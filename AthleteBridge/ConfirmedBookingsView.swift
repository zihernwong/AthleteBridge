import SwiftUI
import FirebaseFirestore

struct ConfirmedBookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var bookingToCancel: FirestoreManager.BookingItem? = nil
    @State private var showCancelAlert: Bool = false

    @State private var bookingToReschedule: FirestoreManager.BookingItem? = nil

    private func isConfirmed(_ status: String?) -> Bool {
        let s = (status ?? "").lowercased()
        return s == "confirmed" || s == "accepted" || s == "approved"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let confirmed = firestore.bookings.filter { isConfirmed($0.status) }
                if confirmed.isEmpty {
                    Text("No confirmed bookings")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(confirmed, id: \ .id) { b in
                        VStack(alignment: .leading, spacing: 8) {
                            BookingRowView(item: b)
                            Button(role: .destructive) {
                                bookingToCancel = b
                                showCancelAlert = true
                            } label: {
                                Text("Cancel Booking")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                bookingToReschedule = b
                            } label: {
                                Text("Reschedule Booking")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("Confirmed Bookings")
        .onAppear {
            if let uid = auth.user?.uid {
                firestore.fetchBookingsFromClientSubcollection(clientId: uid)
            } else {
                firestore.fetchBookingsForCurrentClientSubcollection()
            }
        }
        .alert("Cancel Booking", isPresented: $showCancelAlert) {
            Button("Keep Booking", role: .cancel) { }
            Button("Cancel Booking", role: .destructive) {
                if let booking = bookingToCancel {
                    cancelBooking(booking)
                }
            }
        } message: {
            Text("Are you sure you want to cancel this booking? The coach will be notified.")
        }
        .sheet(item: $bookingToReschedule) { booking in
            ClientRescheduleView(booking: booking) {
                bookingToReschedule = nil
                firestore.fetchBookingsForCurrentClientSubcollection()
            }
            .environmentObject(firestore)
            .environmentObject(auth)
        }
    }

    private func cancelBooking(_ booking: FirestoreManager.BookingItem) {
        firestore.updateBookingStatus(bookingId: booking.id, status: "cancelled") { err in
            DispatchQueue.main.async {
                if let err = err {
                    firestore.showToast("Failed to cancel: \(err.localizedDescription)")
                } else {
                    if !booking.coachID.isEmpty {
                        let clientName = firestore.currentClient?.name ?? "Client"
                        let notifRef = Firestore.firestore().collection("pendingNotifications").document(booking.coachID).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Booking Cancelled",
                            "body": "\(clientName) has cancelled the booking.",
                            "bookingId": booking.id,
                            "senderId": booking.clientID,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { _ in }
                    }
                    firestore.showToast("Booking cancelled")
                    firestore.fetchBookingsForCurrentClientSubcollection()
                }
            }
        }
    }
}

// MARK: - Client Reschedule View (shows coach calendar availability)
struct ClientRescheduleView: View {
    let booking: FirestoreManager.BookingItem
    let onComplete: () -> Void

    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var calendarDate: Date = Date()
    @State private var startAt: Date = Date()
    @State private var endAt: Date = Date().addingTimeInterval(3600)
    @State private var showConfirmOverlay: Bool = false
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Day navigation
                HStack {
                    Button(action: { calendarDate = Calendar.current.date(byAdding: .day, value: -1, to: calendarDate) ?? calendarDate }) {
                        Image(systemName: "chevron.left").font(.headline)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(DateFormatter.localizedString(from: calendarDate, dateStyle: .medium, timeStyle: .none))
                        .font(.subheadline).bold()
                    Spacer()
                    Button(action: { calendarDate = Calendar.current.date(byAdding: .day, value: 1, to: calendarDate) ?? calendarDate }) {
                        Image(systemName: "chevron.right").font(.headline)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                Text("Tap an available slot to select a new time")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)

                // Coach calendar grid (already contains its own ScrollView)
                CoachCalendarGridView(coachID: booking.coachID,
                                      date: $calendarDate,
                                      showOnlyAvailable: false,
                                      onSlotSelected: nil,
                                      embedMode: true,
                                      onAvailableSlot: { start, end in
                                          let minEnd = start.addingTimeInterval(3600)
                                          startAt = start
                                          endAt = max(end, minEnd)
                                          showConfirmOverlay = true
                                      })
                    .environmentObject(firestore)
                    .environmentObject(auth)
                    .id(calendarDate)
            }
            .navigationTitle("Reschedule Booking")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                calendarDate = Calendar.current.startOfDay(for: booking.startAt ?? Date())
            }
            .overlay(
                Group {
                    if showConfirmOverlay {
                        ZStack {
                            Color.black.opacity(0.35)
                                .ignoresSafeArea()
                                .onTapGesture { withAnimation(.easeInOut) { showConfirmOverlay = false } }

                            VStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Confirm New Time").font(.headline)
                                    if let coachName = booking.coachName {
                                        Text("Coach: \(coachName)")
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
                                        confirmReschedule()
                                    } label: {
                                        if isSaving {
                                            ProgressView()
                                                .frame(maxWidth: .infinity)
                                        } else {
                                            Text("Confirm Reschedule").frame(maxWidth: .infinity)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isSaving || !(startAt < endAt) || endAt.timeIntervalSince(startAt) < 3600)
                                }
                                .padding()
                            }
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(UIColor.systemBackground)))
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
    }

    private func confirmReschedule() {
        isSaving = true
        firestore.rescheduleBooking(bookingId: booking.id, newStart: startAt, newEnd: endAt, newStatus: "requested") { err in
            DispatchQueue.main.async {
                isSaving = false
                if let err = err {
                    firestore.showToast("Failed to reschedule: \(err.localizedDescription)")
                } else {
                    if !booking.coachID.isEmpty {
                        let clientName = firestore.currentClient?.name ?? "Client"
                        let notifRef = Firestore.firestore().collection("pendingNotifications").document(booking.coachID).collection("notifications").document()
                        let notifPayload: [String: Any] = [
                            "title": "Booking Reschedule Requested",
                            "body": "\(clientName) has requested to reschedule the booking.",
                            "bookingId": booking.id,
                            "senderId": booking.clientID,
                            "createdAt": FieldValue.serverTimestamp(),
                            "delivered": false
                        ]
                        notifRef.setData(notifPayload) { _ in }
                    }
                    firestore.showToast("Reschedule requested")
                    onComplete()
                }
            }
        }
    }
}

struct ConfirmedBookingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ConfirmedBookingsView()
                .environmentObject(FirestoreManager())
                .environmentObject(AuthViewModel())
        }
    }
}
