import SwiftUI

private let presetStrings = [
    "BG65", "BG65T", "BG66F", "BG66UM", "BG80", "BG80P",
    "EX63", "AB", "ABBT", "EX65", "EX68", "SKYARC"
]

struct EditStringerView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss
    let stringer: BadmintonStringer

    @State private var stringerName = ""
    @State private var selectedStrings: Set<String> = []
    @State private var stringCosts: [String: String] = [:]
    @State private var customString = ""
    @State private var customStrings: [String] = []
    @State private var laborCost = ""
    @State private var isSaving = false
    @State private var selectedLocations: [StringerLocation] = []
    @State private var didLoad = false

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
            .navigationTitle("Edit Stringer Profile")
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
                                if err == nil {
                                    firestore.showToast("Profile updated")
                                    dismiss()
                                }
                            }
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                stringerName = stringer.name
                laborCost = stringer.laborCost
                selectedLocations = stringer.meetupLocations

                for (name, cost) in stringer.stringsOffered {
                    if presetStrings.contains(name) {
                        selectedStrings.insert(name)
                    } else {
                        customStrings.append(name)
                    }
                    stringCosts[name] = cost
                }
            }
        }
    }
}
