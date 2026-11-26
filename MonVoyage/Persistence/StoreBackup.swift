import Foundation

/// Copies de sécurité de la base avant chaque chargement.
///
/// Chaque ouverture crée une copie datée dans `Backup/AAAAMMJJ-HHMMSS/` ; les 20 plus
/// récentes sont gardées. Les anciennes copies `Backup/*.backup` (versions précédentes de
/// l'appli) ne sont plus jamais modifiées : elles servent à la récupération des voyages.
enum StoreBackup {
    static let keep = 20

    static func isDir(_ url: URL) -> Bool {
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    static var backupDirectory: URL {
        let url = PersistenceController.storeDirectory.appendingPathComponent("Backup", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Une copie de sécurité : dossier + date + noms des fichiers dans ce dossier.
    struct BackupSet: Identifiable {
        let id: String
        let label: String
        let date: Date?
        /// nom de fichier d'origine (ex. MonVoyage.sqlite-wal) → fichier de la copie
        let files: [String: URL]
    }

    /// Copie `X.sqlite`, `-wal`, `-shm` dans un nouveau dossier daté. Ne supprime jamais la base.
    static func backupBeforeLoading(storeURLs: [URL]) {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folder = backupDirectory.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        var copied = false
        for storeURL in storeURLs where fm.fileExists(atPath: storeURL.path) {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: storeURL.path + suffix)
                guard fm.fileExists(atPath: source.path) else { continue }
                do {
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    try fm.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
                    copied = true
                } catch {
                    print("Sauvegarde impossible pour \(source.lastPathComponent) : \(error)")
                }
            }
        }
        if copied { prune() }
    }

    /// Garde les `keep` copies datées les plus récentes (les copies anciennes `.backup` restent).
    private static func prune() {
        let fm = FileManager.default
        let folders = ((try? fm.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { isDir($0) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in folders.dropFirst(keep) { try? fm.removeItem(at: old) }
    }

    /// Toutes les copies disponibles, de la plus récente à la plus ancienne.
    static func backupSets() -> [BackupSet] {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let display = DateFormatter()
        display.locale = Locale(identifier: "fr_FR")
        display.dateFormat = "d MMM yyyy 'à' HH:mm:ss"
        var sets: [BackupSet] = []
        let entries = (try? fm.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for folder in entries where isDir(folder) {
            let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            var map: [String: URL] = [:]
            for f in files { map[f.lastPathComponent] = f }
            guard !map.isEmpty else { continue }
            let date = formatter.date(from: folder.lastPathComponent)
            sets.append(BackupSet(id: folder.lastPathComponent,
                                  label: "Copie du \(date.map { display.string(from: $0) } ?? folder.lastPathComponent)",
                                  date: date, files: map))
        }
        // Ancienne copie unique (versions précédentes de l'appli).
        var legacy: [String: URL] = [:]
        var legacyDate: Date?
        for f in entries where !isDir(f) && f.lastPathComponent.hasSuffix(".backup") {
            legacy[String(f.lastPathComponent.dropLast(".backup".count))] = f
            if f.lastPathComponent == "MonVoyage.sqlite.backup" {
                legacyDate = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }
        }
        if !legacy.isEmpty {
            sets.append(BackupSet(id: "ancienne", label: "Copie d'avant la mise à jour\(legacyDate.map { " (" + display.string(from: $0) + ")" } ?? "")",
                                  date: legacyDate, files: legacy))
        }
        return sets.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Archive .zip de toutes les copies et de la base actuelle (pour l'écran d'erreur).
    static func exportBackupArchive() throws -> URL {
        let fm = FileManager.default
        var entries: [ZipEntry] = []
        func add(_ dir: URL, folder: String) {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                if isDir(file) {
                    if dir == backupDirectory { add(file, folder: "backup/\(file.lastPathComponent)") }
                    continue
                }
                guard file.lastPathComponent.contains("MonVoyage"), let data = try? Data(contentsOf: file) else { continue }
                entries.append(ZipEntry(path: "\(folder)/\(file.lastPathComponent)", data: data))
            }
        }
        add(backupDirectory, folder: "backup")
        add(PersistenceController.storeDirectory, folder: "actuel")
        let zip = ZipArchive.write(entries)
        let url = fm.temporaryDirectory.appendingPathComponent("MonVoyage-sauvegarde.zip")
        try zip.write(to: url, options: .atomic)
        return url
    }
}
