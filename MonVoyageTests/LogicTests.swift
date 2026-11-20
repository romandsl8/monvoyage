import XCTest
@testable import MonVoyage

final class MoneyTests: XCTestCase {
    func testConversionToEUR() {
        XCTAssertEqual(Money.toEUR(100, currency: "USD", rateEURPerUnit: 0.92), 92)
        XCTAssertEqual(Money.toEUR(10.006, currency: "EUR", rateEURPerUnit: 0.5), 10.01)
        XCTAssertEqual(Money.fromEUR(92, currency: "USD", rateEURPerUnit: 0.92), 100)
    }

    func testParseFrenchAndAmericanFormats() {
        XCTAssertEqual(Money.parse("1 234,56"), 1234.56)
        XCTAssertEqual(Money.parse("1,234.56"), 1234.56)
        XCTAssertEqual(Money.parse("12,5"), 12.5)
        XCTAssertEqual(Money.parse("$12.50"), 12.5)
        XCTAssertEqual(Money.parse("1\u{202F}200,00 €"), 1200)
        XCTAssertNil(Money.parse(""))
    }

    /// Critère : 50 $ + 6,5 % + 20 % de pourboire.
    func testTaxAndTip() {
        let r = TaxTipCalculator.compute(subtotal: 50, taxRate: 0.065, tipRate: 0.20, rateEURPerUnit: 0.9)
        XCTAssertEqual(r.tax, 3.25)
        XCTAssertEqual(r.tip, 10)
        XCTAssertEqual(r.total, 63.25)
        XCTAssertEqual(r.totalEUR, 56.93)
    }
}

final class PaymentMathTests: XCTestCase {
    func testSplitEquallyWithRemainderOnLast() {
        XCTAssertEqual(PaymentMath.splitEqually(900, count: 3), [300, 300, 300])
        XCTAssertEqual(PaymentMath.splitEqually(100, count: 3), [33.33, 33.33, 33.34])
        XCTAssertEqual(PaymentMath.splitEqually(10, count: 0), [])
    }

    /// Critère : vol à 1 200 € avec 300 € d'acompte et le solde en 3 fois.
    func testPlanWithDeposit() {
        let plan = PaymentMath.plan(total: 1200, deposit: 300, depositIsPercent: false, depositDate: Date(),
                                    count: 3, firstInstallmentDate: Date())
        XCTAssertEqual(plan.count, 4)
        XCTAssertEqual(plan[0].kind, .deposit)
        XCTAssertEqual(plan[0].amount, 300)
        XCTAssertEqual(plan.dropFirst().map(\.amount), [300, 300, 300])
        XCTAssertEqual(PaymentMath.scheduleGap(total: 1200, installments: plan.map(\.amount)), 0)
    }

    func testPlanWithPercentDeposit() {
        let plan = PaymentMath.plan(total: 1000, deposit: 30, depositIsPercent: true, depositDate: Date(),
                                    count: 2, firstInstallmentDate: Date())
        XCTAssertEqual(plan.map(\.amount), [300, 350, 350])
    }

    func testScheduleGapWarning() {
        XCTAssertEqual(PaymentMath.scheduleGap(total: 1200, installments: [300, 300, 300]), 300)
    }

    func testInstallmentStatuses() {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)
        let tomorrow = now.addingTimeInterval(86400)
        XCTAssertEqual(PaymentMath.status(isPaid: false, dueDate: yesterday, now: now), .overdue)
        XCTAssertEqual(PaymentMath.status(isPaid: false, dueDate: tomorrow, now: now), .upcoming)
        XCTAssertEqual(PaymentMath.status(isPaid: false, dueDate: now, now: now), .upcoming)
        XCTAssertEqual(PaymentMath.status(isPaid: true, dueDate: yesterday, now: now), .paid)
    }

    func testExpenseStatus() {
        let paid = InstallmentValue(amount: 10, isPaid: true, paidAmountEUR: 10, dueDate: nil)
        let unpaid = InstallmentValue(amount: 10, isPaid: false, paidAmountEUR: 0, dueDate: nil)
        XCTAssertEqual(PaymentMath.expenseStatus(installments: [], isSettled: true), .settled)
        XCTAssertEqual(PaymentMath.expenseStatus(installments: [], isSettled: false), .planned)
        XCTAssertEqual(PaymentMath.expenseStatus(installments: [unpaid, unpaid], isSettled: false), .planned)
        XCTAssertEqual(PaymentMath.expenseStatus(installments: [paid, unpaid], isSettled: false), .partial)
        XCTAssertEqual(PaymentMath.expenseStatus(installments: [paid, paid], isSettled: false), .settled)
    }

    func testRemainingDecreases() {
        var values = Array(repeating: InstallmentValue(amount: 300, isPaid: false, paidAmountEUR: 0, dueDate: nil), count: 4)
        XCTAssertEqual(PaymentMath.remainingEUR(totalEUR: 1200, rate: 1, installments: values, isSettled: false), 1200)
        values[0].isPaid = true; values[0].paidAmountEUR = 300
        XCTAssertEqual(PaymentMath.remainingEUR(totalEUR: 1200, rate: 1, installments: values, isSettled: false), 900)
        XCTAssertEqual(PaymentMath.paidEUR(totalEUR: 1200, rate: 1, installments: values, isSettled: false), 300)
    }
}

final class DailyBudgetTests: XCTestCase {
    func testPerDayAndColors() {
        let green = DailyBudgetCalculator.compute(onSiteBudgetEUR: 1000, spentBeforeTodayEUR: 200, spentTodayEUR: 50, daysRemaining: 8)
        XCTAssertEqual(green.perDayEUR, 100)
        XCTAssertEqual(green.status, 0)
        let orange = DailyBudgetCalculator.compute(onSiteBudgetEUR: 1000, spentBeforeTodayEUR: 200, spentTodayEUR: 90, daysRemaining: 8)
        XCTAssertEqual(orange.status, 1)
        let red = DailyBudgetCalculator.compute(onSiteBudgetEUR: 1000, spentBeforeTodayEUR: 200, spentTodayEUR: 130, daysRemaining: 8)
        XCTAssertEqual(red.status, 2)
        XCTAssertEqual(red.remainingEUR, 670)
    }

    func testZeroDaysIsSafe() {
        let r = DailyBudgetCalculator.compute(onSiteBudgetEUR: 300, spentBeforeTodayEUR: 0, spentTodayEUR: 0, daysRemaining: 0)
        XCTAssertEqual(r.perDayEUR, 300)
    }
}

final class FlightTimeTests: XCTestCase {
    /// CDG 10:30 (heure de Paris, été) → MCO 14:15 (heure d'Orlando) = 9 h 45 de vol.
    func testDurationAcrossTimeZones() throws {
        let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let orlando = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let dep = try XCTUnwrap(FlightTime.date(year: 2027, month: 7, day: 1, hour: 10, minute: 30, timeZone: paris))
        let arr = try XCTUnwrap(FlightTime.date(year: 2027, month: 7, day: 1, hour: 14, minute: 15, timeZone: orlando))
        let duration = FlightTime.duration(departure: dep, arrival: arr)
        XCTAssertEqual(duration, 9 * 3600 + 45 * 60)
        XCTAssertEqual(FlightTime.durationText(duration), "9 h 45")
        XCTAssertEqual(Fmt.time(arr, timeZone: orlando), "14:15")
        XCTAssertEqual(FlightTime.offsetHours(from: paris, to: orlando, at: dep), -6)
    }

    func testWinterOffset() throws {
        let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let orlando = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let dep = try XCTUnwrap(FlightTime.date(year: 2027, month: 1, day: 10, hour: 10, minute: 0, timeZone: paris))
        let arr = try XCTUnwrap(FlightTime.date(year: 2027, month: 1, day: 10, hour: 14, minute: 0, timeZone: orlando))
        XCTAssertEqual(FlightTime.durationText(FlightTime.duration(departure: dep, arrival: arr)), "10 h")
    }

    func testKeepWallTime() throws {
        let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let orlando = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let d = try XCTUnwrap(FlightTime.date(year: 2027, month: 7, day: 1, hour: 10, minute: 30, timeZone: paris))
        XCTAssertEqual(Fmt.time(FlightTime.keepWallTime(d, from: paris, to: orlando), timeZone: orlando), "10:30")
    }

    func testAirlineAndAirportTables() {
        XCTAssertEqual(Airlines.code(fromFlightNumber: "AF 090"), "AF")
        XCTAssertEqual(Airlines.code(fromFlightNumber: "u21234"), "U2")
        XCTAssertEqual(Airlines.name(for: "AF"), "Air France")
        XCTAssertEqual(Airports.timeZoneID(for: "mco"), "America/New_York")
        XCTAssertNil(Airports.timeZoneID(for: "XYZ"))
    }
}

final class ReceiptParserTests: XCTestCase {
    func testUSReceipt() {
        let lines = [
            "SUNSHINE DINER",
            "123 Main Street Orlando FL",
            "05/14/2027 12:41",
            "Burger 12.99",
            "Fries 4.50",
            "SUBTOTAL 17.49",
            "TAX 1.14",
            "TOTAL 18.63",
            "VISA ****1234 18.63"
        ]
        let r = ReceiptParser.parse(lines: lines)
        XCTAssertEqual(r.total, 18.63)
        XCTAssertEqual(r.merchant, "Sunshine Diner")
        XCTAssertEqual(r.date.map { DayKey.key($0) }, "2027-05-14")
    }

    func testAmountDueOnNextLine() {
        let r = ReceiptParser.parse(lines: ["Universal Studios Store", "Sub Total", "$45.00", "Amount Due", "$47.93"])
        XCTAssertEqual(r.total, 47.93)
        XCTAssertEqual(r.currency, "USD")
    }

    func testFrenchReceipt() {
        let r = ReceiptParser.parse(lines: ["BOULANGERIE DU PORT", "14/05/2027", "TOTAL TTC 1 234,50 €"])
        XCTAssertEqual(r.total, 1234.5)
        XCTAssertEqual(r.date.map { DayKey.key($0) }, "2027-05-14")
        XCTAssertEqual(r.currency, "EUR")
    }

    func testFallbackLargestAmount() {
        XCTAssertEqual(ReceiptParser.parse(lines: ["Shop", "Item 3.00", "Item 9.50"]).total, 9.5)
    }
}

final class WeatherLogicTests: XCTestCase {
    func testForecastWithin16Days() {
        let now = Date()
        let in10 = DayKey.key(now.addingTimeInterval(10 * 86400))
        XCTAssertEqual(WeatherLogic.source(for: in10, now: now), .forecast)
        XCTAssertEqual(WeatherLogic.source(for: DayKey.key(now), now: now), .forecast)
    }

    func testNormalsBeyond16Days() {
        let now = DayKey.date(fromKey: "2027-01-10")!
        XCTAssertEqual(WeatherLogic.source(for: "2027-03-01", now: now), .normals(previousYearKey: "2026-03-01"))
        XCTAssertEqual(WeatherLogic.previousYearKey("2028-02-29"), "2027-02-28")
    }

    func testCrowdScale() {
        XCTAssertEqual(CrowdScale.label(for: 1), "Très calme")
        XCTAssertEqual(CrowdScale.label(for: 6), "Modéré")
        XCTAssertEqual(CrowdScale.label(for: 10), "Très chargé")
    }
}

final class NotificationPlannerTests: XCTestCase {
    func testKeepsClosest64FutureNotifications() {
        let now = Date()
        var candidates: [PlannedNotification] = []
        for i in 0..<100 {
            candidates.append(PlannedNotification(id: "n\(i)", title: "t", body: "b", date: now.addingTimeInterval(Double(100 - i) * 3600)))
        }
        candidates.append(PlannedNotification(id: "past", title: "t", body: "b", date: now.addingTimeInterval(-60)))
        let selected = NotificationPlanner.select(candidates, now: now)
        XCTAssertEqual(selected.count, 64)
        XCTAssertFalse(selected.contains { $0.id == "past" })
        XCTAssertEqual(selected.first?.id, "n99")
        XCTAssertTrue(zip(selected, selected.dropFirst()).allSatisfy { $0.date <= $1.date })
    }
}

final class ZipArchiveTests: XCTestCase {
    func testCRC32() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    func testRoundTrip() throws {
        let entries = [ZipEntry(path: "monvoyage.json", data: Data("{\"a\":1}".utf8)),
                       ZipEntry(path: "files/photo.bin", data: Data((0..<5000).map { UInt8($0 % 251) })),
                       ZipEntry(path: "vide.txt", data: Data())]
        let archive = ZipArchive.write(entries)
        XCTAssertEqual(try ZipArchive.read(archive), entries)
    }

    func testInvalidArchive() {
        XCTAssertThrowsError(try ZipArchive.read(Data("pas un zip".utf8)))
    }
}
