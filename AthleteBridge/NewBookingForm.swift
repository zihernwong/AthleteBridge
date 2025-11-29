import SwiftUI

// New booking form that posts a booking to Firestore
struct NewBookingFormView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Binding var showSheet: Bool

    @State private var selectedCoachId: String = ""
    @State private var coachSearchText: String = ""
    @State private var startAt: Date = Date()
    @State private var endAt: Date = Date().addingTimeInterval(60*30)
    // selectedLocationId references a document id in clients/{uid}/locations (firestore.locations)
    @State private var selectedLocationId: String = ""
    @State private var notes: String = "notes"

    @State private var isSaving = false
    @State private var alertMessage: String = ""
    @State private var showAlert = false

    // Inline suggestions for coach names (prefix match)
    private var coachSuggestions: [Coach] {
        let typed = coachSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard typed.count >= 1 else { return [] }
        return firestore.coaches.filter { $0.name.lowercased().hasPrefix(typed) }
    }

    // Custom initializer to allow pre-filling coach/start/end when created from a calendar slot
    init(showSheet: Binding<Bool>, initialCoachId: String? = nil, initialStart: Date? = nil, initialEnd: Date? = nil) {
        self._showSheet = showSheet
        self._selectedCoachId = State(initialValue: initialCoachId ?? "")
        self._startAt = State(initialValue: initialStart ?? Date())
        self._endAt = State(initialValue: initialEnd ?? (initialStart ?? Date()).addingTimeInterval(60*30))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Client (defaults to signed-in user)")) {
                    if let client = firestore.currentClient {
                        Text("Signed in as: \(client.name)")
                    } else if let uid = auth.user?.uid {
                        // fallback: show uid while we fetch profile
                        Text("Signed in as: \(uid)")
                    } else {
                        Text("Not signed in").foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Coach")) {
                    if firestore.coaches.isEmpty {
                        Text("No coaches available").foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Search coach by name", text: $coachSearchText)
                                .textFieldStyle(.roundedBorder)

                            if !coachSuggestions.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(coachSuggestions.prefix(8), id: \.id) { coach in
                                            Button(action: {
                                                coachSearchText = coach.name
                                                selectedCoachId = coach.id
                                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                            }) {
                                                Text(coach.name)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(Color(UIColor.secondarySystemBackground))
                                                    .cornerRadius(16)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }

                            if let selected = firestore.coaches.first(where: { $0.id == selectedCoachId }) {
                                Text("Selected: \(selected.name)")
                                    .font(.subheadline)
                            } else if !selectedCoachId.isEmpty {
                                Text("Selected coach id: \(selectedCoachId)")
                                    .font(.subheadline)
                            }
                        }
                        .onAppear {
                            firestore.fetchCoaches()
                            if selectedCoachId.isEmpty, let first = firestore.coaches.first {
                                selectedCoachId = first.id
                                coachSearchText = first.name
                            }
                        }
                    }
                }

                Section(header: Text("When")) {
                    DatePicker("Start", selection: $startAt, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $endAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section(header: Text("Details")) {
                    // Only allow selecting from the current user's saved locations
                    if firestore.locations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No saved locations found").foregroundColor(.secondary)
                            Text("Save a location in the Locations tab before creating a booking.").font(.caption).foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Location", selection: $selectedLocationId) {
                            ForEach(firestore.locations, id: \.id) { loc in
                                Text(loc.name ?? "Unnamed").tag(loc.id)
                            }
                        }
                        .onAppear {
                            if selectedLocationId.isEmpty, let first = firestore.locations.first {
                                selectedLocationId = first.id
                            }
                        }
                    }
                    TextEditor(text: $notes).frame(minHeight: 80)
                }

                if isSaving { ProgressView().frame(maxWidth: .infinity, alignment: .center) }
            }
            .navigationTitle("New Booking")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveBooking() }
                        .disabled(selectedCoachId.isEmpty || auth.user == nil || selectedLocationId.isEmpty)
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .onAppear {
                // ensure coaches and current client profile are available when the form appears
                firestore.fetchCoaches()
                if selectedCoachId.isEmpty, let first = firestore.coaches.first {
                    selectedCoachId = first.id
                }
                if let uid = auth.user?.uid {
                    firestore.fetchCurrentProfiles(for: uid)
                    // also load bookings stored under clients/{uid}/bookings
                    firestore.fetchBookingsFromClientSubcollection(clientId: uid)
                    // ensure current user's saved locations are loaded for the location picker
                    firestore.fetchLocationsForCurrentUser()
                }
            }
        }
    }

    private func saveBooking() {
        guard let clientUid = auth.user?.uid, !clientUid.isEmpty else {
            alertMessage = "You must be signed in to create a booking"
            showAlert = true
            return
        }
        let coachUid = selectedCoachId
        guard !coachUid.isEmpty else {
            alertMessage = "Select a coach"
            showAlert = true
            return
        }

        isSaving = true
        // Determine location name from the selected saved location id
        let locationName = firestore.locations.first(where: { $0.id == selectedLocationId })?.name ?? ""
        // Always create bookings with default status "requested"
        firestore.saveBooking(clientUid: clientUid, coachUid: coachUid, startAt: startAt, endAt: endAt, location: locationName, notes: notes, status: "requested") { err in
            DispatchQueue.main.async {
                self.isSaving = false
                if let err = err {
                    self.alertMessage = "Failed to save booking: \(err.localizedDescription)"
                    self.showAlert = true
                } else {
                    // Refresh the client subcollection which is the canonical source
                    firestore.fetchBookingsForCurrentClientSubcollection()
                    firestore.showToast("Booking saved")
                    showSheet = false
                }
            }
        }
    }
}

struct NewBookingFormView_Previews: PreviewProvider {
    static var previews: some View {
        NewBookingFormView(showSheet: .constant(true), initialCoachId: "", initialStart: Date(), initialEnd: Date().addingTimeInterval(1800))
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
