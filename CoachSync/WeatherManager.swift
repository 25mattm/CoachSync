/// WeatherKit dashboard weather card. iOS-only (WeatherKit entitlement + location usage string
/// exist only on the CoachSync iOS target, not CoachSyncMac) — this file lives in the shared
/// PBXFileSystemSynchronizedRootGroup that both targets compile, so it is wrapped in
/// `#if os(iOS)` in its entirety to compile to nothing on the Mac target.
#if os(iOS)

import Foundation
import Observation
import WeatherKit
import CoreLocation
import MapKit

/// Transient device-local weather snapshot cached in `UserDefaults` for a cold/offline launch.
/// Not a SwiftData model — this is not synced coaching data. All fields are pre-converted to
/// metric at capture time so the UI and cache never re-convert or depend on locale.
struct CurrentConditions: Codable, Equatable {
    var temperatureC: Double
    var feelsLikeC: Double
    /// 0-1 range as WeatherKit provides it; the UI multiplies by 100 for display.
    var humidity: Double
    var windSpeedKmh: Double
    var windDirectionDegrees: Double
    var uvIndex: Int
    var uvCategory: String
    var visibilityKm: Double
    var dewPointC: Double
    var conditionText: String
    /// An SF Symbol name from WeatherKit — used directly by the UI, no manual icon mapping.
    var symbolName: String
    /// Reverse-geocoded; nil if geocoding failed or has not run.
    var placeName: String?
    var fetchedAt: Date

    var windCompass: String {
        WeatherManager.compassDirection(fromDegrees: windDirectionDegrees)
    }
}

@MainActor
@Observable
final class WeatherManager {

    enum Status: Equatable {
        case idle
        case loading
        case loaded(CurrentConditions)
        case denied
        case unavailable
    }

    private(set) var status: Status = .idle

    static let staleInterval: TimeInterval = 15 * 60

    private static let cacheKey = "dashboardWeatherCache"

    /// Guards against overlapping fetches from `refresh()`/`refreshIfStale()`.
    private var inFlight = false

    /// Lazily constructed so a `CLLocationManager` is never created unless `refresh()` actually
    /// runs — `init()` must stay free of location/network side effects.
    /// `lazy var` cannot be used directly on an `@Observable` class's stored property (the
    /// macro rewrites storage into an init-accessor-backed computed property), so the
    /// lazy-init behavior is hand-rolled here via an `@ObservationIgnored` backing field —
    /// this is not UI-observed state anyway.
    @ObservationIgnored
    private var _locationProvider: OneShotLocationProvider?
    private var locationProvider: OneShotLocationProvider {
        if let existing = _locationProvider {
            return existing
        }
        let created = OneShotLocationProvider()
        _locationProvider = created
        return created
    }

    /// Reads the persisted cache only — no `CLLocationManager`, no network call — so a cold
    /// offline launch can show last-known weather immediately.
    init() {
        if let cached = loadCache() {
            status = .loaded(cached)
        }
    }

    /// No-ops if a fetch is already in flight, or if a fresh reading is already showing.
    /// Falls through to `refresh()` even when `.denied`, so the card can recover automatically
    /// after the coach grants permission in Settings and returns to the app.
    func refreshIfStale() async {
        guard !inFlight else { return }
        if case let .loaded(conditions) = status, !WeatherManager.isStale(fetchedAt: conditions.fetchedAt) {
            return
        }
        await refresh()
    }

    func refresh() async {
        // Re-entrancy guard here (not just in refreshIfStale) — the card's
        // "Weather unavailable" tap calls refresh() directly, and overlapping
        // fetches would orphan the location provider's single continuation slot.
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let hadCachedReading: Bool
        if case .loaded = status {
            hadCachedReading = true
        } else {
            hadCachedReading = false
            status = .loading
        }

        do {
            let location = try await locationProvider.currentLocation()
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location, including: .current)

            // CLGeocoder.reverseGeocodeLocation and MKMapItem.placemark are both
            // deprecated as of iOS 26 in favor of addressRepresentations. cityName is
            // the plain city ("Springfield") — cityWithContext would add the region. City only,
            // by design: no street-address fallback (the card is glanceable in public).
            // Best-effort via `try?`: any failure just falls back to "Current Location".
            var placeName: String?
            if let request = MKReverseGeocodingRequest(location: location),
               let mapItem = try? await request.mapItems.first {
                placeName = mapItem.addressRepresentations?.cityName
            }

            let conditions = CurrentConditions(
                temperatureC: weather.temperature.converted(to: .celsius).value,
                feelsLikeC: weather.apparentTemperature.converted(to: .celsius).value,
                humidity: weather.humidity,
                windSpeedKmh: weather.wind.speed.converted(to: .kilometersPerHour).value,
                windDirectionDegrees: weather.wind.direction.converted(to: .degrees).value,
                uvIndex: weather.uvIndex.value,
                uvCategory: String(describing: weather.uvIndex.category),
                visibilityKm: weather.visibility.converted(to: .kilometers).value,
                dewPointC: weather.dewPoint.converted(to: .celsius).value,
                conditionText: weather.condition.description,
                symbolName: weather.symbolName,
                placeName: placeName,
                fetchedAt: .now
            )

            saveCache(conditions)
            status = .loaded(conditions)
        } catch let error as OneShotLocationProvider.LocationError where error == .denied {
            // Actionable beats stale — this wins even over an existing cached reading.
            status = .denied
        } catch {
            // Network failure, WeatherKit error, etc. Keep a good cached reading on-screen (the
            // UI renders an age label to convey staleness) rather than overwrite it with an error.
            if !hadCachedReading {
                status = .unavailable
            }
        }
    }

    /// Pure, independently unit-testable. Normalizes into 0..<360 then buckets into 16 compass points.
    static func compassDirection(fromDegrees degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                           "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        var normalized = degrees.truncatingRemainder(dividingBy: 360)
        if normalized < 0 {
            normalized += 360
        }
        let index = Int((normalized / 22.5).rounded()) % 16
        return directions[index]
    }

    /// Pure, independently unit-testable via the injectable `now` parameter. Exactly at the
    /// stale-interval boundary (900s) a reading is NOT yet stale — only strictly past it.
    static func isStale(fetchedAt: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(fetchedAt) > staleInterval
    }

    private func loadCache() -> CurrentConditions? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        // A decode failure (garbage/missing data) is simply "no cache", not a crash.
        return try? JSONDecoder().decode(CurrentConditions.self, from: data)
    }

    private func saveCache(_ conditions: CurrentConditions) {
        // Default date encoding strategy — .iso8601 would lose precision on round-trip.
        guard let data = try? JSONEncoder().encode(conditions) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}

/// Kept as a separate class from `WeatherManager` (not merging `NSObject` conformance into the
/// `@Observable` class) to avoid `@Observable`/`NSObject` interaction edge cases.
///
/// `@MainActor` so the `continuation` slot is only ever touched from one executor: without it,
/// `currentLocation()` (a nonisolated async method) would run on the global concurrent executor
/// while CoreLocation delivers delegate callbacks on the main thread the manager was created on.
/// The delegate methods are `nonisolated` to satisfy the protocol and hop back in via
/// `MainActor.assumeIsolated` — safe because callbacks arrive on the creating (main) run loop.
@MainActor
private final class OneShotLocationProvider: NSObject, CLLocationManagerDelegate {

    enum LocationError: Error, Equatable {
        case denied
        case unavailable
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        // Reduced accuracy is sufficient for weather — do not request full accuracy.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
    }

    func currentLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                let pending = self.continuation
                self.continuation = nil
                pending?.resume(throwing: LocationError.denied)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                let pending = continuation
                continuation = nil
                pending?.resume(throwing: LocationError.denied)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            let pending = continuation
            continuation = nil
            if let location = locations.first {
                pending?.resume(returning: location)
            } else {
                pending?.resume(throwing: LocationError.unavailable)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            let pending = continuation
            continuation = nil
            pending?.resume(throwing: LocationError.unavailable)
        }
    }
}

#endif
