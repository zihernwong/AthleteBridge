import SwiftUI

struct BookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var showingNewBooking = false
    @State private var selectedBookingForAccept: FirestoreManager.BookingItem? = nil
    @State private var selectedConfirmBooking: FirestoreManager.BookingItem? = nil

    private var currentUserRole: String? { firestore.currentUserType?.uppercased() }

    private var clientBookingsSection: some View {
        VStack(spacing: 12) {
            Section(header: Text("My Bookings")) {
                if firestore.bookings.isEmpty {
                    Text("No bookings yet").foregroundColor(.secondary)
                } else {
                    ForEach(firestore.bookings, id: \.id) { b in
                        BookingRowView(item: b)
                    }
                }
            }

            // Pending offers from coaches where client needs to confirm
            Section(header: Text("Pending Offers")) {
                let pending = firestore.bookings.filter { ($0.status ?? "").lowercased() == "pending acceptance" }
                if pending.isEmpty {
                    Text("No pending offers").foregroundColor(.secondary)
                } else {
                    ForEach(pending, id: \.id) { b in
                        VStack(alignment: .leading, spacing: 8) {
                            BookingRowView(item: b)
                            HStack {
                                Spacer()
                                Button(action: { self.selectedConfirmBooking = b }) {
                                    Text("View Appointment")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if currentUserRole == "CLIENT" {
                    clientBookingsSection
                } else if currentUserRole == "COACH" {
                    // For coaches show their coachBookings (simple list)
                    Section(header: Text("Coach Bookings")) {
                        if firestore.coachBookings.isEmpty {
                            Text("No coach bookings").foregroundColor(.secondary)
                        } else {
                            ForEach(firestore.coachBookings, id: \.id) { b in
                                BookingRowView(item: b)
                            }
                        }
                    }
                } else {
                    // fallback show both
                    clientBookingsSection
                    Section(header: Text("Coach Bookings")) {
                        ForEach(firestore.coachBookings, id: \.id) { b in
                            BookingRowView(item: b)
                        }
                    }
                }
            }
            .navigationTitle("Bookings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if currentUserRole == "CLIENT" {
                        Button(action: { showingNewBooking = true }) { Image(systemName: "plus") }
                    }
                }
            }
            .onAppear {
                firestore.fetchBookingsForCurrentClientSubcollection()
                firestore.fetchBookingsForCurrentCoachSubcollection()
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
            .sheet(item: $selectedConfirmBooking) { booking in
                ConfirmBookingView(booking: booking)
                    .environmentObject(firestore)
                    .environmentObject(auth)
            }
        }
    }
}

// Minimal reusable BookingRowView used in BookingsView. Kept simple to avoid referencing other UI pieces.
struct BookingRowView: View {
    let item: FirestoreManager.BookingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.coachName ?? "Coach").font(.headline)
                Spacer()
                Text(item.status?.capitalized ?? "").font(.caption).foregroundColor(.secondary)
            }
            if let start = item.startAt {
                Text("Start: \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            if let end = item.endAt {
                Text("End: \(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            if let location = item.location, !location.isEmpty { Text(location).font(.body) }
            if let notes = item.notes, !notes.isEmpty { Text(notes).font(.footnote).foregroundColor(.secondary) }
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
