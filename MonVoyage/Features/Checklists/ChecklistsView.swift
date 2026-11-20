import SwiftUI
import CoreData

/// Plusieurs listes par voyage.
struct ChecklistsView: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @State private var newTitle = ""
    @State private var showNew = false

    var body: some View {
        List {
            if trip.checklistList.isEmpty {
                EmptyState(symbol: "checklist", title: "Aucune liste",
                           message: "Valise, documents, avant le départ… créez autant de listes que vous voulez.",
                           actionTitle: "Créer une liste") { showNew = true }
                    .listRowBackground(Color.clear)
            }
            ForEach(trip.checklistList, id: \.objectID) { list in
                NavigationLink {
                    ChecklistDetailView(checklist: list, trip: trip)
                } label: {
                    HStack {
                        IconBubble(symbol: list.symbol ?? "checklist", tint: trip.accent, size: 38)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(list.wTitle)
                            ProgressBar(fraction: list.itemList.isEmpty ? 0 : Double(list.doneCount) / Double(list.itemList.count), tint: trip.accent)
                        }
                        Text("\(list.doneCount)/\(list.itemList.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(trip.checklistList[i]) }
                context.saveIfNeeded()
            }
            .onMove { from, to in
                var lists = trip.checklistList
                lists.move(fromOffsets: from, toOffset: to)
                for (i, l) in lists.enumerated() { l.sortIndex = Int32(i) }
                context.saveIfNeeded()
            }
        }
        .navigationTitle("Checklists")
        .scrollContentBackground(.hidden)
        .groupedBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Label("Nouvelle liste", systemImage: "plus") }
            }
        }
        .alert("Nouvelle liste", isPresented: $showNew) {
            TextField("Titre", text: $newTitle)
            Button("Créer") {
                let list = context.make(Checklist.self, trip: trip)
                list.title = newTitle.isEmpty ? "Liste" : newTitle
                list.symbol = "checklist"
                list.sortIndex = Int32(trip.checklistList.count)
                list.trip = trip
                context.saveIfNeeded()
                newTitle = ""
            }
            Button("Annuler", role: .cancel) { newTitle = "" }
        }
    }
}

struct ChecklistDetailView: View {
    @ObservedObject var checklist: Checklist
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @State private var newItem = ""
    @State private var checkTick = 0
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                ForEach(checklist.itemList, id: \.objectID) { item in
                    ChecklistItemRow(item: item, travelers: trip.travelerList) { checkTick += 1 }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(checklist.itemList[i]) }
                    context.saveIfNeeded()
                }
                .onMove { from, to in
                    var items = checklist.itemList
                    items.move(fromOffsets: from, toOffset: to)
                    for (i, it) in items.enumerated() { it.sortIndex = Int32(i) }
                    context.saveIfNeeded()
                }
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(trip.accent)
                    TextField("Ajouter un élément", text: $newItem)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(addItem)
                }
            } header: {
                Text("\(checklist.doneCount)/\(checklist.itemList.count) fait\(checklist.doneCount > 1 ? "s" : "")")
            }
        }
        .navigationTitle(checklist.wTitle)
        .scrollContentBackground(.hidden)
        .groupedBackground()
        .toolbar { EditButton() }
        .sensoryFeedback(.success, trigger: checkTick)
    }

    private func addItem() {
        let title = newItem.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let item = context.make(ChecklistItem.self, trip: trip)
        item.title = title
        item.sortIndex = Int32(checklist.itemList.count)
        item.checklist = checklist
        context.saveIfNeeded()
        newItem = ""
        focused = true
    }
}

struct ChecklistItemRow: View {
    @ObservedObject var item: ChecklistItem
    let travelers: [Traveler]
    let onCheck: () -> Void
    @Environment(\.managedObjectContext) private var context
    @State private var showDetails = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { item.isDone.toggle() }
                context.saveIfNeeded()
                if item.isDone { onCheck() }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "Décocher" : "Cocher")
            VStack(alignment: .leading, spacing: 2) {
                TextField("Élément", text: Binding(get: { item.title ?? "" }, set: { item.title = $0 }), onCommit: { context.saveIfNeeded() })
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                HStack(spacing: 8) {
                    if let due = item.dueDate {
                        Label(Fmt.day(due), systemImage: "calendar")
                            .foregroundStyle(!item.isDone && DayKey.key(due) < DayKey.key(Date()) ? Color.red : Color.secondary)
                    }
                    if let who = item.assignee { Label(who.wName, systemImage: "person") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button { item.dueDate = item.dueDate == nil ? Date().addingTimeInterval(86400) : nil; context.saveIfNeeded() } label: {
                    Label(item.dueDate == nil ? "Ajouter une échéance" : "Retirer l'échéance", systemImage: "calendar")
                }
                if item.dueDate != nil {
                    Button { showDetails = true } label: { Label("Changer l'échéance", systemImage: "calendar.badge.clock") }
                }
                Divider()
                ForEach(travelers, id: \.objectID) { t in
                    Button { item.assignee = (item.assignee == t ? nil : t); context.saveIfNeeded() } label: {
                        Label(t.wName, systemImage: item.assignee == t ? "checkmark" : "person")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
            .accessibilityLabel("Options de l'élément")
        }
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                DatePicker("Échéance", selection: Binding(get: { item.dueDate ?? Date() }, set: { item.dueDate = $0 }), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { context.saveIfNeeded(); showDetails = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
