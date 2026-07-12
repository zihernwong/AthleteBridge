import SwiftUI
import UIKit
import MapKit
import CoreLocation

// MARK: - Shared loader / caches

/// Produces an Apple Maps image for an address or coordinate:
/// a Look Around photo when Apple has street-level imagery for the spot,
/// otherwise a map snapshot with a pin. Results are cached in-memory so
/// list rows don't re-geocode or re-render on every appearance.
enum LocationImageLoader {
    private static let imageCache = NSCache<NSString, UIImage>()
    @MainActor private static var coordinateCache: [String: CLLocationCoordinate2D] = [:]
    /// Addresses that failed to geocode — avoid hammering CLGeocoder on scroll.
    @MainActor private static var failedAddresses: Set<String> = []

    enum Style {
        /// Look Around photo, falling back to a map snapshot.
        case auto
        /// Look Around photo only; returns nil when no imagery exists.
        case lookAroundOnly
    }

    @MainActor
    static func loadImage(address: String, coordinate: CLLocationCoordinate2D? = nil, size: CGSize, style: Style = .auto) async -> UIImage? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard coordinate != nil || !trimmed.isEmpty else { return nil }

        let styleKey = (style == .lookAroundOnly) ? "la" : "auto"
        let cacheKey = "\(trimmed)|\(coordinate.map { "\($0.latitude),\($0.longitude)" } ?? "")|\(Int(size.width))x\(Int(size.height))|\(styleKey)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) { return cached }

        guard let coord = await resolveCoordinate(address: trimmed, coordinate: coordinate) else { return nil }

        var image = await lookAroundImage(coordinate: coord, size: size)
        if image == nil, style == .auto {
            image = await mapSnapshotImage(coordinate: coord, size: size)
        }
        if let image = image {
            imageCache.setObject(image, forKey: cacheKey)
        }
        return image
    }

    @MainActor
    private static func resolveCoordinate(address: String, coordinate: CLLocationCoordinate2D?) async -> CLLocationCoordinate2D? {
        if let coordinate = coordinate { return coordinate }
        if let cached = coordinateCache[address] { return cached }
        guard !failedAddresses.contains(address) else { return nil }
        guard let placemarks = try? await CLGeocoder().geocodeAddressString(address),
              let coord = placemarks.first?.location?.coordinate else {
            failedAddresses.insert(address)
            return nil
        }
        coordinateCache[address] = coord
        return coord
    }

    private static func lookAroundImage(coordinate: CLLocationCoordinate2D, size: CGSize) async -> UIImage? {
        let request = MKLookAroundSceneRequest(coordinate: coordinate)
        guard let scene = try? await request.scene else { return nil }
        let options = MKLookAroundSnapshotter.Options()
        options.size = size
        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
        guard let snapshot = try? await snapshotter.snapshot else { return nil }
        return snapshot.image
    }

    private static func mapSnapshotImage(coordinate: CLLocationCoordinate2D, size: CGSize) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        options.size = size
        options.pointOfInterestFilter = .includingAll
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        // Composite a pin at the location since MKMapSnapshotter has no annotations
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            let point = snapshot.point(for: coordinate)
            let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
            if let pin = UIImage(systemName: "mappin.circle.fill", withConfiguration: config)?
                .withTintColor(.systemRed, renderingMode: .alwaysOriginal) {
                pin.draw(in: CGRect(x: point.x - 14, y: point.y - 28, width: 28, height: 28))
            }
        }
    }
}

// MARK: - View

/// Displays an Apple Maps picture (Look Around photo, or map snapshot fallback)
/// for a place. Pass a `coordinate` when known to skip geocoding.
struct LocationSnapshotView: View {
    let address: String
    var coordinate: CLLocationCoordinate2D? = nil
    var height: CGFloat = 140
    /// When true, the view disappears entirely if no Look Around photo exists
    /// (no map fallback) — used next to an existing live map.
    var lookAroundOnly: Bool = false

    @State private var image: UIImage? = nil
    @State private var finishedLoading = false

    var body: some View {
        Group {
            if let image = image {
                // The image lives in an overlay so its natural size can never
                // affect row layout; the container defines the bounds and clips.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay(
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if !finishedLoading && !lookAroundOnly {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay(ProgressView())
            } else if !lookAroundOnly {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "map")
                                .foregroundColor(.secondary)
                            Text("No preview available")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
        .task(id: "\(address)|\(coordinate?.latitude ?? 0),\(coordinate?.longitude ?? 0)") {
            // Render at 1.5x for sharpness; approximate the visible width of a
            // list row (screen minus insets/chevron) so scaledToFill barely crops
            let width = min(UIScreen.main.bounds.width - 80, 560)
            let size = CGSize(width: width * 1.5, height: height * 1.5)
            image = await LocationImageLoader.loadImage(
                address: address,
                coordinate: coordinate,
                size: size,
                style: lookAroundOnly ? .lookAroundOnly : .auto
            )
            finishedLoading = true
        }
    }
}

/// Small fixed-size thumbnail variant for rows and pickers.
struct LocationThumbnailView: View {
    let address: String
    var coordinate: CLLocationCoordinate2D? = nil
    var width: CGFloat = 72
    var height: CGFloat = 56

    @State private var image: UIImage? = nil

    var body: some View {
        Group {
            if let image = image {
                Color.clear
                    .overlay(
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    )
            } else {
                Color(UIColor.secondarySystemBackground)
                    .overlay(
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    )
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: address) {
            image = await LocationImageLoader.loadImage(
                address: address,
                coordinate: coordinate,
                size: CGSize(width: width * 2, height: height * 2)
            )
        }
    }
}
