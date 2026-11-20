import SwiftUI
import CoreData

/// Création / modification d'une activité (heure saisie en heure locale du voyage).
struct ActivityEditorView: View {
    @ObservedObject var trip: Trip
    let activityID: NSManagedObjectID?
    let dayKey: String?

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nav: TripNavigation

    @State private var title = ""
    @State private var place = ""
    @State private var kind: ActivityKind = .other
    @State private var day = ""
    @State private var time = Date()
    @State private var note = ""
    @State private var costText = ""
    @State private var parkID: NSManagedObjectID?
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $title)
                    Picker("Type", selection: $kind) {
                        ForEach(ActivityKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Jour", selection: $day) {
                        ForEach(trip.dayKeys, id: \.self) { key in
                            Text(DayKey.date(fromKey: key).map { Fmt.day($0) } ?? key).tag(key)
                        }
                    }
                    DatePicker("Heure (locale)", selection: $time, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, trip.tripTimeZone)
                    TextField("Lieu", text: $place)
                }
                if kind == .park || kind == .attraction || !trip.parkList.isEmpty {
                    Section("Parc") {
                        Picker("Parc associé", selection: $parkID) {
                            Text("Aucun").tag(NSManagedObjectID?.none)
                            ForEach(trip.parkList, id: \.objectID) { Text($0.wName).tag(NSManagedObjectID?.some($0.objectID)) }
                        }
                    }
                }
                Section {
                    AmountField(title: "Coût estimé", text: $costText, currency: "EUR")
                    TextField("Note", text: $note, axis: .vertical)
                } footer: {
                    Text("Le coût est indicatif. Pour le compter dans le budget, créez la dépense depuis cette fiche.")
                }
                if let activityID {
                    Section {
                        Button {
                            nav.present(.newExpense(ExpensePrefill(title: title, amount: Money.parse(costText), currency: "EUR",
                                                                   categoryName: kind == .restaurant ? "Repas" : nil,
                                                                   date: DayKey.date(fromKey: day) ?? Date(), activityID: activityID)))
                        } label: { Label("Créer la dépense correspondante", systemImage: "eurosign.circle") }
                        Button("Supprimer l'activité", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(activityID == nil ? "Nouvelle activité" : "Activité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer", action: save).disabled(day.isEmpty) }
            }
            .confirmationDialog("Supprimer cette activité ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let activityID, let a = try? context.existingObject(with: activityID) { context.delete(a); context.saveIfNeeded() }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        day = dayKey ?? trip.dayKeys.first ?? DayKey.key(Date())
        time = DayKey.combine(dayKey: day, hour: 9, minute: 0, timeZone: trip.tripTimeZone) ?? Date()
        if let activityID, let a = try? context.existingObject(with: activityID) as? PlanActivity {
            title = a.title ?? ""
            place = a.place ?? ""
            kind = a.kind
            day = a.dayKey ?? day
            time = a.time ?? time
            note = a.note ?? ""
            costText = a.cost > 0 ? Fmt.number(a.cost) : ""
            parkID = a.park?.objectID
        }
    }

    private func save() {
        let a: PlanActivity
        if let activityID, let existing = try? context.existingObject(with: activityID) as? PlanActivity {
            a = existing
        } else {
            a = context.make(PlanActivity.self, trip: trip)
            a.trip = trip
        }
        a.title = title
        a.place = place
        a.kindRaw = kind.rawValue
        a.day = DayKey.date(fromKey: day)
        let comps = DayKey.calendar(trip.tripTimeZone).dateComponents([.hour, .minute], from: time)
        a.time = DayKey.combine(dayKey: day, hour: comps.hour ?? 9, minute: comps.minute ?? 0, timeZone: trip.tripTimeZone)
        a.note = note
        a.cost = Money.parse(costText) ?? 0
        a.park = parkID.flatMap { try? context.existingObject(with: $0) as? Park }
        context.saveIfNeeded()
        dismiss()
    }
}
