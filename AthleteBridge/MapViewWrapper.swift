import SwiftUI
import MapKit
import CoreLocation

// Reusable UIKit-backed MKMapView wrapper with tap-to-place and draggable pin support.
struct MapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var markerCoordinate: CLLocationCoordinate2D?
    var showsUserLocation: Bool = false
    var existingLocations: [FirestoreManager.LocationItem] = []

    init(region: Binding<MKCoordinateRegion>, markerCoordinate: Binding<CLLocationCoordinate2D?>, showsUserLocation: Bool = false, existingLocations: [FirestoreManager.LocationItem] = []) {
        _region = region
        _markerCoordinate = markerCoordinate
        self.showsUserLocation = showsUserLocation
        self.existingLocations = existingLocations
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = showsUserLocation
        map.isRotateEnabled = false

        // Set initial region
        map.setRegion(region, animated: false)

        // Tap gesture recognizer to place pin at tap location
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        map.addGestureRecognizer(tap)

        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Sync region if changed externally
        if !coordsEqual(uiView.region.center, region.center) {
            uiView.setRegion(region, animated: true)
        }

        // Sync marker
        if let coord = markerCoordinate {
            if context.coordinator.annotation == nil {
                let ann = MKPointAnnotation()
                ann.coordinate = coord
                uiView.addAnnotation(ann)
                context.coordinator.annotation = ann
            } else {
                // move existing annotation if needed
                if let ann = context.coordinator.annotation {
                    ann.coordinate = coord
                }
            }
        } else {
            // remove annotation if marker cleared
            if let ann = context.coordinator.annotation {
                uiView.removeAnnotation(ann)
                context.coordinator.annotation = nil
            }
        }

        // Sync other location annotations (non-draggable)
        // Remove any previous otherAnnotations, then add new ones
        let current = context.coordinator.otherAnnotations ?? []
        if !current.isEmpty {
            uiView.removeAnnotations(current)
            context.coordinator.otherAnnotations = []
        }
        var newAnns: [MKPointAnnotation] = []
        for loc in existingLocations {
            if let lat = loc.latitude, let lng = loc.longitude {
                let a = MKPointAnnotation()
                a.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                a.title = loc.name
                a.subtitle = loc.address
                newAnns.append(a)
            }
        }
        if !newAnns.isEmpty {
            uiView.addAnnotations(newAnns)
            context.coordinator.otherAnnotations = newAnns
        }
    }

    private func coordsEqual(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        return abs(a.latitude - b.latitude) < 0.000001 && abs(a.longitude - b.longitude) < 0.000001
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        weak var annotation: MKPointAnnotation?
        var otherAnnotations: [MKPointAnnotation]? = []

        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            let coord = map.convert(point, toCoordinateFrom: map)

            // Add or move annotation
            if let ann = annotation {
                ann.coordinate = coord
            } else {
                let ann = MKPointAnnotation()
                ann.coordinate = coord
                map.addAnnotation(ann)
                annotation = ann
            }

            // Update binding and center map
            DispatchQueue.main.async {
                self.parent.markerCoordinate = coord
                self.parent.region.center = coord
                print("[MapView] tap placed pin at: \(coord.latitude), \(coord.longitude)")
            }
        }

        // make draggable annotation views
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let id = "pin"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view?.canShowCallout = false
                view?.isDraggable = true
                view?.animatesWhenAdded = true
            } else {
                view?.annotation = annotation
            }
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // propagate visible region back to SwiftUI
            parent.region = mapView.region
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard let ann = view.annotation else { return }
            switch newState {
            case .ending, .none:
                // update binding when drag ends
                DispatchQueue.main.async {
                    self.parent.markerCoordinate = ann.coordinate
                    print("[MapView] pin drag ended at: \(ann.coordinate.latitude), \(ann.coordinate.longitude)")
                }
                view.setDragState(.none, animated: true)
            default:
                break
            }
        }
    }
}

// Simple BlurView used by AddLocationView
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemMaterial
    func makeUIView(context: Context) -> UIVisualEffectView { UIVisualEffectView(effect: UIBlurEffect(style: style)) }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
