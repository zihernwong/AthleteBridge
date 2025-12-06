import SwiftUI

struct BookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var showingNewBooking = false
    @State private var selectedBookingForAccept: FirestoreManager.BookingItem? = nil
    @State private var selectedBookingForReview: FirestoreManager.BookingItem? = nil
    
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
                                        Button(action: {
                                            // set selected booking - sheet(item:) will present when non-nil
                                            self.selectedBookingForAccept = b
                                        }) {
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
                BookingEditorView(showSheet: $showingNewBooking)
                    .environmentObject(firestore)
                    .environmentObject(auth)
            }
            .sheet(item: $selectedBookingForAccept) { booking in
                AcceptBookingView(booking: booking)
                    .environmentObject(firestore)
                    .environmentObject(auth)
            }
            .sheet(item: $selectedBookingForReview) { booking in
                ReviewBookingView(booking: booking)
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
                    VStack(alignment: .leading, spacing: 6) {
                        BookingRowView(item: b)

                        // If booking is pending acceptance, show a Review Booking button for clients
                        if (b.status ?? "").lowercased() == "pending acceptance" {
                            HStack {
                                Spacer()
                                Button(action: { selectedBookingForReview = b }) {
                                    Text("Review Booking")
                                }
                                .buttonStyle(.bordered)
                                .tint(.blue)
                            }
                        }
                    }
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

struct BookingsView_Previews: PreviewProvider {
    static var previews: some View {
        BookingsView()
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
