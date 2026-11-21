import SwiftUI

/// Choix de plusieurs parcs dans la liste Queue-Times, regroupés par exploitant
/// (Walt Disney Attractions, Universal Parks & Resorts, Six Flags…).
struct ParkMultiPicker: View {
    @Binding var selection: [QTPark]
    /// Parcs déjà présents dans le voyage : affichés comme cochés et non modifiables.
    var alreadyAdded: Set<Int64> = []
    /// Ajout d'un parc sans données en ligne (facultatif).
    var onManualAdd: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var queueTimes: QueueTimesService
    @State private var query = ""
    @State private var manualName = ""

    private var selectedIDs: Set<Int64> { Set(selection.map(\.id)) }

    private var groups: [QTCompany] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return queueTimes.companies }
        return queueTimes.companies.compactMap { company in
            if company.name.localizedCaseInsensitiveContains(q) { return company }
            let parks = company.parks.filter { $0.name.localizedCaseInsensitiveContains(q) }
            return parks.isEmpty ? nil : QTCompany(id: company.id, name: company.name, parks: parks)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !selection.isEmpty && query.isEmpty {
                    Section("Sélection (\(selection.count))") {
                        ForEach(selection) { park in row(park) }
                    }
                }
                if let onManualAdd, query.isEmpty {
                    Section {
                        HStack {
                            TextField("Nom du parc", text: $manualName)
                            Button("Ajouter") {
                                onManualAdd(manualName.trimmingCharacters(in: .whitespaces))
                                manualName = ""
                                dismiss()
                            }
                            .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } header: {
                        Text("Parc absent de la liste")
                    } footer: {
                        Text("Sans temps d'attente en direct.")
                    }
                }
                ForEach(groups) { company in
                    Section(company.name) {
                        ForEach(company.parks) { park in row(park) }
                    }
                }
                Section { QueueTimesCredit() }
            }
            .overlay {
                if queueTimes.companies.isEmpty {
                    if queueTimes.lastError != nil {
                        ContentUnavailableView {
                            Label("Liste indisponible", systemImage: "wifi.slash")
                        } description: {
                            Text("Connectez-vous à internet pour choisir vos parcs.")
                        } actions: {
                            Button("Réessayer") { Task { await queueTimes.loadParks(force: true) } }
                        }
                    } else {
                        ProgressView("Chargement des parcs…")
                    }
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Parc, ville ou groupe (Disney, Six Flags…)")
            .navigationTitle("Choisir les parcs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .task { await queueTimes.loadParks() }
        }
    }

    private func row(_ park: QTPark) -> some View {
        let added = alreadyAdded.contains(park.id)
        let selected = added || selectedIDs.contains(park.id)
        return Button {
            guard !added else { return }
            if let i = selection.firstIndex(where: { $0.id == park.id }) {
                selection.remove(at: i)
            } else {
                selection.append(park)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(park.name).foregroundStyle(.primary)
                    if added { Text("Déjà dans le voyage").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
