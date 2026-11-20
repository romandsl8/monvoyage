import Foundation

/// Copie de sécurité de la base avant chaque chargement.
enum StoreBackup {
    static var backupDirectory: URL {
        let url = PersistenceController.storeDirectory.appendingPathComponent("Backup", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copie `X.sqlite`, `X.sqlite-wal`, `X.sqlite-shm` vers `Backup/X.sqlite.backup`…
    /// Ne supprime jamais la base d'origine.
    static func backupBeforeLoading(storeURLs: [URL]) {
        let fm = FileManager.default
        for storeURL in storeURLs where fm.fileExists(atPath: storeURL.path) {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: storeURL.path + suffix)
                guard fm.fileExists(atPath: source.path) else { continue }
                let target = backupDirectory.appendingPathComponent(source.lastPathComponent + ".backup")
                let temp = backupDirectory.appendingPathComponent(source.lastPathComponent + ".tmp")
                try? fm.removeItem(at: temp)
                do {
                    try fm.copyItem(at: source, to: temp)
                    if fm.fileExists(atPath: target.path) {
                        _ = try fm.replaceItemAt(target, withItemAt: temp)
                    } else {
                        try fm.moveItem(at: temp, to: target)
                    }
                } catch {
                    print("Sauvegarde impossible pour \(source.lastPathComponent) : \(error)")
                }
            }
        }
    }

    /// Archive .zip de la sauvegarde (pour l'écran d'erreur).
    static func exportBackupArchive() throws -> URL {
        let fm = FileManager.default
        var entries: [ZipEntry] = []
        let directories = [backupDirectory, PersistenceController.storeDirectory]
        for dir in directories {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent.contains("MonVoyage") {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue,
                      let data = try? Data(contentsOf: file) else { continue }
                let folder = dir == backupDirectory ? "backup" : "actuel"
                entries.append(ZipEntry(path: "\(folder)/\(file.lastPathComponent)", data: data))
            }
        }
        let zip = ZipArchive.write(entries)
        let url = fm.temporaryDirectory.appendingPathComponent("MonVoyage-sauvegarde.zip")
        try zip.write(to: url, options: .atomic)
        return url
    }
}
