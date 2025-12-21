import Foundation
import CoreLocation

/// ZipToState resolves a US ZIP code to a state abbreviation (e.g. "MN").
/// It uses CLGeocoder to geocode the ZIP code and caches results to avoid repeated network calls.
final class ZipToState {
    static let shared = ZipToState()
    private let geocoder = CLGeocoder()
    private var cache: [String: String] = [:] // zip -> state abbreviation (may store "" for unknown)
    private let queue = DispatchQueue(label: "zipToState.queue")

    /// Normalize ZIP to first 5 digits if possible
    private func normalize(zip: String) -> String {
        let digits = zip.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.count >= 5 {
            let start = digits.prefix(5)
            return String(start)
        }
        return digits
    }

    /// Resolve state abbreviation for a given ZIP code. Completion is called on main queue.
    /// If resolution fails, completion receives nil.
    func stateForZip(_ zip: String, completion: @escaping (String?) -> Void) {
        let z = normalize(zip: zip)
        queue.async {
            if let cached = self.cache[z] {
                // empty string represents cached unknown
                let out = cached.isEmpty ? nil : cached
                DispatchQueue.main.async { completion(out) }
                return
            }

            // Use CLGeocoder to geocode the ZIP code
            self.geocoder.geocodeAddressString(z) { placemarks, error in
                var result: String? = nil
                if let pm = placemarks?.first {
                    if let admin = pm.administrativeArea, !admin.isEmpty {
                        result = admin
                    }
                }

                // cache result (store empty string for nil)
                self.queue.async {
                    self.cache[z] = result ?? ""
                }

                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
    }
}
