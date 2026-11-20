import Foundation
import Compression

struct ZipEntry: Equatable {
    var path: String
    var data: Data
}

enum ZipError: Error, LocalizedError {
    case invalidArchive
    case unsupportedCompression(Int)
    case corruptedEntry(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "Ce fichier n'est pas une archive ZIP valide."
        case .unsupportedCompression(let m): return "Méthode de compression non gérée (\(m))."
        case .corruptedEntry(let p): return "Le fichier « \(p) » de l'archive est endommagé."
        }
    }
}

/// Lecture / écriture ZIP minimale, sans dépendance.
/// Écriture : méthode « stored » (sans compression). Lecture : « stored » et « deflate ».
enum ZipArchive {
    static func write(_ entries: [ZipEntry]) -> Data {
        var output = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(output.count)
            // En-tête local
            output.appendLE(UInt32(0x04034b50))
            output.appendLE(UInt16(20))       // version
            output.appendLE(UInt16(0x0800))   // UTF-8
            output.appendLE(UInt16(0))        // stored
            output.appendLE(UInt16(0))        // heure
            output.appendLE(UInt16(0x21))     // date (1980-01-01)
            output.appendLE(crc)
            output.appendLE(size)
            output.appendLE(size)
            output.appendLE(UInt16(name.count))
            output.appendLE(UInt16(0))
            output.append(name)
            output.append(entry.data)
            // Répertoire central
            central.appendLE(UInt32(0x02014b50))
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(0x0800))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0x21))
            central.appendLE(crc)
            central.appendLE(size)
            central.appendLE(size)
            central.appendLE(UInt16(name.count))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt32(0))
            central.appendLE(offset)
            central.append(name)
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.appendLE(UInt32(0x06054b50))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt32(central.count))
        output.appendLE(centralOffset)
        output.appendLE(UInt16(0))
        return output
    }

    static func read(_ archive: Data) throws -> [ZipEntry] {
        let bytes = [UInt8](archive)
        guard bytes.count >= 22 else { throw ZipError.invalidArchive }
        // Recherche de la fin du répertoire central.
        var eocd = -1
        var i = bytes.count - 22
        while i >= max(0, bytes.count - 65_557) {
            if bytes.u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.invalidArchive }
        let count = Int(bytes.u16(eocd + 10))
        var pos = Int(bytes.u32(eocd + 16))
        var entries: [ZipEntry] = []
        for _ in 0..<count {
            guard pos + 46 <= bytes.count, bytes.u32(pos) == 0x02014b50 else { throw ZipError.invalidArchive }
            let method = Int(bytes.u16(pos + 10))
            let crc = bytes.u32(pos + 16)
            let compSize = Int(bytes.u32(pos + 20))
            let rawSize = Int(bytes.u32(pos + 24))
            let nameLen = Int(bytes.u16(pos + 28))
            let extraLen = Int(bytes.u16(pos + 30))
            let commentLen = Int(bytes.u16(pos + 32))
            let localOffset = Int(bytes.u32(pos + 42))
            guard pos + 46 + nameLen <= bytes.count else { throw ZipError.invalidArchive }
            let name = String(decoding: bytes[(pos + 46)..<(pos + 46 + nameLen)], as: UTF8.self)
            pos += 46 + nameLen + extraLen + commentLen

            guard localOffset + 30 <= bytes.count, bytes.u32(localOffset) == 0x04034b50 else { throw ZipError.invalidArchive }
            let localNameLen = Int(bytes.u16(localOffset + 26))
            let localExtraLen = Int(bytes.u16(localOffset + 28))
            let start = localOffset + 30 + localNameLen + localExtraLen
            guard start + compSize <= bytes.count else { throw ZipError.corruptedEntry(name) }
            if name.hasSuffix("/") { continue }
            let payload = Data(bytes[start..<(start + compSize)])
            let data: Data
            switch method {
            case 0: data = payload
            case 8: data = try inflate(payload, expectedSize: rawSize, name: name)
            default: throw ZipError.unsupportedCompression(method)
            }
            guard CRC32.checksum(data) == crc else { throw ZipError.corruptedEntry(name) }
            entries.append(ZipEntry(path: name, data: data))
        }
        return entries
    }

    private static func inflate(_ data: Data, expectedSize: Int, name: String) throws -> Data {
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, expectedSize, s, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ZipError.corruptedEntry(name) }
        return output
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
    mutating func appendLE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}

private extension Array where Element == UInt8 {
    func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 {
        UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}
