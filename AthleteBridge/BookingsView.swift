import SwiftUI

struct BookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var showingNewBooking = false

    var body: some View {
        NavigationStack {
            List {
                // Debug info at the top for troubleshooting
                Section(header: Text("Debug")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(firestore.bookingsDebug.isEmpty ? "No debug messages yet" : firestore.bookingsDebug)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                        HStack {
                            Spacer()
                            Button("Refresh Debug") {
                                firestore.bookingsDebug = "Refreshing debug (all bookings)..."
                                firestore.fetchAllBookingsDebug()
                            }
                            Spacer()
                            Button("Clear Debug") {
                                firestore.bookingsDebug = ""
                            }
                            Spacer()
                        }
                        .font(.caption2)
                    }
                    .padding(.vertical, 4)
                }

                // Bookings where the current user is the client
                Section(header: Text("My Bookings")) {
                    if firestore.bookings.isEmpty {
                        Text("No bookings yet").foregroundColor(.secondary)
                    } else {
                        ForEach(firestore.bookings) { b in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(b.coachName ?? "Coach")
                                        .font(.headline)
                                    Spacer()
                                    Text(b.status?.capitalized ?? "")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if let start = b.startAt {
                                    Text("Start: \(start, formatter: DateFormatter.shortDateTime)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                if let end = b.endAt {
                                    Text("End: \(end, formatter: DateFormatter.shortDateTime)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                if let location = b.location {
                                    Text(location).font(.body)
                                }
                                if let notes = b.notes {
                                    Text(notes).font(.footnote).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }

                // Aggregated coach-side bookings (for the current user as a coach)
                Section(header: Text("Coach-side Bookings")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(firestore.coachBookingsDebug.isEmpty ? "" : firestore.coachBookingsDebug)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        HStack {
                            Spacer()
                            Button("Refresh Coach Bookings") {
                                // Fetch only the bookings under the currently authenticated coach's subcollection
                                firestore.fetchBookingsForCurrentCoachSubcollection()
                            }
                            Spacer()
                        }
                    }

                    if firestore.coachBookings.isEmpty {
                        Text("No coach bookings found").foregroundColor(.secondary)
                    } else {
                        ForEach(firestore.coachBookings) { b in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(b.coachName ?? "Coach")
                                        .font(.headline)
                                    Spacer()
                                    Text(b.status?.capitalized ?? "")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if let start = b.startAt {
                                    Text("Start: \(start, formatter: DateFormatter.shortDateTime)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                if let location = b.location {
                                    Text(location).font(.body)
                                }
                                if let notes = b.notes {
                                    Text(notes).font(.footnote).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("Bookings")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showingNewBooking = true }) {
                        Image(systemName: "plus")
                    }
                    Button(action: { firestore.fetchBookingsForCurrentClientSubcollection() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                // Load bookings where user is client
                firestore.fetchBookingsForCurrentClientSubcollection()
                // Also load bookings where user is coach
                firestore.fetchBookingsForCurrentCoachSubcollection()
                // ensure coaches are loaded so the NewBookingForm picker has items
                firestore.fetchCoaches()
            }
            .sheet(isPresented: $showingNewBooking) {
                NewBookingForm(showSheet: $showingNewBooking)
                    .environmentObject(firestore)
                    .environmentObject(auth)
            }
        }
    }
}

// New booking form that posts a booking to Firestore
struct NewBookingForm: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Binding var showSheet: Bool

    @State private var selectedCoachId: String = ""
    @State private var coachSearchText: String = ""
    @State private var startAt: Date = Date()
    @State private var endAt: Date = Date().addingTimeInterval(60*30)
    @State private var location: String = "Burnsville High School"
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
                    TextField("Location", text: $location)
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
                        .disabled(selectedCoachId.isEmpty || auth.user == nil)
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
        // Always create bookings with default status "requested"
        firestore.saveBooking(clientUid: clientUid, coachUid: coachUid, startAt: startAt, endAt: endAt, location: location, notes: notes, status: "requested") { err in
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

// Simple date formatter helper
extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

struct BookingsView_Previews: PreviewProvider {
    static var previews: some View {
        BookingsView()
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
