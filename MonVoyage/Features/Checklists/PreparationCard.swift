import SwiftUI
import CoreData

/// Carte « Préparatifs » de l'onglet Aujourd'hui : avancement de chaque liste
/// et prochains éléments à cocher directement depuis la carte.
struct PreparationCard: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var nav: TripNavigation
    @FetchRequest private var items: FetchedResults<ChecklistItem>
    @State private var checkTick = 0

    init(trip: Trip) {
        self.trip = trip
        _items = FetchRequest(
            sortDescriptors: [NSSortDescriptor(key: "sortIndex", ascending: true)],
            predicate: NSPredicate(format: "checklist.trip == %@", trip),
            animation: .snappy)
    }

    private var lists: [Checklist] { trip.checklistList }

    var body: some View {
        let all = Array(items)
        let done = all.filter(\.isDone).count
        Card {
            HStack {
                CardTitle(title: "Préparatifs", symbol: "checklist", tint: .mint)
                Spacer()
                if !all.isEmpty {
                    Text("\(done)/\(all.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if lists.isEmpty {
                Text("Tout ce qu'il faut préparer et ne pas oublier dans la valise, à cocher au fur et à mesure.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    withAnimation { ChecklistTemplates.add(to: trip, in: context) }
                    context.saveIfNeeded()
                } label: {
                    Label("Ajouter les listes prêtes", systemImage: "wand.and.stars")
                }
                .buttonStyle(.glass).font(.caption)
            } else if done == all.count && !all.isEmpty {
                Label("Tout est prêt, bon voyage !", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            } else {
                ProgressBar(fraction: all.isEmpty ? 0 : Double(done) / Double(all.count), tint: .mint)
                ForEach(lists, id: \.objectID) { list in
                    listBlock(list, items: all.filter { $0.checklist == list })
                }
            }
            if !lists.isEmpty {
                Button { nav.open(.checklists) } label: {
                    Label("Voir toutes les listes", systemImage: "chevron.right")
                }
                .buttonStyle(.glass).font(.caption)
            }
        }
        .sensoryFeedback(.success, trigger: checkTick)
    }

    @ViewBuilder
    private func listBlock(_ list: Checklist, items: [ChecklistItem]) -> some View {
        let remaining = items.filter { !$0.isDone }
            .sorted { ($0.dueDate ?? .distantFuture, $0.sortIndex) < ($1.dueDate ?? .distantFuture, $1.sortIndex) }
        let doneCount = items.count - remaining.count
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                IconBubble(symbol: list.symbol ?? "checklist", tint: .mint, size: 30)
                Text(list.wTitle).font(.subheadline.weight(.semibold))
                Spacer()
                if remaining.isEmpty {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("\(doneCount)/\(items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
            .onTapGesture { nav.open(.checklists) }
            ForEach(remaining.prefix(3), id: \.objectID) { item in
                PrepItemRow(item: item) {
                    withAnimation(.snappy) { item.isDone = true }
                    context.saveIfNeeded()
                    checkTick += 1
                }
            }
            if remaining.count > 3 {
                Text("+ \(remaining.count - 3) autre\(remaining.count - 3 > 1 ? "s" : "")")
                    .font(.caption).foregroundStyle(.secondary).padding(.leading, 40)
            }
        }
        .padding(.top, 4)
    }
}

/// Un élément à cocher dans la carte.
private struct PrepItemRow: View {
    @ObservedObject var item: ChecklistItem
    let onCheck: () -> Void

    var body: some View {
        Button(action: onCheck) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title ?? "Élément").font(.subheadline).foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let due = item.dueDate {
                        let late = DayKey.key(due) < DayKey.key(Date())
                        Text(late ? "En retard · \(Fmt.day(due))" : "Avant le \(Fmt.day(due))")
                            .font(.caption).foregroundStyle(late ? Color.red : Color.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title ?? "Élément")
        .accessibilityHint("Touchez pour cocher")
    }
}
