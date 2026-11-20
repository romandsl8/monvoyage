import SwiftUI

/// Affiché si la base ne se charge pas : rien n'est effacé, la sauvegarde peut être exportée.
struct PersistenceErrorView: View {
    let error: Error
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Vos données n'ont pas pu être ouvertes")
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .multilineTextAlignment(.center)
                Text("Rien n'a été effacé. Une copie de sauvegarde a été faite avant l'ouverture. Exportez-la, puis contactez le développeur avec le message ci-dessous.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text(error.localizedDescription)
                    .font(.footnote.monospaced())
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: .rect(cornerRadius: 12))
                    .textSelection(.enabled)
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Partager la sauvegarde", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button {
                        do { exportURL = try StoreBackup.exportBackupArchive() }
                        catch { exportError = error.localizedDescription }
                    } label: {
                        Label("Préparer l'export de la sauvegarde", systemImage: "archivebox")
                    }
                    .buttonStyle(.glassProminent)
                }
                if let exportError { Text(exportError).foregroundStyle(.red).font(.footnote) }
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
    }
}
