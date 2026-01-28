import SwiftUI
import FirebaseAuth

// Unified booking editor used by BookingsView and other places.
struct BookingEditorView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Binding var showSheet: Bool

    @State private var selectedCoachId: String = ""
    @State private var coachSearchText: String = ""
    @State private var startAt: Date = Date()
    @State private var endAt: Date = Date().addingTimeInterval(60*60)

    // Group booking support
    @State private var isGroupBooking: Bool = false
    @State private var selectedCoachIds: Set<String> = []
    @State private var selectedCoachNames: Set<String> = []
    @State private var selectedClientIds: Set<String> = []
    @State private var selectedClientNames: Set<String> = []

    // Reviews for selected coach
    @State private var coachReviews: [FirestoreManager.ReviewItem] = []

    // For presenting chat sheet
    private struct ChatSheetId: Identifiable { let id: String }
    @State private var presentedChat: ChatSheetId? = nil
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

    // Cache the selected coach lookup
    private var selectedCoach: Coach? {
        selectedCoachId.isEmpty ? nil : firestore.coaches.first(where: { $0.id == selectedCoachId })
    }

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
        self._endAt = State(initialValue: initialEnd ?? (initialStart ?? Date()).addingTimeInterval(60*60))
        self._selectedLocationId = State(initialValue: initialLocationId ?? "")
        self._notes = State(initialValue: initialNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isGroupBooking {
                        // Multi-select clients for group bookings
                        VStack(alignment: .leading, spacing: 8) {
                            if let currentClient = firestore.currentClient {
                                HStack {
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.green)
                                    Text("You: \(currentClient.name)")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("(included)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Filter out current user from the client list
                            let otherClients = firestore.clients.filter { $0.id != auth.user?.uid }
                            if !otherClients.isEmpty {
                                MultiSelectDropdown(
                                    title: "Add Other Clients",
                                    items: otherClients.map { $0.name },
                                    selection: $selectedClientNames,
                                    placeholder: "Tap to add more clients"
                                )
                                .onChange(of: selectedClientNames) { _, newNames in
                                    // Sync IDs with names
                                    selectedClientIds = Set(newNames.compactMap { name in
                                        firestore.clients.first(where: { $0.name == name })?.id
                                    })
                                }
                            }

                            let totalClients = 1 + selectedClientIds.count
                            if totalClients > 1 {
                                Text("\(totalClients) clients in this session")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    } else {
                        // Single client (current user) for regular bookings
                        if let client = firestore.currentClient {
                            Text("Signed in as: \(client.name)")
                        } else if let uid = auth.user?.uid {
                            // fallback: show uid while we fetch profile
                            Text("Signed in as: \(uid)")
                        } else {
                            Text("Not signed in").foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text(isGroupBooking ? "Clients" : "Client (defaults to signed-in user)")
                }

                // Group Booking Toggle
                Section {
                    Toggle("Group Booking", isOn: $isGroupBooking)
                        .onChange(of: isGroupBooking) { _, newValue in
                            if newValue {
                                // When enabling group booking, add currently selected coach to set
                                if !selectedCoachId.isEmpty {
                                    selectedCoachIds.insert(selectedCoachId)
                                    if let coach = selectedCoach {
                                        selectedCoachNames.insert(coach.name)
                                    }
                                }
                                // Fetch clients list for multi-select
                                firestore.fetchClients()
                            } else {
                                // When disabling, use first selected coach as the single selection
                                if let firstId = selectedCoachIds.first {
                                    selectedCoachId = firstId
                                    if let coach = firestore.coaches.first(where: { $0.id == firstId }) {
                                        coachSearchText = coach.name
                                    }
                                }
                                selectedCoachIds.removeAll()
                                selectedCoachNames.removeAll()
                                // Clear client selections
                                selectedClientIds.removeAll()
                                selectedClientNames.removeAll()
                            }
                        }
                    if isGroupBooking {
                        Text("Select multiple coaches and/or clients for a group session")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Booking Type")
                }

                Section {
                    if firestore.coaches.isEmpty {
                        Text("No coaches available").foregroundColor(.secondary)
                    } else if isGroupBooking {
                        // Multi-select mode for group bookings
                        VStack(alignment: .leading, spacing: 8) {
                            MultiSelectDropdown(
                                title: "Select Coaches",
                                items: firestore.coaches.map { $0.name },
                                selection: $selectedCoachNames,
                                placeholder: "Tap to select coaches"
                            )
                            .onChange(of: selectedCoachNames) { _, newNames in
                                // Sync IDs with names
                                selectedCoachIds = Set(newNames.compactMap { name in
                                    firestore.coaches.first(where: { $0.name == name })?.id
                                })
                                // Update single selection for compatibility
                                if let firstId = selectedCoachIds.first {
                                    selectedCoachId = firstId
                                }
                            }

                            if !selectedCoachIds.isEmpty {
                                Text("\(selectedCoachIds.count) coach\(selectedCoachIds.count > 1 ? "es" : "") selected")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        // Single coach selection (original behavior)
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

                            if let selected = selectedCoach {
                                Text("Selected: \(selected.name)")
                                    .font(.subheadline)
                            } else if !selectedCoachId.isEmpty {
                                Text("Selected coach id: \(selectedCoachId)")
                                    .font(.subheadline)
                            }
                        }
                    }
                } header: {
                    Text(isGroupBooking ? "Coaches" : "Coach")
                }

                // Only after a coach is selected, show Coach Info and Calendar
                if let coach = selectedCoach {
                    // Coach Info section (above the calendar)
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            let coachURL = firestore.coachPhotoURLs[coach.id] ?? nil
                            AvatarView(url: coachURL ?? nil, size: 72, useCurrentUser: false)
                            VStack(alignment: .leading, spacing: 8) {
                                if let bio = coach.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(bio).font(.body).foregroundColor(.primary)
                                } else {
                                    Text("No bio provided").font(.subheadline).foregroundColor(.secondary)
                                }
                            }
                        }
                        if !coach.specialties.isEmpty {
                            Text("Specialties: \(coach.specialties.joined(separator: ", "))")
                        }
                        Text("Experience: \(coach.experienceYears) years")
                        if let range = coach.rateRange, range.count >= 2 {
                            Text(String(format: "$%.0f - $%.0f / hr", range[0], range[1]))
                        } else {
                            Text("Message coach for rate").foregroundColor(.secondary)
                        }
                        if !coach.availability.isEmpty {
                            Text("Availability: \(coach.availability.joined(separator: ", "))")
                        }

                        // Message Coach button
                        Button(action: {
                            guard Auth.auth().currentUser?.uid != nil else {
                                firestore.showToast("Please sign in to message coaches")
                                return
                            }
                            let expectedChatId = [Auth.auth().currentUser?.uid ?? "", coach.id].sorted().joined(separator: "_")
                            presentedChat = ChatSheetId(id: expectedChatId)
                            firestore.createOrGetChat(withCoachId: coach.id) { chatId in
                                DispatchQueue.main.async {
                                    let target = chatId ?? expectedChatId
                                    if target != expectedChatId {
                                        presentedChat = ChatSheetId(id: target)
                                    }
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "message.fill")
                                Text("Message Coach")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)

                        // Reviews summary section
                        VStack(alignment: .leading, spacing: 8) {
                            let avgRating = coachReviews.isEmpty ? 0.0 : coachReviews.compactMap { r -> Double? in
                                if let s = r.rating, let d = Double(s) { return d }
                                return nil
                            }.reduce(0, +) / Double(coachReviews.count)

                            HStack(spacing: 8) {
                                HStack(spacing: 2) {
                                    ForEach(1...5, id: \.self) { i in
                                        Image(systemName: Double(i) <= avgRating ? "star.fill" : (Double(i) - 0.5 <= avgRating ? "star.leadinghalf.filled" : "star"))
                                            .foregroundColor(.yellow)
                                            .font(.subheadline)
                                    }
                                }

                                Text(String(format: "%.1f", avgRating))
                                    .font(.headline)

                                Text("(\(coachReviews.count) reviews)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            NavigationLink(destination: CoachReviewsListView(coach: coach, reviews: coachReviews)) {
                                Text("View All Reviews")
                                    .font(.subheadline)
                            }
                        }
                        .padding(.top, 8)
                    } header: {
                        Text(coach.name)
                    }

                    // Show coach calendar grid once a coach is selected; hide time pickers
                    Section {
                        // Show merged availability info for group bookings
                        if isGroupBooking && selectedCoachIds.count > 1 {
                            HStack {
                                Image(systemName: "calendar.badge.checkmark")
                                    .foregroundColor(.blue)
                                Text("Showing combined availability for \(selectedCoachIds.count) coaches")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }

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
                                              coachIDs: isGroupBooking ? Array(selectedCoachIds) : nil,
                                              date: $calendarDate,
                                              showOnlyAvailable: false,
                                              onSlotSelected: nil,
                                              embedMode: true,
                                              onAvailableSlot: { start, end in
                                                  selectedSlotStart = start
                                                  // Enforce minimum 1-hour booking from selected slot
                                                  let minEnd = start.addingTimeInterval(3600)
                                                  selectedSlotEnd = max(end, minEnd)
                                                  startAt = start
                                                  endAt = max(end, minEnd)
                                                  showConfirmOverlay = true
                                              })
                            .environmentObject(firestore)
                            .environmentObject(auth)
                            .id("\(calendarDate)-\(Array(selectedCoachIds).sorted().joined(separator: ","))")

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
                        Text(isGroupBooking && selectedCoachIds.count > 1 ? "Combined Coach Availability" : "Coach Calendar")
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
                                if let coach = selectedCoach {
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
                                        // Enforce minimum 1-hour booking
                                        if endAt.timeIntervalSince(startAt) < 3600 { endAt = Calendar.current.date(byAdding: .hour, value: 1, to: startAt) ?? startAt.addingTimeInterval(3600) }
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
                                        // Enforce minimum 1-hour booking
                                        if endAt.timeIntervalSince(startAt) < 3600 { startAt = Calendar.current.date(byAdding: .hour, value: -1, to: endAt) ?? endAt.addingTimeInterval(-3600) }
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
                                .disabled(selectedCoachId.isEmpty || auth.user == nil || !(startAt < endAt) || endAt.timeIntervalSince(startAt) < 3600)
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
        .onChange(of: selectedCoachId) { _, newCoachId in
            // Fetch reviews when coach is selected
            if !newCoachId.isEmpty {
                firestore.fetchReviewsForCoach(coachId: newCoachId) { items in
                    DispatchQueue.main.async { coachReviews = items }
                }
            } else {
                coachReviews = []
            }
        }
        .sheet(item: $presentedChat) { sheet in
            ChatView(chatId: sheet.id)
                .environmentObject(firestore)
        }
    }

    private func saveBooking() {
        guard let clientUid = auth.user?.uid, !clientUid.isEmpty else {
            alertMessage = "You must be signed in to create a booking"
            showAlert = true
            return
        }

        // Get coach IDs based on booking type
        let coachIdsToBook: [String]
        if isGroupBooking {
            coachIdsToBook = Array(selectedCoachIds)
            guard !coachIdsToBook.isEmpty else {
                alertMessage = "Select at least one coach for group booking"
                showAlert = true
                return
            }
        } else {
            guard !selectedCoachId.isEmpty else {
                alertMessage = "Select a coach"
                showAlert = true
                return
            }
            coachIdsToBook = [selectedCoachId]
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
        // Enforce minimum 1-hour booking
        if endAt.timeIntervalSince(startAt) < 3600 {
            alertMessage = "Minimum booking length is 1 hour"
            showAlert = true
            return
        }

        isSaving = true

        // Check for overlapping bookings for ALL coaches
        let dayStart = Calendar.current.startOfDay(for: startAt)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? startAt

        // For group bookings, check all coaches for overlaps
        let group = DispatchGroup()
        var hasOverlap = false
        var overlapCoachName: String? = nil

        for coachId in coachIdsToBook {
            group.enter()
            firestore.fetchBookingsForCoach(coachId: coachId, start: dayStart, end: dayEnd) { existingBookings in
                let overlapping = existingBookings.filter { b in
                    guard let bStart = b.startAt, let bEnd = b.endAt else { return false }
                    let status = (b.status ?? "").lowercased()
                    guard status == "requested" || status == "confirmed" || status == "pending acceptance" || status == "partially_accepted" else { return false }
                    return bStart < self.endAt && bEnd > self.startAt
                }
                if !overlapping.isEmpty {
                    hasOverlap = true
                    if let coach = self.firestore.coaches.first(where: { $0.id == coachId }) {
                        overlapCoachName = coach.name
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if hasOverlap {
                self.isSaving = false
                if let coachName = overlapCoachName {
                    self.alertMessage = "\(coachName) already has a booking at this time. Please choose a different time."
                } else {
                    self.alertMessage = "One or more coaches have a conflicting booking. Please choose a different time."
                }
                self.showAlert = true
                return
            }

            // No overlap — proceed with save
            self.performSave(coachIds: coachIdsToBook, clientUid: clientUid)
        }
    }

    private func performSave(coachIds: [String], clientUid: String) {
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

        // Determine location name from the selected saved location id
        let locationName: String? = firestore.locations.first(where: { $0.id == selectedLocationId })?.name

        let saveCompletion: (Error?) -> Void = { err in
            DispatchQueue.main.async {
                uiTimeoutItem?.cancel()
                self.isSaving = false
                if let err = err {
                    self.alertMessage = "Failed to save booking: \(err.localizedDescription)"
                    self.showAlert = true
                } else {
                    self.firestore.fetchBookingsForCurrentClientSubcollection()
                    self.firestore.showToast(self.isGroupBooking ? "Group booking saved" : "Booking saved")
                    withAnimation {
                        self.showConfirmOverlay = false
                        self.showSheet = false
                    }
                }
            }
        }

        // Build client IDs list - always include current user, plus any additional selected clients
        var allClientIds = [clientUid]
        if isGroupBooking {
            // Add other selected clients (excluding current user to avoid duplicates)
            let additionalClients = Array(selectedClientIds).filter { $0 != clientUid }
            allClientIds.append(contentsOf: additionalClients)
        }

        // Use group booking if multiple coaches OR multiple clients
        let isMultiParticipant = isGroupBooking || coachIds.count > 1 || allClientIds.count > 1

        if isMultiParticipant {
            // Use group booking function
            firestore.saveGroupBooking(
                coachIds: coachIds,
                clientIds: allClientIds,
                startAt: startAt,
                endAt: endAt,
                location: locationName,
                notes: notes,
                creatorID: clientUid,
                creatorType: "client",
                completion: saveCompletion
            )
        } else {
            // Use regular booking function for single coach
            let coachUid = coachIds[0]
            let clientNameExtra = firestore.currentClient?.name ?? ""
            let coachNameExtra = selectedCoach?.name ?? ""
            let extra: [String: Any] = {
                var m: [String: Any] = [:]
                if !clientNameExtra.isEmpty { m["ClientName"] = clientNameExtra }
                if !coachNameExtra.isEmpty { m["CoachName"] = coachNameExtra }
                return m
            }()
            firestore.saveBookingAndMirror(
                coachId: coachUid,
                clientId: clientUid,
                startAt: startAt,
                endAt: endAt,
                status: "requested",
                location: locationName,
                notes: notes,
                extra: extra,
                completion: saveCompletion
            )
        }
    }
}

struct BookingEditorView_Previews: PreviewProvider {
    static var previews: some View {
        BookingEditorView(showSheet: .constant(true), initialCoachId: "", initialStart: Date(), initialEnd: Date().addingTimeInterval(3600))
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
