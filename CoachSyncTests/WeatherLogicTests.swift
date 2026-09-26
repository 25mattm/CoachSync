import XCTest
@testable import CoachSync

final class WeatherLogicTests: XCTestCase {
    func testCompassCardinalCenters() {
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: 0), "N")
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: 90), "E")
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: 180), "S")
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: 270), "W")
    }

    func testCompassBucketBoundaries() {
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: 11.24), "N")
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: 11.25), "NNE")
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: 22.5), "NNE")
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: 348.74), "NNW")
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: 348.75), "N")
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: 360), "N")
    }

    func testCompassNormalizesOutOfRange() {
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: -0.1), "N")
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: 405), "NE")
        XCTAssertEqual(WeatherManager.compassDirection(fromDegrees: 720), "N")
    }

    func testFreshReadingIsNotStale() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let fetchedAt = base
        let now = base.addingTimeInterval(899)
        XCTAssertFalse(WeatherManager.isStale(fetchedAt: fetchedAt, now: now))
    }

    func testExactThresholdIsNotStale() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let fetchedAt = base
        let now = base.addingTimeInterval(900)
        XCTAssertFalse(WeatherManager.isStale(fetchedAt: fetchedAt, now: now))
    }

    func testJustOverThresholdIsStale() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let fetchedAt = base
        let now = base.addingTimeInterval(901)
        XCTAssertTrue(WeatherManager.isStale(fetchedAt: fetchedAt, now: now))
    }

    func testCurrentConditionsRoundTripsThroughJSON() throws {
        let original = CurrentConditions(
            temperatureC: 21.5,
            feelsLikeC: 20.1,
            humidity: 0.62,
            windSpeedKmh: 14.3,
            windDirectionDegrees: 202.5,
            uvIndex: 6,
            uvCategory: "high",
            visibilityKm: 12.8,
            dewPointC: 11.4,
            conditionText: "Partly Cloudy",
            symbolName: "cloud.sun.fill",
            placeName: "Springfield",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CurrentConditions.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testDecodeGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
        XCTAssertThrowsError(try JSONDecoder().decode(CurrentConditions.self, from: garbage))
    }
}
