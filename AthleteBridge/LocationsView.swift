import SwiftUI

struct LocationsView: View {
    @EnvironmentObject var firestore: FirestoreManager

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Locations")) {
                    if firestore.locations.isEmpty {
                        Text("No locations").foregroundColor(.secondary)
                    } else {
                        ForEach(firestore.locations) { loc in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(loc.name ?? "Unnamed location").font(.headline)
                                if let address = loc.address { Text(address).font(.subheadline) }
                                if let notes = loc.notes { Text(notes).font(.caption).foregroundColor(.secondary) }
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
            .navigationTitle("Locations")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { firestore.fetchLocations() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .onAppear { firestore.fetchLocations() }
        }
    }
}

struct LocationsView_Previews: PreviewProvider {
    static var previews: some View {
        LocationsView().environmentObject(FirestoreManager())
    }
}
