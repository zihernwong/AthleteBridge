import SwiftUI

/// Compact inline calendar-style view that shows a coach's upcoming bookings.
struct CoachCalendarInlineView: View {
    let coach: Coach
    @EnvironmentObject var firestore: FirestoreManager
    @State private var bookings: [FirestoreManager.BookingItem] = []
    @State private var loading: Bool = true

    var body: some View {
        Group {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 6)
            } else if bookings.isEmpty {
                Text("No bookings").font(.caption).foregroundColor(.secondary).padding(.vertical, 6)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(bookings) { b in
                            BookingInlineCard(item: b)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .onAppear {
            loading = true
            firestore.fetchBookingsForCoach(coachId: coach.id) { items in
                DispatchQueue.main.async {
                    // Show upcoming bookings sorted ascending by start
                    self.bookings = items.sorted { (a,b) in
                        (a.startAt ?? Date.distantFuture) < (b.startAt ?? Date.distantFuture)
                    }
                    self.loading = false
                }
            }
        }
    }
}

// Small view to render a single booking card used inside the inline calendar
fileprivate struct BookingInlineCard: View {
    let item: FirestoreManager.BookingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.clientName ?? item.clientID)
                .font(.subheadline)
                .bold()

            if let start = item.startAt {
                Text(DateFormatter.localizedString(from: start, dateStyle: .none, timeStyle: .short))
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
            if let end = item.endAt {
                Text(DateFormatter.localizedString(from: end, dateStyle: .none, timeStyle: .short))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if let loc = item.location, !loc.isEmpty {
                Text(loc).font(.caption2).foregroundColor(.secondary)
            }
            if let status = item.status {
                Text(status.capitalized).font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .shadow(radius: 0.5)
    }
}

struct CoachCalendarInlineView_Previews: PreviewProvider {
    static var previews: some View {
        CoachCalendarInlineView(coach: Coach(id: "demo", name: "Demo Coach", specialties: ["Tennis"], experienceYears: 3, availability: ["Morning"]))
            .environmentObject(FirestoreManager())
            .previewLayout(.sizeThatFits)
    }
}
