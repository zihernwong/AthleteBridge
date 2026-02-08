import SwiftUI

struct RejectedBookingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var firestore: FirestoreManager

    let booking: FirestoreManager.BookingItem

    private var coachDisplayName: String {
        if let names = booking.coachNames, !names.isEmpty {
            return names.joined(separator: ", ")
        }
        return booking.coachName ?? "Coach"
    }

    private var rejectionReason: String {
        // Try to get rejection reason from booking data
        // This would need to be added to BookingItem if not already there
        return booking.rejectionReason ?? "No reason provided"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Rejection icon
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                    .padding(.top, 40)

                Text("Booking Declined")
                    .font(.title)
                    .bold()

                Text("\(coachDisplayName) has declined your booking request.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Booking details card
                VStack(alignment: .leading, spacing: 12) {
                    if let start = booking.startAt {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.secondary)
                            Text(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .none))
                        }
                    }

                    if let start = booking.startAt, let end = booking.endAt {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.secondary)
                            Text("\(DateFormatter.localizedString(from: start, dateStyle: .none, timeStyle: .short)) - \(DateFormatter.localizedString(from: end, dateStyle: .none, timeStyle: .short))")
                        }
                    }

                    if let location = booking.location, !location.isEmpty {
                        HStack {
                            Image(systemName: "mappin.circle")
                                .foregroundColor(.secondary)
                            Text(location)
                        }
                    }

                    Divider()

                    // Rejection reason
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reason")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(rejectionReason)
                            .font(.body)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
                .padding(.horizontal)

                Spacer()

                Button(action: { dismiss() }) {
                    Text("Close")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
