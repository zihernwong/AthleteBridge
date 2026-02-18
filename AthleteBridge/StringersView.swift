import SwiftUI
import MapKit

private let presetStrings = [
    "BG65", "BG65T", "BG66F", "BG66UM", "BG80", "BG80P",
    "EX63", "AB", "ABBT", "EX65", "EX68", "SKYARC"
]

struct StringersView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @StateObject private var locationManager = LocationManager.shared
    @State private var showAddSheet = false
    @State private var mapPosition: MapCameraPosition = .automatic

    private var currentUid: String { auth.user?.uid ?? "" }

    /// Stringers that have at least one location with coordinates.
    private var stringersWithLocations: [BadmintonStringer] {
        firestore.stringers.filter { !$0.meetupLocations.isEmpty }
    }

    /// All stringer annotations for the map (one per meetup location).
    private var mapAnnotations: [StringerMapPin] {
        stringersWithLocations.flatMap { stringer in
            stringer.meetupLocations.map { loc in
                StringerMapPin(
                    id: "\(stringer.id)_\(loc.id)",
                    stringerId: stringer.id,
                    name: stringer.name,
                    locationName: loc.name,
                    coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
                )
            }
        }
    }

    /// Stringers sorted by closest meetup location to user, if location is available.
    private var sortedStringers: [BadmintonStringer] {
        guard let userLoc = locationManager.currentLocation else {
            return firestore.stringers
        }
        let userCL = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
        return firestore.stringers.sorted { a, b in
            let distA = a.meetupLocations.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: userCL) }.min() ?? Double.greatestFiniteMagnitude
            let distB = b.meetupLocations.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: userCL) }.min() ?? Double.greatestFiniteMagnitude
            return distA < distB
        }
    }

    private var mapSectionHeader: some View {
        Text("Find Nearest Stringers")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .textCase(nil)
    }

    private var mapSectionFooter: some View {
        Text("Based on your real-time location or profile zip code")
            .font(.caption2)
    }

    private var mapContent: some View {
        Map(position: $mapPosition) {
            ForEach(mapAnnotations) { pin in
                Marker(pin.name, coordinate: pin.coordinate)
                    .tint(Color("LogoGreen"))
            }
            UserAnnotation()
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }

    var body: some View {
        List {
            // Map section
            if !mapAnnotations.isEmpty {
                Section(header: mapSectionHeader, footer: mapSectionFooter) {
                    mapContent
                }
            }

            Section {
                NavigationLink {
                    MyStringerOrdersView()
                        .environmentObject(firestore)
                } label: {
                    HStack {
                        Image(systemName: "shippingbox")
                            .foregroundColor(Color("LogoBlue"))
                        Text("My Stringing Orders")
                        Spacer()
                    }
                }
            }

            if firestore.stringers.isEmpty {
                Text("No stringers registered yet. Be the first!")
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedStringers) { stringer in
                    NavigationLink {
                        StringerDetailView(stringer: stringer)
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(stringer.name)
                                .font(.headline)

                            if !stringer.meetupLocations.isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundColor(.secondary)
                                    Text(stringer.meetupLocations.map { $0.name }.joined(separator: ", "))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            } else if !stringer.meetupLocationNames.isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundColor(.secondary)
                                    Text(stringer.meetupLocationNames.joined(separator: ", "))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if let distText = distanceText(for: stringer) {
                                HStack(spacing: 4) {
                                    Image(systemName: "location")
                                        .foregroundColor(.secondary)
                                    Text(distText)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if !stringer.laborCost.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "wrench.and.screwdriver")
                                        .foregroundColor(.secondary)
                                    Text("Labor: \(stringer.laborCost)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if !stringer.stringsOffered.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "figure.badminton")
                                            .foregroundColor(.secondary)
                                        Text("Strings Offered")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    StringsWithCostDisplay(strings: stringer.stringsOffered)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { indexSet in
                    let sorted = sortedStringers
                    for index in indexSet {
                        let stringer = sorted[index]
                        if stringer.id == currentUid {
                            firestore.deleteStringer(id: stringer.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Badminton Stringers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddStringerView()
                .environmentObject(firestore)
        }
        .onAppear {
            firestore.fetchStringers()
            locationManager.requestPermission()
            locationManager.requestLocation()
        }
    }

    private func distanceText(for stringer: BadmintonStringer) -> String? {
        guard let userLoc = locationManager.currentLocation,
              !stringer.meetupLocations.isEmpty else { return nil }
        let userCL = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
        guard let closest = stringer.meetupLocations
            .map({ CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: userCL) })
            .min() else { return nil }
        let miles = closest / 1609.34
        if miles < 1 {
            return String(format: "%.1f mi away", miles)
        } else {
            return String(format: "%.0f mi away", miles)
        }
    }
}

// MARK: - Map Pin Model

struct StringerMapPin: Identifiable {
    let id: String
    let stringerId: String
    let name: String
    let locationName: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Display strings with costs

private struct StringsWithCostDisplay: View {
    let strings: [String: String]

    private var sortedKeys: [String] {
        let order = presetStrings
        return strings.keys.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? Int.max
            let ib = order.firstIndex(of: b) ?? Int.max
            return ia < ib
        }
    }

    var body: some View {
        ForEach(sortedKeys, id: \.self) { name in
            HStack {
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                if let cost = strings[name], !cost.isEmpty {
                    Text(cost)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Add Stringer Form

struct AddStringerView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss

    @State private var stringerName = ""
    @State private var hasSetDefaultName = false
    @State private var selectedStrings: Set<String> = []
    @State private var stringCosts: [String: String] = [:]
    @State private var customString = ""
    @State private var customStrings: [String] = []
    @State private var laborCost = ""
    @State private var isSaving = false

    // Meetup locations (rich)
    @State private var selectedLocations: [StringerLocation] = []

    private var allOfferedStrings: [String: String] {
        var result: [String: String] = [:]
        for s in presetStrings where selectedStrings.contains(s) {
            result[s] = stringCosts[s] ?? ""
        }
        for s in customStrings {
            result[s] = stringCosts[s] ?? ""
        }
        return result
    }

    private var isValid: Bool {
        !stringerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !laborCost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !allOfferedStrings.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Stringer Details")) {
                    TextField("Stringer Name", text: $stringerName)
                    TextField("Labor Cost Per Racket (e.g. $10)", text: $laborCost)
                }

                Section(header: Text("Meetup Locations")) {
                    ForEach(selectedLocations) { loc in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.name)
                                    .font(.subheadline)
                                Text(loc.address)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                selectedLocations.removeAll { $0.id == loc.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    AddressSearchBar { location in
                        selectedLocations.append(location)
                    }
                }

                Section(header: Text("Strings Offered")) {
                    ForEach(presetStrings, id: \.self) { s in
                        StringRow(
                            name: s,
                            isSelected: selectedStrings.contains(s),
                            cost: Binding(
                                get: { stringCosts[s] ?? "" },
                                set: { stringCosts[s] = $0 }
                            ),
                            onToggle: {
                                if selectedStrings.contains(s) {
                                    selectedStrings.remove(s)
                                    stringCosts.removeValue(forKey: s)
                                } else {
                                    selectedStrings.insert(s)
                                }
                            }
                        )
                    }

                    // Custom strings
                    ForEach(customStrings, id: \.self) { s in
                        HStack {
                            StringRow(
                                name: s,
                                isSelected: true,
                                cost: Binding(
                                    get: { stringCosts[s] ?? "" },
                                    set: { stringCosts[s] = $0 }
                                ),
                                onToggle: {}
                            )
                            Button(action: {
                                customStrings.removeAll { $0 == s }
                                stringCosts.removeValue(forKey: s)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }

                    // Add custom string
                    HStack {
                        TextField("Add custom string", text: $customString)
                        Button(action: {
                            let trimmed = customString.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            if !customStrings.contains(trimmed) && !presetStrings.contains(trimmed) {
                                customStrings.append(trimmed)
                            }
                            customString = ""
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Color("LogoGreen"))
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(customString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Register Stringer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        let names = selectedLocations.map { $0.name }
                        firestore.addStringer(
                            name: stringerName.trimmingCharacters(in: .whitespacesAndNewlines),
                            meetupLocationNames: names,
                            stringsOffered: allOfferedStrings,
                            laborCost: laborCost.trimmingCharacters(in: .whitespacesAndNewlines),
                            meetupLocations: selectedLocations
                        ) { err in
                            DispatchQueue.main.async {
                                isSaving = false
                                if err == nil { dismiss() }
                            }
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .onAppear {
                if !hasSetDefaultName {
                    if let name = firestore.currentClient?.name, !name.isEmpty {
                        stringerName = name
                    } else if let coach = firestore.currentCoach {
                        stringerName = coach.name
                    }
                    hasSetDefaultName = true
                }
            }
        }
    }
}

// MARK: - String row with checkbox and cost

struct StringRow: View {
    let name: String
    let isSelected: Bool
    @Binding var cost: String
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? Color("LogoGreen") : .secondary)
                    Text(name)
                        .font(.body)
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())

            if isSelected {
                TextField("Additional cost (e.g. $5)", text: $cost)
                    .font(.caption)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading, 28)
            }
        }
    }
}
