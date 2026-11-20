import XCTest
import CoreData
@testable import MonVoyage

/// Tests avec une base Core Data en mémoire.
final class DataTests: XCTestCase {
    var controller: PersistenceController!
    var context: NSManagedObjectContext { controller.viewContext }

    override func setUp() {
        super.setUp()
        controller = PersistenceController(inMemory: true)
    }

    override func tearDown() {
        controller = nil
        super.tearDown()
    }

    private func makeTrip() -> Trip {
        let trip = TripFactory.createTrip(in: context, name: "Floride", start: Date(), end: Date().addingTimeInterval(9 * 86400))
        trip.totalBudgetEUR = 6000
        trip.city = "Orlando"
        return trip
    }

    func testNewTripHasDefaultCategoriesAndTwoTravelers() {
        let trip = makeTrip()
        XCTAssertEqual(trip.categoryList.map { $0.name ?? "" },
                       ["Vols", "Hébergement", "Billets parcs", "Express Pass", "Repas", "Transport", "Shopping", "Souvenirs", "Divers"])
        XCTAssertEqual(trip.travelerList.count, 2)
        XCTAssertNotNil(trip.id)
        XCTAssertEqual(trip.days.count, 10)
    }

    /// Critère : vol à 1 200 € (300 € d'acompte + 3 × 300 €), le reste à payer baisse à chaque versement payé.
    func testFlightScheduleRemainingDecreases() {
        let trip = makeTrip()
        let expense = context.make(Expense.self, trip: trip)
        expense.trip = trip
        expense.title = "Vol Paris – Orlando"
        expense.amount = 1200
        expense.currency = "EUR"
        expense.rateUsed = 1
        expense.amountEUR = 1200
        expense.isSettled = false
        let plan = PaymentMath.plan(total: 1200, deposit: 300, depositIsPercent: false, depositDate: Date(),
                                    count: 3, firstInstallmentDate: Date().addingTimeInterval(30 * 86400))
        for (i, p) in plan.enumerated() {
            let inst = context.make(PaymentInstallment.self, trip: trip)
            inst.kindRaw = p.kind.rawValue
            inst.amount = p.amount
            inst.dueDate = p.dueDate
            inst.sortIndex = Int32(i)
            inst.expense = expense
        }
        XCTAssertTrue(context.saveIfNeeded())

        XCTAssertEqual(expense.installmentList.filter { $0.kind == .installment }.map(\.amount), [300, 300, 300])
        XCTAssertEqual(BudgetSummary(trip: trip).remainingEUR, 1200)
        XCTAssertEqual(expense.status, .planned)

        var expected = 1200.0
        for inst in expense.installmentList {
            inst.markPaid(rateEURPerUnit: 1)
            expected -= 300
            XCTAssertEqual(BudgetSummary(trip: trip).remainingEUR, expected)
        }
        XCTAssertEqual(expense.status, .settled)
        XCTAssertEqual(BudgetSummary(trip: trip).paidEUR, 1200)
    }

    /// Un versement en USD marqué payé est converti au taux du jour de paiement.
    func testUSDInstallmentUsesPaymentDayRate() {
        let trip = makeTrip()
        let expense = context.make(Expense.self, trip: trip)
        expense.trip = trip
        expense.amount = 200
        expense.currency = "USD"
        expense.rateUsed = 0.9
        expense.amountEUR = 180
        let inst = context.make(PaymentInstallment.self, trip: trip)
        inst.amount = 200
        inst.expense = expense
        XCTAssertEqual(inst.estimatedEUR, 180)
        inst.markPaid(rateEURPerUnit: 0.95)
        XCTAssertEqual(inst.paidAmountEUR, 190)
        XCTAssertEqual(inst.paidRate, 0.95)
    }

    /// Critère : 50 $ + 6,5 % + 20 % s'enregistre au bon montant en EUR.
    func testTaxTipExpenseInEUR() {
        let trip = makeTrip()
        let r = TaxTipCalculator.compute(subtotal: 50, taxRate: trip.taxRate, tipRate: trip.defaultTipRate, rateEURPerUnit: 0.92)
        let expense = context.make(Expense.self, trip: trip)
        expense.trip = trip
        expense.amount = r.total
        expense.currency = "USD"
        expense.rateUsed = 0.92
        expense.amountEUR = Money.toEUR(r.total, currency: "USD", rateEURPerUnit: 0.92)
        XCTAssertEqual(expense.amount, 63.25)
        XCTAssertEqual(expense.amountEUR, 58.19)
    }

    func testDailyBudgetDuringTrip() {
        let trip = makeTrip()
        for cat in trip.categoryList where !cat.isPreDeparture { cat.plannedEUR = 200 }   // 5 × 200 = 1 000 € sur place
        let flight = context.make(Expense.self, trip: trip)
        flight.trip = trip
        flight.amountEUR = 900
        flight.date = Date()
        flight.category = trip.category(named: "Vols")
        let meal = context.make(Expense.self, trip: trip)
        meal.trip = trip
        meal.amountEUR = 40
        meal.date = Date()
        meal.category = trip.category(named: "Repas")
        // Budget total 6 000 € − vol (avant le voyage) 900 € = 5 100 € sur place, sur 10 jours.
        let daily = BudgetSummary.daily(trip: trip, now: Date())
        XCTAssertEqual(daily?.daysRemaining, 10)
        XCTAssertEqual(daily?.perDayEUR, 510)
        XCTAssertEqual(daily?.spentTodayEUR, 40)
        XCTAssertEqual(daily?.status, 0)
        XCTAssertEqual(daily?.isBeforeTrip, false)

        // Sans budget total : somme des budgets des catégories sur place (5 × 200 €).
        trip.totalBudgetEUR = 0
        XCTAssertEqual(BudgetSummary.daily(trip: trip, now: Date())?.perDayEUR, 100)
    }

    /// Le moment choisi (avant / pendant) prime sur la catégorie.
    func testExpensePhase() {
        let trip = makeTrip()
        let expense = context.make(Expense.self, trip: trip)
        expense.trip = trip
        expense.amountEUR = 300
        expense.category = trip.category(named: "Vols")
        XCTAssertTrue(expense.isPreTrip)                 // auto : catégorie « avant départ »
        expense.phaseRaw = ExpensePhase.duringTrip.rawValue
        XCTAssertFalse(expense.isPreTrip)
        expense.category = trip.category(named: "Repas")
        expense.phaseRaw = ExpensePhase.beforeTrip.rawValue
        XCTAssertTrue(expense.isPreTrip)
        let summary = BudgetSummary(trip: trip)
        XCTAssertEqual(summary.preTripEUR, 300)
        XCTAssertEqual(summary.duringTripEUR, 0)
    }

    /// Avant le départ : montant prévu par jour, pas de « dépensé aujourd'hui ».
    func testDailyBudgetBeforeTrip() throws {
        let start = Date().addingTimeInterval(30 * 86400)
        let trip = TripFactory.createTrip(in: context, name: "Plus tard", start: start, end: start.addingTimeInterval(9 * 86400))
        trip.totalBudgetEUR = 3000
        let hotel = context.make(Expense.self, trip: trip)
        hotel.trip = trip
        hotel.amountEUR = 1000
        hotel.date = Date()
        hotel.phaseRaw = ExpensePhase.beforeTrip.rawValue
        let daily = try XCTUnwrap(BudgetSummary.daily(trip: trip, now: Date()))
        XCTAssertTrue(daily.isBeforeTrip)
        XCTAssertEqual(daily.daysRemaining, 10)
        XCTAssertEqual(daily.perDayEUR, 200)
        XCTAssertEqual(daily.spentTodayEUR, 0)
    }

    /// Critère : un export puis un import restaurent un voyage à l'identique, avec de nouveaux UUID.
    func testExportImportRoundTrip() throws {
        let trip = makeTrip()
        let expense = context.make(Expense.self, trip: trip)
        expense.trip = trip
        expense.title = "Hôtel"
        expense.amount = 1500
        expense.amountEUR = 1500
        expense.category = trip.category(named: "Hébergement")
        expense.paidBy = trip.travelerList.first
        expense.receiptImage = Data([1, 2, 3, 4, 5])
        let inst = context.make(PaymentInstallment.self, trip: trip)
        inst.amount = 500
        inst.expense = expense
        inst.markPaid(rateEURPerUnit: 1)
        let reservation = context.make(Reservation.self, trip: trip)
        reservation.trip = trip
        reservation.kindRaw = ReservationKind.flight.rawValue
        reservation.confirmationNumber = "ABC123"
        let segment = context.make(FlightSegment.self, trip: trip)
        segment.flightNumber = "AF090"
        segment.departureDate = Date()
        segment.reservation = reservation
        let attachment = context.make(Attachment.self, trip: trip)
        attachment.data = Data(repeating: 7, count: 2048)
        attachment.mimeKind = "pdf"
        attachment.name = "billet"
        attachment.reservation = reservation
        let list = context.make(Checklist.self, trip: trip)
        list.title = "Valise"
        list.trip = trip
        let item = context.make(ChecklistItem.self, trip: trip)
        item.title = "Passeports"
        item.isDone = true
        item.checklist = list
        item.assignee = trip.travelerList.last
        XCTAssertTrue(context.saveIfNeeded())

        let archive = try ExportImportService.makeArchive(trips: [trip])
        let imported = try ExportImportService.importArchive(archive, into: context)
        let copy = try XCTUnwrap(imported.first)

        XCTAssertNotEqual(copy.objectID, trip.objectID)
        XCTAssertNotEqual(copy.id, trip.id)
        XCTAssertEqual(copy.name, "Floride")
        XCTAssertEqual(copy.city, "Orlando")
        XCTAssertEqual(copy.totalBudgetEUR, 6000)
        XCTAssertEqual(copy.startDate, trip.startDate)
        XCTAssertEqual(copy.categoryList.count, 9)
        XCTAssertEqual(copy.travelerList.count, 2)

        let copiedExpense = try XCTUnwrap(copy.expenseList.first)
        XCTAssertEqual(copiedExpense.title, "Hôtel")
        XCTAssertEqual(copiedExpense.category?.name, "Hébergement")
        XCTAssertEqual(copiedExpense.category?.trip, copy)
        XCTAssertEqual(copiedExpense.paidBy?.trip, copy)
        XCTAssertEqual(copiedExpense.receiptImage, Data([1, 2, 3, 4, 5]))
        XCTAssertEqual(copiedExpense.installmentList.first?.paidAmountEUR, 500)
        XCTAssertNotEqual(copiedExpense.id, expense.id)

        let copiedReservation = try XCTUnwrap(copy.reservationList.first)
        XCTAssertEqual(copiedReservation.confirmationNumber, "ABC123")
        XCTAssertEqual(copiedReservation.segmentList.first?.flightNumber, "AF090")
        XCTAssertEqual(copiedReservation.attachmentList.first?.data, Data(repeating: 7, count: 2048))

        let copiedItem = try XCTUnwrap(copy.checklistList.first?.itemList.first)
        XCTAssertEqual(copiedItem.title, "Passeports")
        XCTAssertTrue(copiedItem.isDone)
        XCTAssertEqual(copiedItem.assignee?.trip, copy)

        // L'original est intact.
        XCTAssertEqual(trip.expenseList.count, 1)
        XCTAssertEqual(TripFactory.fetchTrips(in: context).count, 2)
    }

    func testDuplicateAddsSuffix() throws {
        let trip = makeTrip()
        XCTAssertTrue(context.saveIfNeeded())
        let copy = try XCTUnwrap(ExportImportService.duplicate(trip, in: context))
        XCTAssertEqual(copy.name, "Floride (copie)")
    }
}
