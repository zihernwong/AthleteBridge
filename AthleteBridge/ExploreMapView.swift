import SwiftUI
import MapKit
import CoreLocation

/// Discovery map: badminton venues (green pins) and coaches (blue pins),
/// geocoded from place addresses and coach zip codes. Mirrors the Android Explore Map.
struct ExploreMapView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    struct MapPin: Identifiable, Equatable {
        enum PinType { case place, coach }
        let id: String
        let title: String
        let subtitle: String
        let coordinate: CLLocationCoordinate2D
        let type: PinType

        static func == (lhs: MapPin, rhs: MapPin) -> Bool { lhs.id == rhs.id }
    }

    @State private var pins: [MapPin] = []
    @State private var isLoading = true
    @State private var selectedPlace: PlaceToPlay? = nil
    @State private var selectedCoach: Coach? = nil
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.9778, longitude: -93.2650),
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
        )
    )

    var body: some View {
        VStack(spacing: 0) {
            // Legend
            HStack(spacing: 16) {
                legendDot(color: Color("LogoGreen"), label: "Places to Play")
                legendDot(color: Color("LogoBlue"), label: "Coaches")
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.8) }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Map(position: $cameraPosition) {
                ForEach(pins) { pin in
                    Annotation(pin.title, coordinate: pin.coordinate) {
                        Button {
                            handleTap(pin)
                        } label: {
                            Circle()
                                .fill(pin.type == .place ? Color("LogoGreen") : Color("LogoBlue"))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(radius: 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("Explore Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if firestore.placesToPlay.isEmpty { firestore.fetchPlacesToPlay() }
            if firestore.coaches.isEmpty { firestore.fetchCoaches() }
            buildPins()
        }
        .onChange(of: firestore.placesToPlay) { _, _ in buildPins() }
        .onChange(of: firestore.coaches) { _, _ in buildPins() }
        .sheet(item: $selectedPlace) { place in
            NavigationStack {
                PlaceDetailView(place: place)
                    .environmentObject(firestore)
                    .environmentObject(auth)
            }
        }
        .sheet(item: $selectedCoach) { coach in
            NavigationStack {
                CoachDetailView(coach: coach)
                    .environmentObject(firestore)
                    .environmentObject(auth)
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(label).font(.caption)
        }
    }

    private func handleTap(_ pin: MapPin) {
        switch pin.type {
        case .place:
            selectedPlace = firestore.placesToPlay.first { $0.id == pin.id }
        case .coach:
            selectedCoach = firestore.coaches.first { $0.id == pin.id }
        }
    }

    // MARK: - Geocoding

    /// Session-scoped geocode cache: address/zip -> coordinate (or nil for failed lookups)
    private static var geocodeCache: [String: CLLocationCoordinate2D?] = [:]
    private static let geocoder = CLGeocoder()

    private func buildPins() {
        var queries: [(id: String, title: String, subtitle: String, query: String, type: MapPin.PinType)] = []

        for place in firestore.placesToPlay where !place.address.isEmpty {
            queries.append((place.id, place.name, place.address, place.address, .place))
        }
        for coach in firestore.coaches where coach.hasValidName {
            let query = (coach.zipCode?.isEmpty == false ? coach.zipCode : coach.city) ?? ""
            guard !query.isEmpty else { continue }
            let subtitle = [coach.city, coach.hourlyRate.map { "$\(Int($0))/hr" }]
                .compactMap { $0 }.joined(separator: " · ")
            queries.append((coach.id, coach.name, subtitle, query, .coach))
        }

        guard !queries.isEmpty else { isLoading = false; return }
        isLoading = true
        geocodeNext(queries: queries, index: 0, accumulated: [])
    }

    /// Geocode sequentially — CLGeocoder rejects concurrent requests.
    private func geocodeNext(queries: [(id: String, title: String, subtitle: String, query: String, type: MapPin.PinType)],
                             index: Int,
                             accumulated: [MapPin]) {
        var acc = accumulated
        guard index < queries.count else {
            applyPins(acc)
            return
        }
        let q = queries[index]

        func advance(with coordinate: CLLocationCoordinate2D?) {
            if var coord = coordinate {
                // Spread pins sharing the same geocoded point (e.g. same zip) so all stay tappable
                let clashes = acc.filter {
                    abs($0.coordinate.latitude - coord.latitude) < 0.0001 &&
                    abs($0.coordinate.longitude - coord.longitude) < 0.0001
                }.count
                if clashes > 0 { coord.latitude += Double(clashes) * 0.0015 }
                acc.append(MapPin(id: q.id, title: q.title, subtitle: q.subtitle, coordinate: coord, type: q.type))
            }
            geocodeNext(queries: queries, index: index + 1, accumulated: acc)
        }

        if let cached = Self.geocodeCache[q.query] {
            advance(with: cached)
            return
        }
        Self.geocoder.geocodeAddressString(q.query) { placemarks, _ in
            let coord = placemarks?.first?.location?.coordinate
            Self.geocodeCache[q.query] = coord
            DispatchQueue.main.async { advance(with: coord) }
        }
    }

    private func applyPins(_ newPins: [MapPin]) {
        pins = newPins
        isLoading = false
        guard !newPins.isEmpty else { return }
        let lats = newPins.map { $0.coordinate.latitude }
        let lons = newPins.map { $0.coordinate.longitude }
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.1, (lats.max()! - lats.min()!) * 1.4),
            longitudeDelta: max(0.1, (lons.max()! - lons.min()!) * 1.4)
        )
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}
