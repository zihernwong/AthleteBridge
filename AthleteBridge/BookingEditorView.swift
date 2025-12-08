import SwiftUI

// Unified booking editor used by BookingsView and other places.
struct BookingEditorView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Binding var showSheet: Bool

    @State private var selectedCoachId: String = ""
    @State private var coachSearchText: String = ""
    @State private var startAt: Date = Date()
    @State private var endAt: Date = Date().addingTimeInterval(60*30)
    // selectedLocationId references a document id in clients/{uid}/locations (firestore.locations)
    @State private var selectedLocationId: String = ""
    @State private var notes: String = ""

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
    init(showSheet: Binding<Bool>, initialCoachId: String? = nil, initialStart: Date? = nil, initialEnd: Date? = nil, initialLocationId: String? = nil, initialNotes: String? = nil) {
        self._showSheet = showSheet
        self._selectedCoachId = State(initialValue: initialCoachId ?? "")
        self._startAt = State(initialValue: initialStart ?? Date())
        self._endAt = State(initialValue: initialEnd ?? (initialStart ?? Date()).addingTimeInterval(60*30))
        self._selectedLocationId = State(initialValue: initialLocationId ?? "")
        self._notes = State(initialValue: initialNotes ?? "")
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
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Start")
                        MinuteIntervalDatePicker(date: $startAt, minuteInterval: 30)
                            .frame(height: 150)
                            .padding(.bottom, 12)
                            .onChange(of: startAt) { _, newStart in
                                // Snap start to nearest 30-minute increment (guard against minute-by-minute behavior)
                                let intervalSeconds = 30 * 60
                                let t = newStart.timeIntervalSinceReferenceDate
                                let snapped = TimeInterval(Int((t + Double(intervalSeconds)/2.0) / Double(intervalSeconds))) * Double(intervalSeconds)
                                let snappedDate = Date(timeIntervalSinceReferenceDate: snapped)
                                if abs(snappedDate.timeIntervalSince(newStart)) > 0.1 {
                                    startAt = snappedDate
                                }
                                // If start is at/after end, bump end to start + 30min
                                if startAt >= endAt {
                                    endAt = Calendar.current.date(byAdding: .minute, value: 30, to: startAt) ?? startAt.addingTimeInterval(60*30)
                                }
                            }

                        Text("End")
                        MinuteIntervalDatePicker(date: $endAt, minuteInterval: 30)
                            .frame(height: 150)
                            .onChange(of: endAt) { _, newEnd in
                                // Snap end to nearest 30-minute increment
                                let intervalSeconds = 30 * 60
                                let t = newEnd.timeIntervalSinceReferenceDate
                                let snapped = TimeInterval(Int((t + Double(intervalSeconds)/2.0) / Double(intervalSeconds))) * Double(intervalSeconds)
                                let snappedDate = Date(timeIntervalSinceReferenceDate: snapped)
                                if abs(snappedDate.timeIntervalSince(newEnd)) > 0.1 {
                                    endAt = snappedDate
                                }
                                // If end is at/earlier than start, move start to end - 30min
                                if endAt <= startAt {
                                    startAt = Calendar.current.date(byAdding: .minute, value: -30, to: endAt) ?? endAt.addingTimeInterval(-60*30)
                                }
                            }
                    }
                }

                Section(header: Text("Details")) {
                    // Location is optional. If the user has saved locations they can pick one,
                    // otherwise they can proceed without selecting a location (e.g., virtual session).
                    if firestore.locations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No saved locations found").foregroundColor(.secondary)
                            Text("Location is optional; leave blank for a virtual session.").font(.caption).foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Location (optional)", selection: $selectedLocationId) {
                            // allow an explicit 'none' option
                            Text("None").tag("")
                            ForEach(firestore.locations, id: \.id) { loc in
                                Text(loc.name ?? "Unnamed").tag(loc.id)
                            }
                        }
                        .onAppear {
                            // Do not auto-select a saved location — keep location optional.
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
                        // Disable save if coach not selected, not signed in, or times invalid (start must be before end)
                        .disabled(selectedCoachId.isEmpty || auth.user == nil || !(startAt < endAt))
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
                // Do not auto-select a saved location; location remains optional.
                if let uid = auth.user?.uid {
                    firestore.fetchCurrentProfiles(for: uid)
                    // also load bookings stored under clients/{uid}/bookings
                    firestore.fetchBookingsFromClientSubcollection(clientId: uid)
                    // ensure current user's saved locations are loaded for the location picker
                    firestore.fetchLocationsForCurrentUser()
                }

                // Snap initial start/end to nearest 30-minute increment so wheels align on load
                let snap: (Date) -> Date = { date in
                    let interval = 30 * 60
                    let t = date.timeIntervalSinceReferenceDate
                    let snapped = TimeInterval(Int((t + Double(interval)/2.0) / Double(interval))) * Double(interval)
                    return Date(timeIntervalSinceReferenceDate: snapped)
                }
                startAt = snap(startAt)
                endAt = snap(endAt)
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

        // Snap times to nearest 30-minute boundary before validation/save
        func snapTo30(_ date: Date) -> Date {
            let interval = 30 * 60
            let t = date.timeIntervalSinceReferenceDate
            let snapped = TimeInterval(Int((t + Double(interval)/2.0) / Double(interval))) * Double(interval)
            return Date(timeIntervalSinceReferenceDate: snapped)
        }
        startAt = snapTo30(startAt)
        endAt = snapTo30(endAt)

        // Validate times before saving
        if !(startAt < endAt) {
            alertMessage = "Start time must be before end time"
            showAlert = true
            return
        }

        isSaving = true
        // UI-level timeout: ensure spinner cleared if backend callback never invoked
        var uiTimeoutItem: DispatchWorkItem? = nil
        uiTimeoutItem = DispatchWorkItem {
            if self.isSaving {
                self.isSaving = false
                self.alertMessage = "Save timed out. Please check your network and try again."
                self.showAlert = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0, execute: uiTimeoutItem!)
        // Determine location name from the selected saved location id; allow nil for no selection
        let locationName: String? = firestore.locations.first(where: { $0.id == selectedLocationId })?.name
        // Always create bookings with default status "requested"
        firestore.saveBooking(clientUid: clientUid, coachUid: coachUid, startAt: startAt, endAt: endAt, location: locationName, notes: notes, status: "requested") { err in
            DispatchQueue.main.async {
                // cancel UI timeout
                uiTimeoutItem?.cancel()
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

struct BookingEditorView_Previews: PreviewProvider {
    static var previews: some View {
        BookingEditorView(showSheet: .constant(true), initialCoachId: "", initialStart: Date(), initialEnd: Date().addingTimeInterval(1800))
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
