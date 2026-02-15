import SwiftUI

private let presetStrings = [
    "BG65", "BG65T", "BG66F", "BG66UM", "BG80", "BG80P",
    "EX63", "AB", "ABBT", "EX65", "EX68", "SKYARC"
]

struct StringersView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @State private var showAddSheet = false

    private var currentUid: String { auth.user?.uid ?? "" }

    var body: some View {
        List {
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
                ForEach(firestore.stringers) { stringer in
                    NavigationLink {
                        StringerDetailView(stringer: stringer)
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(stringer.name)
                                .font(.headline)

                            if !stringer.meetupLocationNames.isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundColor(.secondary)
                                    Text(stringer.meetupLocationNames.joined(separator: ", "))
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
                    for index in indexSet {
                        let stringer = firestore.stringers[index]
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
        }
    }
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
    @State private var isSaving = false

    // Meetup locations
    @State private var locationInputs: [String] = [""]

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

    private var meetupNames: [String] {
        locationInputs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var isValid: Bool {
        !stringerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !allOfferedStrings.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Stringer Details")) {
                    TextField("Stringer Name", text: $stringerName)
                }

                Section(header: Text("Meetup Locations")) {
                    ForEach(locationInputs.indices, id: \.self) { index in
                        HStack {
                            TextField("Location name", text: $locationInputs[index])
                            if locationInputs.count > 1 {
                                Button(action: { locationInputs.remove(at: index) }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                    Button(action: { locationInputs.append("") }) {
                        Label("Add Location", systemImage: "plus.circle.fill")
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
                        let names = meetupNames
                        firestore.addStringer(
                            name: stringerName.trimmingCharacters(in: .whitespacesAndNewlines),
                            meetupLocationNames: names,
                            stringsOffered: allOfferedStrings
                        ) { err in
                            DispatchQueue.main.async {
                                isSaving = false
                                if err == nil {
                                    for loc in names {
                                        firestore.addSimpleLocation(name: loc)
                                    }
                                    dismiss()
                                }
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

private struct StringRow: View {
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
