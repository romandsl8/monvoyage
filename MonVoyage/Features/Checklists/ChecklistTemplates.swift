import Foundation
import CoreData

/// Listes types proposées pour un voyage : préparatifs (avec échéance avant le départ) et valise.
enum ChecklistTemplates {
    struct Item {
        let title: String
        /// Échéance en jours avant le départ (nil = sans échéance).
        var daysBefore: Int? = nil
    }
    struct Template {
        let title: String
        let symbol: String
        let items: [Item]
    }

    static let all: [Template] = [
        Template(title: "À préparer", symbol: "doc.text.fill", items: [
            Item(title: "Vérifier la validité des passeports", daysBefore: 90),
            Item(title: "Demander l'ESTA (États-Unis) ou le visa", daysBefore: 45),
            Item(title: "Souscrire ou vérifier l'assurance voyage", daysBefore: 30),
            Item(title: "Permis de conduire international si location de voiture", daysBefore: 30),
            Item(title: "Réserver les billets des parcs", daysBefore: 30),
            Item(title: "Prévenir la banque du voyage / plafonds de carte", daysBefore: 7),
            Item(title: "Forfait téléphone ou eSIM à l'étranger", daysBefore: 7),
            Item(title: "Télécharger les applis des parcs et cartes hors ligne", daysBefore: 3),
            Item(title: "Faire l'enregistrement en ligne du vol", daysBefore: 1),
            Item(title: "Imprimer ou enregistrer les réservations", daysBefore: 1),
            Item(title: "Prévoir le trajet vers l'aéroport", daysBefore: 7)
        ]),
        Template(title: "Valise", symbol: "suitcase.fill", items: [
            Item(title: "Passeports et ESTA imprimés"),
            Item(title: "Cartes bancaires et un peu d'espèces"),
            Item(title: "Permis de conduire"),
            Item(title: "Chargeurs et câbles"),
            Item(title: "Adaptateur de prise (américaine)"),
            Item(title: "Batterie externe"),
            Item(title: "Médicaments et ordonnances"),
            Item(title: "Crème solaire"),
            Item(title: "Lunettes de soleil et casquette"),
            Item(title: "K-way ou poncho (orages)"),
            Item(title: "Maillots de bain"),
            Item(title: "Chaussures confortables pour marcher"),
            Item(title: "Gourde"),
            Item(title: "Trousse de toilette"),
            Item(title: "Vêtements pour chaque jour")
        ]),
        Template(title: "Avant de partir de la maison", symbol: "house.fill", items: [
            Item(title: "Sortir les poubelles"),
            Item(title: "Vider le réfrigérateur"),
            Item(title: "Débrancher les appareils"),
            Item(title: "Arroser les plantes / confier les clés"),
            Item(title: "Fermer fenêtres, volets et eau"),
            Item(title: "Message d'absence (travail)")
        ])
    ]

    /// Ajoute les listes types qui n'existent pas encore dans le voyage (comparaison par titre).
    @discardableResult
    static func add(to trip: Trip, in context: NSManagedObjectContext) -> Int {
        let existing = Set(trip.checklistList.map { $0.wTitle.lowercased() })
        var index = Int32(trip.checklistList.count)
        var added = 0
        for template in all where !existing.contains(template.title.lowercased()) {
            let list = context.make(Checklist.self, trip: trip)
            list.title = template.title
            list.symbol = template.symbol
            list.sortIndex = index
            list.trip = trip
            for (i, item) in template.items.enumerated() {
                let entry = context.make(ChecklistItem.self, trip: trip)
                entry.title = item.title
                entry.sortIndex = Int32(i)
                if let days = item.daysBefore, let start = trip.startDate {
                    let due = DayKey.noon(start.addingTimeInterval(-Double(days) * 86400))
                    entry.dueDate = max(due, DayKey.noon(Date()))
                }
                entry.checklist = list
            }
            index += 1
            added += 1
        }
        return added
    }

    static func hasAll(_ trip: Trip) -> Bool {
        let existing = Set(trip.checklistList.map { $0.wTitle.lowercased() })
        return all.allSatisfy { existing.contains($0.title.lowercased()) }
    }
}
