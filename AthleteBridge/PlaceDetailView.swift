import SwiftUI
import MapKit
import CoreLocation
import FirebaseAuth

struct PlaceDetailView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @StateObject private var locationManager = LocationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    let place: PlaceToPlay

    private struct ChatSheetId: Identifiable { let id: String }
    @State private var presentedChat: ChatSheetId? = nil

    // Geocoding state
    @State private var placeCoordinate: CLLocationCoordinate2D? = nil
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var isGeocoding = true
    @State private var geocodeError: String? = nil

    // Driving time state
    @State private var drivingTime: String? = nil
    @State private var drivingDistance: String? = nil
    @State private var isDrivingTimeLoading = false
    @State private var drivingTimeError: String? = nil
    @State private var hasCalculatedDrivingTime = false
    @State private var isJoining = false

    // Club photo upload (admins only)
    @State private var showClubPhotoPicker = false
    @State private var selectedClubImage: UIImage? = nil
    @State private var isUploadingClubPhoto = false
    @State private var clubPhotoError: String? = nil

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private var currentUid: String { auth.user?.uid ?? "" }

    private var locationAuthorized: Bool {
        locationManager.authorizationStatus == .authorizedWhenInUse ||
        locationManager.authorizationStatus == .authorizedAlways
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                clubPhotoSection
                placeInfoSection
                // Street-level Apple Maps photo when Look Around imagery exists;
                // collapses silently otherwise (the live map below covers that case)
                if livePlace.photoURL == nil && !place.address.isEmpty {
                    LocationSnapshotView(address: place.address, height: 180, lookAroundOnly: true)
                }
                mapSection
                drivingTimeSection

                clubSection

                announcementsSection

                eventsSection

                if !livePlace.admins.isEmpty {
                    adminsSection
                }

                if placeCoordinate != nil || !place.address.isEmpty {
                    openInMapsButton
                }
            }
            .padding()
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedChat) { sheet in
            NavigationStack {
                ChatView(chatId: sheet.id)
                    .environmentObject(firestore)
            }
        }
        .onAppear {
            geocodePlaceAddress()
            requestLocationIfNeeded()
            firestore.fetchSignupEvents()
            firestore.fetchPlacesToPlay()
            firestore.fetchClubAnnouncements(placeId: place.id)
        }
        .onChange(of: locationManager.currentLocation?.latitude) { _ in
            calculateDrivingTimeIfPossible()
        }
        .onChange(of: locationManager.authorizationStatus) { status in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                firestore.setLocationPermissionGranted(true)
                locationManager.requestLocation()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                firestore.fetchSignupEvents()
                firestore.fetchPlacesToPlay()
            }
        }
    }

    // MARK: - Place Info Section

    private var placeInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !place.address.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(Color("LogoGreen"))
                    Text(place.address)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if !place.pricePerSession.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle")
                        .foregroundColor(Color("LogoGreen"))
                    Text("Price per Session")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(place.pricePerSession)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }

            if !place.playingTimes.isEmpty {
                WeeklyScheduleDisplay(schedule: place.playingTimes)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Group {
            if let coord = placeCoordinate {
                Map(coordinateRegion: $region, annotationItems: [PlaceMapPin(coordinate: coord)]) { pin in
                    MapMarker(coordinate: pin.coordinate, tint: Color("LogoGreen"))
                }
                .frame(height: 200)
                .cornerRadius(12)
                .allowsHitTesting(false)
            } else if isGeocoding {
                HStack {
                    Spacer()
                    ProgressView("Loading map...")
                    Spacer()
                }
                .frame(height: 200)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            } else if geocodeError != nil {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("Could not find location on map")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(height: 200)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Driving Time Section

    private var drivingTimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Driving Time")
                .font(.headline)

            if !locationAuthorized && locationManager.authorizationStatus == .notDetermined {
                Button(action: {
                    locationManager.requestPermission()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "location")
                            .foregroundColor(Color("LogoGreen"))
                        Text("Enable location to see driving time")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            } else if !locationAuthorized {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash")
                        .foregroundColor(.secondary)
                    Text("Location access denied. Enable in Settings to see driving time.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            } else if isDrivingTimeLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Calculating route...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            } else if let time = drivingTime {
                HStack(spacing: 12) {
                    Image(systemName: "car.fill")
                        .font(.title2)
                        .foregroundColor(Color("LogoGreen"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(time)
                            .font(.title3)
                            .fontWeight(.semibold)
                        if let distance = drivingDistance {
                            Text(distance)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("from your current location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            } else if let error = drivingTimeError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            } else if locationAuthorized && locationManager.currentLocation == nil {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Getting your location...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Club Photo

    /// Club profile picture with an admin-only change control. Hidden entirely
    /// for non-admins when no photo has been uploaded.
    @ViewBuilder
    private var clubPhotoSection: some View {
        let photoURL = livePlace.photoURL.flatMap { URL(string: $0) }
        if photoURL != nil || isContact {
            VStack(alignment: .leading, spacing: 8) {
                if let url = photoURL {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .overlay(
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Color(UIColor.secondarySystemBackground)
                                        .overlay(ProgressView())
                                }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if isContact {
                    Button {
                        showClubPhotoPicker = true
                    } label: {
                        Label(photoURL == nil ? "Add Club Photo" : "Change Club Photo",
                              systemImage: "camera.fill")
                            .font(.subheadline)
                    }
                    .disabled(isUploadingClubPhoto)
                    if isUploadingClubPhoto {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Uploading photo…").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    if let err = clubPhotoError {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                }
            }
            .sheet(isPresented: $showClubPhotoPicker) {
                PhotoPicker(selectedImage: $selectedClubImage)
            }
            .onChange(of: selectedClubImage) { image in
                guard let image = image else { return }
                uploadClubPhoto(image)
            }
        }
    }

    private func uploadClubPhoto(_ image: UIImage) {
        clubPhotoError = nil
        let resized = image.resizeMaintainingAspectRatio(targetSize: CGSize(width: 1280, height: 1280))
        guard let jpegData = resized.jpegData(compressionQuality: 0.75) else {
            clubPhotoError = "Failed processing image"
            selectedClubImage = nil
            return
        }
        isUploadingClubPhoto = true
        firestore.uploadClubPhoto(placeId: place.id, imageData: jpegData) { err in
            DispatchQueue.main.async {
                isUploadingClubPhoto = false
                selectedClubImage = nil
                if let err = err {
                    clubPhotoError = err.localizedDescription
                } else {
                    firestore.showToast("Club photo updated")
                }
            }
        }
    }

    // MARK: - Club Section

    private var livePlace: PlaceToPlay {
        firestore.placesToPlay.first { $0.id == place.id } ?? place
    }
    private var isMember: Bool {
        livePlace.members.contains { $0.id == currentUid }
    }
    private var isPending: Bool {
        livePlace.pendingMembers.contains { $0.id == currentUid }
    }
    private var isContact: Bool {
        livePlace.isAdmin(currentUid)
    }

    private var clubSection: some View {
        let p = livePlace
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Club")
                    .font(.headline)
                Spacer()
                Text("\(p.members.count) member\(p.members.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if isMember || isContact {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(Color("LogoGreen"))
                    Text(isContact ? "Club Admin" : "You're a member")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Color("LogoGreen"))
                    Spacer()
                    if !isContact && isMember {
                        Button("Leave") {
                            firestore.leaveClub(placeId: p.id)
                        }
                        .font(.subheadline)
                        .foregroundColor(.red)
                    }
                }
                .padding()
                .background(Color("LogoGreen").opacity(0.1))
                .cornerRadius(12)
            } else if isPending {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.orange)
                    Text("Request pending")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            } else {
                Button {
                    isJoining = true
                    firestore.requestToJoinClub(placeId: p.id) { _ in
                        DispatchQueue.main.async { isJoining = false }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isJoining {
                            ProgressView()
                                .padding(.trailing, 6)
                        }
                        Label("Request to Join Club", systemImage: "person.badge.plus")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(Color("LogoGreen"))
                    .cornerRadius(12)
                }
                .disabled(isJoining)
                .buttonStyle(PlainButtonStyle())
            }

            // Show member names
            if !p.members.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(p.members.prefix(5)) { member in
                        HStack(spacing: 6) {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(member.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if p.members.count > 5 {
                        Text("+ \(p.members.count - 5) more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Announcements Section

    private static let announcementDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private var placeAnnouncements: [ClubAnnouncement] {
        firestore.clubAnnouncements[place.id] ?? []
    }

    private var announcementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Announcements")
                    .font(.headline)
                Spacer()
                if !placeAnnouncements.isEmpty {
                    NavigationLink {
                        ClubAnnouncementsView(place: livePlace)
                            .environmentObject(firestore)
                    } label: {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundColor(Color("LogoGreen"))
                    }
                }
            }

            if placeAnnouncements.isEmpty {
                HStack {
                    Image(systemName: "megaphone")
                        .foregroundColor(.secondary)
                    Text("No announcements yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            } else {
                ForEach(placeAnnouncements.prefix(3)) { announcement in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(announcement.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(announcement.body)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        HStack {
                            Text(announcement.senderName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(Self.announcementDateFormatter.string(from: announcement.createdAt))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - Events Section

    private var eventsForPlace: [SignupEvent] {
        let now = Date()
        return firestore.signupEvents
            .filter { $0.placeId == place.id && $0.eventDate >= now }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Upcoming Events")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    SignupEventsView(place: place)
                        .environmentObject(firestore)
                        .environmentObject(auth)
                } label: {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(Color("LogoGreen"))
                }
            }

            if eventsForPlace.isEmpty {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundColor(.secondary)
                    Text("No upcoming events")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            } else {
                ForEach(eventsForPlace.prefix(3)) { event in
                    NavigationLink {
                        SignupEventDetailView(event: event)
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Text(Self.dateFormatter.string(from: event.eventDate))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(event.isFull ? "Full" : "\(event.spotsRemaining) left")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(event.isFull ? .red : Color("LogoGreen"))
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Club Admins Section

    private var adminsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(livePlace.admins.count == 1 ? "Club Admin" : "Club Admins")
                .font(.headline)

            ForEach(livePlace.admins) { admin in
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(Color("LogoGreen"))
                    Text(admin.name.isEmpty ? "Club Admin" : admin.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    if admin.id != currentUid {
                        Button(action: { openChat(withUid: admin.id) }) {
                            Image(systemName: "message.fill")
                                .font(.title3)
                                .foregroundColor(Color("LogoBlue"))
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Open in Apple Maps

    private var openInMapsButton: some View {
        Button(action: openInAppleMaps) {
            HStack {
                Spacer()
                Label("Open in Apple Maps", systemImage: "map.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color("LogoGreen"))
                Spacer()
            }
            .padding(.vertical, 12)
            .background(Color("LogoGreen").opacity(0.12))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Actions

    private func requestLocationIfNeeded() {
        if locationAuthorized {
            locationManager.requestLocation()
        } else if locationManager.authorizationStatus == .notDetermined {
            // Will show the prompt in the driving time section
        }
    }

    private func geocodePlaceAddress() {
        guard !place.address.isEmpty else {
            isGeocoding = false
            geocodeError = "No address provided"
            return
        }
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(place.address) { placemarks, error in
            DispatchQueue.main.async {
                isGeocoding = false
                if error != nil {
                    geocodeError = "Could not find location"
                    return
                }
                guard let location = placemarks?.first?.location else {
                    geocodeError = "Could not find location"
                    return
                }
                placeCoordinate = location.coordinate
                region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
                calculateDrivingTimeIfPossible()
            }
        }
    }

    private func calculateDrivingTimeIfPossible() {
        guard !hasCalculatedDrivingTime else { return }
        guard let destCoord = placeCoordinate else { return }
        guard let userCoord = locationManager.currentLocation else { return }

        hasCalculatedDrivingTime = true
        isDrivingTimeLoading = true

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userCoord))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            DispatchQueue.main.async {
                isDrivingTimeLoading = false
                if error != nil {
                    drivingTimeError = "Could not calculate driving time"
                    return
                }
                guard let route = response?.routes.first else {
                    drivingTimeError = "No route found"
                    return
                }
                let minutes = Int(route.expectedTravelTime / 60)
                let miles = route.distance / 1609.34
                if minutes < 60 {
                    drivingTime = "\(minutes) min"
                } else {
                    let hours = minutes / 60
                    let remainingMinutes = minutes % 60
                    drivingTime = "\(hours) hr \(remainingMinutes) min"
                }
                drivingDistance = String(format: "%.1f mi", miles)
            }
        }
    }

    private func openInAppleMaps() {
        if let coord = placeCoordinate {
            let placemark = MKPlacemark(coordinate: coord)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = place.name
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        } else if !place.address.isEmpty {
            let encoded = place.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "http://maps.apple.com/?daddr=\(encoded)&dirflg=d") {
                UIApplication.shared.open(url)
            }
        }
    }

    private func openChat(withUid otherUid: String) {
        guard !currentUid.isEmpty else {
            firestore.showToast("Please sign in to message")
            return
        }
        let expectedChatId = [currentUid, otherUid].sorted().joined(separator: "_")
        presentedChat = ChatSheetId(id: expectedChatId)
        firestore.createOrGetChat(withCoachId: otherUid) { chatId in
            DispatchQueue.main.async {
                let target = chatId ?? expectedChatId
                if target != expectedChatId {
                    presentedChat = ChatSheetId(id: target)
                }
            }
        }
    }
}

// MARK: - Map Pin Model

private struct PlaceMapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
