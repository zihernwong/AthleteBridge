import SwiftUI

struct BookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var showingNewBooking = false

    private var currentUserRole: String? { firestore.currentUserType?.uppercased() }

    var body: some View {
        NavigationStack {
            List {
                // Debug section
                Section(header: Text("Debug")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(firestore.bookingsDebug.isEmpty ? "No debug messages yet" : firestore.bookingsDebug)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)

                        HStack {
                            Spacer()
                            Button("Clear Debug") { firestore.bookingsDebug = "" }
                            Spacer()
                        }
                        .font(.caption2)
                    }
                    .padding(.vertical, 4)
                }

                // Requested bookings section for coaches
                if currentUserRole == "COACH" {
                    Section(header: Text("Requested Bookings")) {
                        let requested = firestore.coachBookings.filter { ($0.status ?? "").lowercased() == "requested" }
                        if requested.isEmpty {
                            Text("No requested bookings").foregroundColor(.secondary)
                        } else {
                            ForEach(requested, id: \.id) { b in
                                VStack(alignment: .leading, spacing: 8) {
                                    BookingRowView(item: b)
                                    HStack {
                                        Spacer()
                                        Button(action: { acceptBooking(b) }) {
                                            Text("Accept")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.blue)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                // Role-specific rendering
                if currentUserRole == "CLIENT" {
                    clientBookingsSection
                } else if currentUserRole == "COACH" {
                    coachBookingsSection
                } else {
                    // fallback: show both while role is unknown
                    clientBookingsSection
                    coachBookingsSection
                }
            }
            .navigationTitle("Bookings")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if currentUserRole == "CLIENT" {
                        Button(action: { showingNewBooking = true }) { Image(systemName: "plus") }
                    }
                }
            }
            .onAppear {
                // fetch both lists (safe) — we can optimize later to fetch only what's needed
                firestore.fetchBookingsForCurrentClientSubcollection()
                firestore.fetchBookingsForCurrentCoachSubcollection()
                firestore.fetchCoaches()
            }
            .sheet(isPresented: $showingNewBooking) {
                NewBookingForm(showSheet: $showingNewBooking)
                    .environmentObject(firestore)
                    .environmentObject(auth)
            }
        }
    }

    private func acceptBooking(_ b: FirestoreManager.BookingItem) {
        firestore.updateBookingStatus(bookingId: b.id, status: "accepted") { err in
            DispatchQueue.main.async {
                if let err = err {
                    // simple error indicator
                    print("acceptBooking error: \(err)")
                } else {
                    // Refresh coach bookings
                    firestore.fetchBookingsForCurrentCoachSubcollection()
                    firestore.showToast("Booking accepted")
                }
            }
        }
    }

    private var clientBookingsSection: some View {
        Section(header: Text("My Bookings")) {
            if firestore.bookings.isEmpty {
                Text("No bookings yet").foregroundColor(.secondary)
            } else {
                ForEach(firestore.bookings, id: \.id) { b in
                    BookingRowView(item: b)
                }
            }
        }
    }

    private var coachBookingsSection: some View {
        Section(header: Text("Accepted Bookings")) {
            VStack(alignment: .leading, spacing: 8) {
                if !firestore.coachBookingsDebug.isEmpty {
                    Text(firestore.coachBookingsDebug)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if firestore.coachBookings.isEmpty {
                Text("No coach bookings found").foregroundColor(.secondary)
            } else {
                ForEach(firestore.coachBookings, id: \.id) { b in
                    BookingRowView(item: b)
                }
            }
        }
    }
}

// Small reusable row view for displaying a booking
struct BookingRowView: View {
    let item: FirestoreManager.BookingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.coachName ?? "Coach").font(.headline)
                Spacer()
                Text(item.status?.capitalized ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let start = item.startAt {
                Text("Start: \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let end = item.endAt {
                Text("End: \(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let location = item.location {
                Text(location).font(.body)
            }
            if let notes = item.notes {
                Text(notes).font(.footnote).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// New booking form (kept similar, but cleaned up)
struct NewBookingForm: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Binding var showSheet: Bool

    let initialCoachId: String? = nil
    let initialStartAt: Date? = nil
    let initialEndAt: Date? = nil
    let initialLocationId: String? = nil

    @State private var selectedCoachId: String? = nil
    @State private var startAt: Date = Date()
    @State private var endAt: Date = Date().addingTimeInterval(60*30)
    @State private var selectedLocationId: String = ""
    @State private var notes: String = ""

    @State private var isSaving = false
    @State private var alertMessage: String = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Client (defaults to signed-in user)")) {
                    if let client = firestore.currentClient {
                        Text("Signed in as: \(client.name)")
                    } else if let uid = auth.user?.uid {
                        Text("Signed in as: \(uid)")
                    } else {
                        Text("Not signed in").foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Coach")) {
                    if firestore.coaches.isEmpty {
                        Text("No coaches available").foregroundColor(.secondary)
                    } else {
                        Picker("Coach", selection: $selectedCoachId) {
                            Text("Select a coach").tag(nil as String?)
                            ForEach(firestore.coaches, id: \.id) { coach in
                                Text(coach.name).tag(coach.id as String?)
                            }
                        }
                        .pickerStyle(.menu)
                        .onAppear {
                            firestore.fetchCoaches()
                            if let pre = initialCoachId { selectedCoachId = pre }
                        }
                    }
                }

                Section(header: Text("When")) {
                    DatePicker("Start", selection: $startAt, displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: startAt) { _, newStart in
                            // If start is at/after end, bump end to start + 30min
                            if newStart >= endAt {
                                endAt = Calendar.current.date(byAdding: .minute, value: 30, to: newStart) ?? newStart.addingTimeInterval(60*30)
                            }
                        }

                    DatePicker("End", selection: $endAt, displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: endAt) { _, newEnd in
                            // If end is at/earlier than start, move start to end - 30min
                            if newEnd <= startAt {
                                startAt = Calendar.current.date(byAdding: .minute, value: -30, to: newEnd) ?? newEnd.addingTimeInterval(-60*30)
                            }
                        }
                }

                Section(header: Text("Details")) {
                    // Location is optional for the booking form in the Bookings tab.
                    if firestore.locations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No saved locations found").foregroundColor(.secondary)
                            Text("leave blank for a virtual session.").font(.caption).foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Location (optional)", selection: $selectedLocationId) {
                            // Explicit 'None' option to allow no-location bookings
                            Text("None").tag("")
                            ForEach(firestore.locations, id: \.id) { loc in
                                Text(loc.name ?? "Unnamed").tag(loc.id)
                            }
                        }
                        .onAppear {
                            // Do not auto-select a saved location here; keep it optional.
                        }
                    }

                    TextEditor(text: $notes).frame(minHeight: 80)
                }

                if isSaving { ProgressView().frame(maxWidth: .infinity, alignment: .center) }
            }
            .navigationTitle("New Booking")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveBooking() }
                        // Disable save if coach not selected, not signed in, or times invalid (start must be before end)
                        .disabled((selectedCoachId ?? "").isEmpty || auth.user == nil || !(startAt < endAt))
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .onAppear {
                firestore.fetchCoaches()
                if let pre = initialCoachId { selectedCoachId = pre }
                if let preStart = initialStartAt { startAt = preStart }
                if let preEnd = initialEndAt { endAt = preEnd }
                if let preLoc = initialLocationId { selectedLocationId = preLoc }
                if let uid = auth.user?.uid {
                    firestore.fetchCurrentProfiles(for: uid)
                    firestore.fetchBookingsFromClientSubcollection(clientId: uid)
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
        guard let coachUid = selectedCoachId, !coachUid.isEmpty else {
            alertMessage = "Select a coach"
            showAlert = true
            return
        }

        // Validate times before saving
        if !(startAt < endAt) {
            alertMessage = "Start time must be before end time"
            showAlert = true
            return
        }

        isSaving = true
        // Allow nil location when no selection made
        let locationName: String? = firestore.locations.first(where: { $0.id == selectedLocationId })?.name
        firestore.saveBooking(clientUid: clientUid, coachUid: coachUid, startAt: startAt, endAt: endAt, location: locationName, notes: notes, status: "requested") { err in
            DispatchQueue.main.async {
                isSaving = false
                if let err = err {
                    alertMessage = "Failed to save booking: \(err.localizedDescription)"
                    showAlert = true
                } else {
                    firestore.fetchBookingsForCurrentClientSubcollection()
                    firestore.showToast("Booking saved")
                    showSheet = false
                }
            }
        }
    }
}

struct BookingsView_Previews: PreviewProvider {
    static var previews: some View {
        BookingsView()
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
