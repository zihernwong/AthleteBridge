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

    @State private var selectedSlotStart: Date? = nil
    @State private var selectedSlotEnd: Date? = nil
    @State private var calendarDate: Date = Date()

    @State private var showConfirmOverlay: Bool = false

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
                Section {
                    if let client = firestore.currentClient {
                        Text("Signed in as: \(client.name)")
                    } else if let uid = auth.user?.uid {
                        // fallback: show uid while we fetch profile
                        Text("Signed in as: \(uid)")
                    } else {
                        Text("Not signed in").foregroundColor(.secondary)
                    }
                } header: {
                    Text("Client (defaults to signed-in user)")
                }

                Section {
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
                        }
                    }
                } header: {
                    Text("Coach")
                }

                // Only after a coach is selected, show Coach Info and Calendar
                if !selectedCoachId.isEmpty, let coach = firestore.coaches.first(where: { $0.id == selectedCoachId }) {
                    // Coach Info section (above the calendar)
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            let coachURL = firestore.coachPhotoURLs[coach.id] ?? nil
                            AvatarView(url: coachURL ?? nil, size: 72, useCurrentUser: false)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(coach.name).font(.headline)
                                if let bio = coach.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(bio).font(.body).foregroundColor(.primary)
                                } else {
                                    Text("No bio provided").font(.subheadline).foregroundColor(.secondary)
                                }
                                if !coach.specialties.isEmpty {
                                    Text("Specialties: \(coach.specialties.joined(separator: ", "))")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Text("Experience: \(coach.experienceYears) years").font(.caption).foregroundColor(.secondary)
                                if let rate = coach.hourlyRate {
                                    Text(String(format: "Hourly Rate: $%.0f / hr", rate)).font(.caption).foregroundColor(.primary)
                                } else {
                                    Text("Hourly rate to be discussed").font(.caption).foregroundColor(.secondary)
                                }
                                if !coach.availability.isEmpty {
                                    Text("Availability: \(coach.availability.joined(separator: ", "))")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Coach Info")
                    }

                    // Show coach calendar grid once a coach is selected; hide time pickers
                    Section {
                        // Calendar day controls
                        HStack {
                            Button(action: { calendarDate = Calendar.current.date(byAdding: .day, value: -1, to: calendarDate) ?? calendarDate }) { Image(systemName: "chevron.left") }
                                .buttonStyle(.plain)
                            Spacer()
                            Text(DateFormatter.localizedString(from: calendarDate, dateStyle: .medium, timeStyle: .none))
                                .font(.subheadline).bold()
                            Spacer()
                            Button(action: { calendarDate = Calendar.current.date(byAdding: .day, value: 1, to: calendarDate) ?? calendarDate }) { Image(systemName: "chevron.right") }
                                .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)

                        CoachCalendarGridView(coachID: selectedCoachId,
                                              date: $calendarDate,
                                              showOnlyAvailable: false,
                                              onSlotSelected: nil,
                                              embedMode: true,
                                              onAvailableSlot: { start, end in
                                                  selectedSlotStart = start
                                                  selectedSlotEnd = end
                                                  startAt = start
                                                  endAt = end
                                                  showConfirmOverlay = true
                                              })
                            .environmentObject(firestore)
                            .environmentObject(auth)
                            .id(calendarDate)

                        if let s = selectedSlotStart, let e = selectedSlotEnd {
                            Text("Selected: \(DateFormatter.localizedString(from: s, dateStyle: .none, timeStyle: .short)) - \(DateFormatter.localizedString(from: e, dateStyle: .none, timeStyle: .short))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Tap an Available slot to select")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Coach Calendar")
                    }

                    // Details section remains
                    Section {
                        if firestore.locations.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No saved locations found").foregroundColor(.secondary)
                                Text("Location is optional; leave blank for a virtual session.").font(.caption).foregroundColor(.secondary)
                            }
                        } else {
                            Picker("Location (optional)", selection: $selectedLocationId) {
                                Text("None").tag("")
                                ForEach(firestore.locations, id: \.id) { loc in
                                    Text(loc.name ?? "Unnamed").tag(loc.id)
                                }
                            }
                        }
                        TextEditor(text: $notes).frame(minHeight: 80)
                    } header: {
                        Text("Details")
                    }
                }

                // Remove the When section when using calendar; only show if no coach selected (fallback)
                if selectedCoachId.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Start")
                            MinuteIntervalDatePicker(date: $startAt, minuteInterval: 30)
                                .frame(height: 150)
                                .padding(.bottom, 12)
                            Text("End")
                            MinuteIntervalDatePicker(date: $endAt, minuteInterval: 30)
                                .frame(height: 150)
                        }
                    } header: {
                        Text("When")
                    }
                }

                if isSaving { ProgressView().frame(maxWidth: .infinity, alignment: .center) }
            }
            .navigationTitle("New Booking")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let s = selectedSlotStart, let e = selectedSlotEnd { startAt = s; endAt = e }
                        saveBooking()
                    }
                    .disabled(selectedCoachId.isEmpty || auth.user == nil || (selectedCoachId.isEmpty && !(startAt < endAt)))
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .onAppear {
                // ensure coaches and current client profile are available when the form appears
                firestore.fetchCoaches()
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

                calendarDate = Calendar.current.startOfDay(for: Date())
            }
        }
        // Replace sheet with a custom overlay so dismissal is simultaneous
        .overlay(
            Group {
                if showConfirmOverlay {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture { withAnimation(.easeInOut) { showConfirmOverlay = false } }

                        // Modal card
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Confirm Date & Time").font(.headline)
                                if let coach = firestore.coaches.first(where: { $0.id == selectedCoachId }) {
                                    Text("Coach: \(coach.name)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()

                            Divider()

                            VStack(alignment: .leading, spacing: 16) {
                                Text("Start")
                                MinuteIntervalDatePicker(date: $startAt, minuteInterval: 30)
                                    .frame(height: 150)
                                    .padding(.bottom, 8)
                                    .onChange(of: startAt) { _, newStart in
                                        let intervalSeconds = 30 * 60
                                        let t = newStart.timeIntervalSinceReferenceDate
                                        let snapped = TimeInterval(Int((t + Double(intervalSeconds)/2.0) / Double(intervalSeconds))) * Double(intervalSeconds)
                                        let snappedDate = Date(timeIntervalSinceReferenceDate: snapped)
                                        if abs(snappedDate.timeIntervalSince(newStart)) > 0.1 { startAt = snappedDate }
                                        if startAt >= endAt { endAt = Calendar.current.date(byAdding: .minute, value: 30, to: startAt) ?? startAt.addingTimeInterval(60*30) }
                                    }

                                Text("End")
                                MinuteIntervalDatePicker(date: $endAt, minuteInterval: 30)
                                    .frame(height: 150)
                                    .onChange(of: endAt) { _, newEnd in
                                        let intervalSeconds = 30 * 60
                                        let t = newEnd.timeIntervalSinceReferenceDate
                                        let snapped = TimeInterval(Int((t + Double(intervalSeconds)/2.0) / Double(intervalSeconds))) * Double(intervalSeconds)
                                        let snappedDate = Date(timeIntervalSinceReferenceDate: snapped)
                                        if abs(snappedDate.timeIntervalSince(newEnd)) > 0.1 { endAt = snappedDate }
                                        if endAt <= startAt { startAt = Calendar.current.date(byAdding: .minute, value: -30, to: endAt) ?? endAt.addingTimeInterval(-60*30) }
                                    }
                            }
                            .padding([.horizontal, .bottom])

                            Divider()

                            HStack(spacing: 12) {
                                Button(role: .cancel) { withAnimation(.easeInOut) { showConfirmOverlay = false } } label: {
                                    Text("Cancel").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    // Save immediately; dismissal occurs together on success
                                    saveBooking()
                                } label: {
                                    Text("Confirm Booking Time").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedCoachId.isEmpty || auth.user == nil || !(startAt < endAt))
                            }
                            .padding()
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(UIColor.systemBackground))
                        )
                        .frame(maxWidth: 560)
                        .padding(24)
                        .shadow(radius: 12)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .animation(.easeInOut, value: showConfirmOverlay)
        )
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
                    // Dismiss both sheets simultaneously
                    withAnimation {
                        self.showConfirmOverlay = false
                        self.showSheet = false
                    }
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
