import SwiftUI
import MapKit
import FirebaseAuth

struct LocationsView: View {
    @EnvironmentObject var firestore: FirestoreManager

    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 44.9778, longitude: -93.2650), span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2))
    @State private var markerCoordinate: CLLocationCoordinate2D? = nil
    @State private var newName: String = ""
    @State private var newAddress: String = ""
    @State private var isSavingInline = false
    @State private var showSaveAlert = false
    @State private var saveAlertMessage = ""
    @State private var bookings: [FirestoreManager.BookingItem] = []
    @State private var loading: Bool = true
    @State private var selectedDate: Date = Date()
    // Local list of locations associated with the currently authenticated user
    @State private var userLocations: [FirestoreManager.LocationItem] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Interactive map for placing a pin via long-press or by using the centered crosshair
                ZStack {
                    ABMapView(region: $region, markerCoordinate: $markerCoordinate, showsUserLocation: true, existingLocations: userLocations)
                        .frame(height: 360)
                        .cornerRadius(8)

                    // Center crosshair to allow precise placement by panning the map
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color.primary.opacity(0.9))
                        .shadow(radius: 2)
                        .allowsHitTesting(false)
                }
                .padding()

                // Show coordinate readout so users can see the placed pin's lat/lng
                if let coord = markerCoordinate {
                    HStack {
                        Image(systemName: "mappin")
                        Text(String(format: "Pin: %.5f, %.5f", coord.latitude, coord.longitude))
                            .font(.caption)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                // User can either long-press to drop a pin and drag, or pan the map and use the center button below.
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        TextField("Name for pin", text: $newName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Address (optional)", text: $newAddress)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(spacing: 8) {
                        // Button to set the marker to the current map center (more discoverable than drag)
                        Button(action: {
                            // use the current region center as the temporary pin
                            markerCoordinate = region.center
                        }) {
                            HStack {
                                Image(systemName: "location.fill")
                                Text("Set Pin to Map Center")
                            }
                            .padding(8)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                        }

                        // Tiny help text
                        Text("Or long-press the map to drop a pin, then drag it.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 140)
                    }

                    Button(action: saveInlineLocation) {
                        if isSavingInline { ProgressView() } else { Image(systemName: "plus.circle.fill").font(.title3) }
                    }
                    .disabled(markerCoordinate == nil || isSavingInline)
                }
                .padding([.horizontal, .bottom])

                List {
                    Section(header: Text("Saved Locations")) {
                        if userLocations.isEmpty {
                            Text("No locations").foregroundColor(.secondary)
                        } else {
                            ForEach(userLocations) { loc in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(loc.name ?? "Unnamed location").font(.headline)
                                    if let address = loc.address { Text(address).font(.subheadline) }
                                    if let lat = loc.latitude, let lng = loc.longitude {
                                        Text(String(format: "Lat: %.4f, Lng: %.4f", lat, lng)).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }

                    if !firestore.locationsDebug.isEmpty {
                        Section(header: Text("Debug")) {
                            Text(firestore.locationsDebug).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Locations")
            .toolbar {
                /* refresh button removed */
            }
            .onAppear {
                // Load locations that belong to the current user (clients/{uid}/locations)
                if let uid = Auth.auth().currentUser?.uid {
                    firestore.fetchLocationsForClient(clientId: uid) { items in
                        DispatchQueue.main.async {
                            self.userLocations = items
                            if let first = items.first, let lat = first.latitude, let lng = first.longitude {
                                region.center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                                region.span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                            }
                        }
                    }
                }
            }
            .onChange(of: firestore.locations) { newLocations in
                // Keep userLocations in sync if the global cache is updated elsewhere
                // but prefer explicitly fetching client-only locations after saves.
                // If you want to strictly use this global cache, uncomment the next line.
                // self.userLocations = newLocations
            }
            .alert(isPresented: $showSaveAlert) { Alert(title: Text("Save Error"), message: Text(saveAlertMessage), dismissButton: .default(Text("OK"))) }
        }
    }

    private func saveInlineLocation() {
        guard let coord = markerCoordinate else { return }
        isSavingInline = true
        let title = newName.isEmpty ? "Untitled Location" : newName
        firestore.addLocationForCurrentUser(name: title, address: newAddress.isEmpty ? nil : newAddress, latitude: coord.latitude, longitude: coord.longitude) { err in
            DispatchQueue.main.async {
                isSavingInline = false
                if let err = err {
                    saveAlertMessage = err.localizedDescription
                    showSaveAlert = true
                } else {
                    // clear form and refresh user-specific locations
                    newName = ""
                    newAddress = ""
                    markerCoordinate = nil
                    if let uid = Auth.auth().currentUser?.uid {
                        firestore.fetchLocationsForClient(clientId: uid) { items in
                            DispatchQueue.main.async {
                                self.userLocations = items
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Map UIViewRepresentable (renamed to avoid collisions)
struct ABMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var markerCoordinate: CLLocationCoordinate2D?

    var showsUserLocation: Bool = false
    var existingLocations: [FirestoreManager.LocationItem] = []

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = showsUserLocation
        map.setRegion(region, animated: false)
        map.isRotateEnabled = false
        map.isPitchEnabled = false

        // long press gesture to drop a pin
        let lp = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        lp.minimumPressDuration = 0.4
        map.addGestureRecognizer(lp)

        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // update region if binding changed externally
        if abs(uiView.region.center.latitude - region.center.latitude) > 0.0001 || abs(uiView.region.center.longitude - region.center.longitude) > 0.0001 {
            uiView.setRegion(region, animated: true)
        }

        // Remove stale annotations (keep user location and temporary pin), then re-add current existingLocations
        uiView.annotations.forEach { ann in
            if ann is MKUserLocation { return }
            if let subtitle = (ann as? MKPointAnnotation)?.subtitle, subtitle == "__TEMP_PIN__" { return }
            uiView.removeAnnotation(ann)
        }

        // add annotations for current existingLocations (use subtitle to store the location id)
        for loc in existingLocations {
            guard let lat = loc.latitude, let lng = loc.longitude else { continue }
            let title = loc.name ?? "Location"
            let ann = MKPointAnnotation()
            ann.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            ann.title = title
            ann.subtitle = loc.id
            uiView.addAnnotation(ann)
        }

        // update marker annotation
        if let coord = markerCoordinate {
            // remove previous temp annotations named "__TEMP_PIN__"
            uiView.annotations.filter { ($0 as? MKPointAnnotation)?.subtitle == "__TEMP_PIN__" }.forEach { uiView.removeAnnotation($0) }
            let temp = MKPointAnnotation()
            temp.coordinate = coord
            temp.title = "Pin"
            temp.subtitle = "__TEMP_PIN__"
            uiView.addAnnotation(temp)
            uiView.selectAnnotation(temp, animated: true)
        } else {
            // remove any temp pins
            uiView.annotations.filter { ($0 as? MKPointAnnotation)?.subtitle == "__TEMP_PIN__" }.forEach { uiView.removeAnnotation($0) }
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ABMapView
        init(_ parent: ABMapView) { self.parent = parent }

        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            if gesture.state == .began {
                let point = gesture.location(in: map)
                let coord = map.convert(point, toCoordinateFrom: map)
                DispatchQueue.main.async {
                    self.parent.markerCoordinate = coord
                    self.parent.region.center = coord
                }
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // avoid customizing user location
            if annotation is MKUserLocation { return nil }

            let id = "pin"
            var v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
            if v == nil {
                v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                v?.canShowCallout = true
            } else {
                v?.annotation = annotation
            }
            // use markerTintColor instead of deprecated pinTintColor
            let isTemp = (annotation.subtitle == "__TEMP_PIN__")
            v?.markerTintColor = isTemp ? .systemBlue : .systemRed
            // allow dragging only for the temporary pin (the one the user is placing)
            v?.isDraggable = isTemp
             return v
         }

        // Track dragging state for temp pin to update the bound markerCoordinate
        func mapView(_ mapView: MKMapView, annotationView: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            // Only care about the temp pin
            guard let ann = annotationView.annotation, (ann.subtitle ?? "") == "__TEMP_PIN__" else { return }
            switch newState {
            case .ending, .canceling:
                // update bound coordinate to match annotation position
                let coord = ann.coordinate
                DispatchQueue.main.async {
                    self.parent.markerCoordinate = coord
                    self.parent.region.center = coord
                }
                // clear drag state
                annotationView.setDragState(.none, animated: true)
            default:
                break
            }
        }
    }
}

struct LocationsView_Previews: PreviewProvider {
    static var previews: some View {
        LocationsView().environmentObject(FirestoreManager())
    }
}
