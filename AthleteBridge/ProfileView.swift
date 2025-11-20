import SwiftUI

struct ProfileView: View {
    enum Role: String, CaseIterable, Identifiable {
        case client = "Client"
        case coach = "Coach"
        var id: String { rawValue }
    }

    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var firestore: FirestoreService
    @State private var role: Role = .client

    // Common fields
    @State private var name: String = ""

    // Client fields
    @State private var clientGoals: String = ""
    @State private var clientAvailability: String = "Morning"

    // Coach fields
    @State private var specialtiesText: String = ""
    @State private var experienceYears: String = "0"
    @State private var coachAvailabilitySelection: [String] = ["Morning"]
    @State private var hourlyRateText: String = ""

    @State private var isSaving = false
    @State private var saveMessage: String? = nil
    @Environment(\.presentationMode) private var presentationMode

    var availabilityOptions = ["Morning", "Afternoon", "Evening"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Role")) {
                    Picker("Role", selection: $role) {
                        ForEach(Role.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("Full Name")) {
                    TextField("Full Name", text: $name)
                }

                if role == .client {
                    Section(header: Text("Client Details")) {
                        TextField("Goals (comma separated)", text: $clientGoals)
                        Picker("Preferred Availability", selection: $clientAvailability) {
                            ForEach(availabilityOptions, id: \.self) { option in
                                Text(option)
                            }
                        }
                    }
                } else {
                    Section(header: Text("Coach Details")) {
                        TextField("Specialties (comma separated)", text: $specialtiesText)
                        TextField("Experience (years)", text: $experienceYears)
                            .keyboardType(.numberPad)
                        // availability multi-select simple toggles
                        VStack(alignment: .leading) {
                            Text("Availability")
                            ForEach(availabilityOptions, id: \.self) { opt in
                                Toggle(opt, isOn: Binding(get: {
                                    coachAvailabilitySelection.contains(opt)
                                }, set: { newVal in
                                    if newVal {
                                        if !coachAvailabilitySelection.contains(opt) {
                                            coachAvailabilitySelection.append(opt)
                                        }
                                    } else {
                                        coachAvailabilitySelection.removeAll { $0 == opt }
                                    }
                                }))
                            }
                        }
                        TextField("Hourly rate (optional)", text: $hourlyRateText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save Profile") {
                            saveProfile()
                        }
                    }

                    if let msg = saveMessage {
                        Text(msg).foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Create Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Dismiss or logout
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                // If firestore already has a current profile, populate fields
                if let client = firestore.currentClient {
                    role = .client
                    name = client.name
                    clientGoals = client.goals.joined(separator: ", ")
                    clientAvailability = client.preferredAvailability
                } else if let coach = firestore.currentCoach {
                    role = .coach
                    name = coach.name
                    specialtiesText = coach.specialties.joined(separator: ", ")
                    experienceYears = String(coach.experienceYears)
                    coachAvailabilitySelection = coach.availability
                }
            }
        }
    }

    private func populateFromExisting() {
        // If firestore already has a current profile, populate fields
        if let client = firestore.currentClient {
            role = .client
            name = client.name
            clientGoals = client.goals.joined(separator: ", ")
            clientAvailability = client.preferredAvailability
        } else if let coach = firestore.currentCoach {
            role = .coach
            name = coach.name
            specialtiesText = coach.specialties.joined(separator: ", ")
            experienceYears = String(coach.experienceYears)
            coachAvailabilitySelection = coach.availability
        }
    }

    private func saveProfile() {
        guard let uid = auth.user?.uid else {
            saveMessage = "No authenticated user"
            return
        }

        isSaving = true
        saveMessage = nil

        if role == .client {
            let goals = clientGoals.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            firestore.saveClient(id: uid, name: name.isEmpty ? "Unnamed" : name, goals: goals, preferredAvailability: clientAvailability) { err in
                DispatchQueue.main.async {
                    self.isSaving = false
                    if let err = err {
                        self.saveMessage = "Error saving client: \(err.localizedDescription)"
                    } else {
                        // Show a success message briefly before dismissing so the user sees the green label
                        self.saveMessage = "Client profile saved"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
        } else {
            let specialties = specialtiesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let experience = Int(experienceYears) ?? 0
            let hourlyRate = Double(hourlyRateText)
            // split full name into first/last for the schema
            let parts = name.split(separator: " ").map { String($0) }
            let firstName = parts.first ?? (name.isEmpty ? "Unnamed" : name)
            let lastName = parts.dropFirst().joined(separator: " ")
            firestore.saveCoachWithSchema(id: uid,
                                          firstName: firstName,
                                          lastName: lastName,
                                          specialties: specialties,
                                          availability: coachAvailabilitySelection,
                                          experienceYears: experience,
                                          hourlyRate: hourlyRate,
                                          photoURL: nil,
                                          active: true,
                                          overwrite: true) { err in
                DispatchQueue.main.async {
                    self.isSaving = false
                    if let err = err {
                        self.saveMessage = "Error saving coach: \(err.localizedDescription)"
                    } else {
                        // Show the green success label like the client flow, then dismiss after a short delay
                        self.saveMessage = "Coach profile saved"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .environmentObject(AuthViewModel())
            .environmentObject(FirestoreService())
    }
}
