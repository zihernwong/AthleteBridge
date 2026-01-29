import SwiftUI
import FirebaseFirestore

struct ClientRequestedBookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var bookingToCancel: FirestoreManager.BookingItem? = nil
    @State private var showCancelAlert: Bool = false
    @State private var selectedTab: Int = 0

    private func isRequested(_ status: String?) -> Bool {
        let s = (status ?? "").lowercased()
        return s == "requested"
    }

    private var upcomingRequested: [FirestoreManager.BookingItem] {
        let now = Date()
        return firestore.bookings
            .filter { isRequested($0.status) }
            .filter { ($0.startAt ?? .distantFuture) >= now }
            .sorted { ($0.startAt ?? .distantFuture) < ($1.startAt ?? .distantFuture) }
    }

    private var pastRequested: [FirestoreManager.BookingItem] {
        let now = Date()
        return firestore.bookings
            .filter { isRequested($0.status) }
            .filter { ($0.startAt ?? .distantFuture) < now }
            .sorted { ($0.startAt ?? .distantPast) > ($1.startAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("These bookings are waiting for coach acceptance.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)

            HStack(spacing: 0) {
                Button {
                    selectedTab = 0
                } label: {
                    Text("Upcoming")
                        .font(.subheadline.weight(selectedTab == 0 ? .semibold : .regular))
                        .foregroundColor(selectedTab == 0 ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedTab == 0 ? Color("LogoGreen") : Color(UIColor.secondarySystemBackground))
                }
                Button {
                    selectedTab = 1
                } label: {
                    Text("Past")
                        .font(.subheadline.weight(selectedTab == 1 ? .semibold : .regular))
                        .foregroundColor(selectedTab == 1 ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedTab == 1 ? Color("LogoBlue") : Color(UIColor.secondarySystemBackground))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let bookings = selectedTab == 0 ? upcomingRequested : pastRequested
                    let emptyMessage = selectedTab == 0 ? "No upcoming requested bookings" : "No past requested bookings"

                    if bookings.isEmpty {
                        Text(emptyMessage)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } else {
                        ForEach(bookings, id: \.id) { b in
                            VStack(alignment: .leading, spacing: 8) {
                                BookingRowView(item: b)
                                Button(role: .destructive) {
                                    bookingToCancel = b
                                    showCancelAlert = true
                                } label: {
                                    Text("Cancel Request")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Requested Bookings")
        .onAppear {
            if let uid = auth.user?.uid {
                firestore.fetchBookingsFromClientSubcollection(clientId: uid)
            } else {
                firestore.fetchBookingsForCurrentClientSubcollection()
            }
        }
        .alert("Cancel Request", isPresented: $showCancelAlert) {
            Button("Keep Request", role: .cancel) { }
            Button("Cancel Request", role: .destructive) {
                if let booking = bookingToCancel {
                    cancelBooking(booking)
                }
            }
        } message: {
            Text("Are you sure you want to cancel this booking request? The coach will be notified.")
        }
    }

    private func cancelBooking(_ booking: FirestoreManager.BookingItem) {
        let isGroup = booking.isGroupBooking ?? false || booking.allCoachIDs.count > 1

        let updateFunc: (@escaping (Error?) -> Void) -> Void = { completion in
            if isGroup {
                self.firestore.updateGroupBookingStatus(bookingId: booking.id, status: "cancelled", completion: completion)
            } else {
                self.firestore.updateBookingStatus(bookingId: booking.id, status: "cancelled", completion: completion)
            }
        }

        updateFunc { err in
            DispatchQueue.main.async {
                if let err = err {
                    self.firestore.showToast("Failed to cancel: \(err.localizedDescription)")
                } else {
                    let clientName = self.firestore.currentClient?.name ?? "Client"
                    let coachIds = booking.allCoachIDs
                    for coachId in coachIds {
                        let notifRef = Firestore.firestore().collection("pendingNotifications").document(coachId).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": isGroup ? "Group Booking Request Cancelled" : "Booking Request Cancelled",
                            "body": "\(clientName) has cancelled their \(isGroup ? "group " : "")booking request.",
                            "bookingId": booking.id,
                            "senderId": booking.clientID,
                            "isGroupBooking": isGroup,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { _ in }
                    }
                    self.firestore.showToast("Request cancelled")
                    self.firestore.fetchBookingsForCurrentClientSubcollection()
                }
            }
        }
    }
}

struct ClientRequestedBookingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ClientRequestedBookingsView()
                .environmentObject(FirestoreManager())
                .environmentObject(AuthViewModel())
        }
    }
}
