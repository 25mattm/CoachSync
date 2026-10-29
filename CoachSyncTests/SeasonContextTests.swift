import XCTest
@testable import CoachSync

final class SeasonContextTests: XCTestCase {

    // MARK: - athleteAge

    func testAthleteAgeIsCalendarYearSubtraction() {
        let dob = dateOfBirth(year: 2010)
        XCTAssertEqual(SeasonContext.athleteAge(for: dob, inYear: 2026), 16)
    }

    func testAthleteAgeDoesNotAdjustForBirthMonth() {
        // Age is purely birth-year subtracted from season year — no month/day cutoff.
        let dob = dateOfBirth(year: 2010, month: 12, day: 31)
        XCTAssertEqual(SeasonContext.athleteAge(for: dob, inYear: 2026), 16)
    }

    // MARK: - ageCategory

    func testAgeCategoryUnderFiveIsNA() {
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2023), inYear: 2026), "N/A") // age 3
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2022), inYear: 2026), "N/A") // age 4
    }

    func testAgeCategoryBoundaryAtFiveIsU10() {
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2021), inYear: 2026), "U10") // age 5
    }

    func testAgeCategoryU10() {
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2018), inYear: 2026), "U10") // age 8
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2016), inYear: 2026), "U10") // age 10
    }

    func testAgeCategoryU12() {
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2015), inYear: 2026), "U12") // age 11
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2014), inYear: 2026), "U12") // age 12
    }

    func testAgeCategoryU14() {
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2013), inYear: 2026), "U14") // age 13
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2012), inYear: 2026), "U14") // age 14
    }

    func testAgeCategoryU16() {
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2011), inYear: 2026), "U16") // age 15
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2010), inYear: 2026), "U16") // age 16
    }

    func testAgeCategoryU18() {
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2009), inYear: 2026), "U18") // age 17
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2008), inYear: 2026), "U18") // age 18
    }

    func testAgeCategoryBoundaryAt19IsSenior() {
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2007), inYear: 2026), "Senior") // age 19
    }

    func testAgeCategorySenior() {
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 2000), inYear: 2026), "Senior") // age 26
        XCTAssertEqual(SeasonContext.ageCategory(for: dateOfBirth(year: 1980), inYear: 2026), "Senior") // age 46
    }

    // MARK: - ageCategoryDisplayOrder

    func testDisplayOrderContainsEveryProducibleCategory() {
        // Age-grouped lists (roster, add-to-team) only render categories that
        // appear in the display order — a missing entry silently hides those
        // athletes, so every value ageCategory(for:) can emit must be present.
        for category in ["N/A", "U10", "U12", "U14", "U16", "U18", "Senior"] {
            XCTAssertTrue(SeasonContext.ageCategoryDisplayOrder.contains(category),
                          "\(category) missing from ageCategoryDisplayOrder")
        }
    }

    // MARK: - dateInterval

    func testDateIntervalCoversFullCalendarYear() {
        let interval = SeasonContext.dateInterval(forYear: 2026)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: interval.start), 2026)
        XCTAssertEqual(cal.component(.month, from: interval.start), 1)
        XCTAssertEqual(cal.component(.day, from: interval.start), 1)
        XCTAssertEqual(cal.component(.year, from: interval.end), 2027)
        XCTAssertEqual(cal.component(.month, from: interval.end), 1)
        XCTAssertEqual(cal.component(.day, from: interval.end), 1)
    }

    // MARK: - contains

    func testContainsDateWithinYear() {
        let mid2026 = date(year: 2026, month: 6, day: 15)
        XCTAssertTrue(SeasonContext.contains(mid2026, inYear: 2026))
        XCTAssertFalse(SeasonContext.contains(mid2026, inYear: 2025))
    }

    func testContainsExcludesJan1OfNextYear() {
        let jan1Next = date(year: 2027, month: 1, day: 1)
        XCTAssertFalse(SeasonContext.contains(jan1Next, inYear: 2026))
    }

    func testContainsIncludesDec31OfSeasonYear() {
        // The exclusive upper bound must still include the last day of the year.
        let dec31 = date(year: 2026, month: 12, day: 31)
        XCTAssertTrue(SeasonContext.contains(dec31, inYear: 2026))
    }

    // MARK: - Helpers

    private func dateOfBirth(year: Int, month: Int = 6, day: Int = 15) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - defaultNewAthleteDateOfBirth

    func testDefaultNewAthleteDateOfBirthIsAU12NotNA() {
        let now = date(year: 2026, month: 10, day: 29)
        let dob = SeasonContext.defaultNewAthleteDateOfBirth(referenceDate: now)
        XCTAssertEqual(dob, date(year: 2014, month: 1, day: 1))
        XCTAssertEqual(SeasonContext.ageCategory(for: dob, inYear: 2026), "U12")
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
