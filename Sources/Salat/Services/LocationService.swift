import CoreLocation
import MapKit
import PrayerKit

enum LocationError: Error {
    case denied
    case failed(String)
}

/// One-shot current-location lookup plus place search, both resolved to a `SavedLocation`.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool {
        let s = manager.authorizationStatus
        return s == .denied || s == .restricted
    }

    func currentLocation() async throws -> SavedLocation {
        let location = try await requestLocation()
        return await resolve(location)
    }

    private func requestLocation() async throws -> CLLocation {
        if isDenied { throw LocationError.denied }
        continuation?.resume(throwing: LocationError.failed("superseded"))
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch manager.authorizationStatus {
            case .authorized, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.finish(.failure(LocationError.denied))
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.finish(.success(loc)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in
            self.finish(.failure(denied ? LocationError.denied : LocationError.failed(error.localizedDescription)))
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let c = continuation else { return }
        continuation = nil
        c.resume(with: result)
    }

    /// Reverse-geocodes to a human name and the place's own time zone.
    func resolve(_ location: CLLocation) async -> SavedLocation {
        let coords = Coordinates(latitude: location.coordinate.latitude,
                                 longitude: location.coordinate.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark?.locality ?? placemark?.subAdministrativeArea ?? placemark?.administrativeArea
            ?? String(format: "%.3f, %.3f", coords.latitude, coords.longitude)
        return SavedLocation(name: name,
                             country: placemark?.country,
                             countryCode: placemark?.isoCountryCode,
                             coordinates: coords,
                             timeZoneID: (placemark?.timeZone ?? .current).identifier)
    }

    /// Searches cities/places worldwide.
    static func search(_ query: String) async -> [SavedLocation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        guard let response = try? await MKLocalSearch(request: request).start() else {
            return await geocodeFallback(trimmed)
        }
        var seen = Set<String>()
        var results: [SavedLocation] = []
        for item in response.mapItems {
            let pm = item.placemark
            let name = pm.locality ?? item.name ?? pm.administrativeArea ?? trimmed
            let key = "\(name)|\(pm.country ?? "")"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(SavedLocation(
                name: name,
                country: [pm.administrativeArea, pm.country]
                    .compactMap { $0 }.filter { $0 != name }.joined(separator: ", "),
                countryCode: pm.isoCountryCode,
                coordinates: Coordinates(latitude: pm.coordinate.latitude, longitude: pm.coordinate.longitude),
                timeZoneID: (item.timeZone ?? .current).identifier))
        }
        return results.isEmpty ? await geocodeFallback(trimmed) : results
    }

    private static func geocodeFallback(_ query: String) async -> [SavedLocation] {
        guard let marks = try? await CLGeocoder().geocodeAddressString(query) else { return [] }
        return marks.compactMap { pm in
            guard let loc = pm.location else { return nil }
            return SavedLocation(name: pm.locality ?? pm.name ?? query,
                                 country: pm.country,
                                 countryCode: pm.isoCountryCode,
                                 coordinates: Coordinates(latitude: loc.coordinate.latitude,
                                                          longitude: loc.coordinate.longitude),
                                 timeZoneID: (pm.timeZone ?? .current).identifier)
        }
    }
}
