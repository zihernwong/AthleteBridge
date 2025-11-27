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
                            VStack(alignment: .leading, spacing: 6) {
                                Text(b.clientName ?? b.clientID)
                                    .font(.subheadline)
                                    .bold()
                                if let start = b.startAt {
                                    Text(DateFormatter.shortDateTime.string(from: start))
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                }
                                if let end = b.endAt {
                                    Text(DateFormatter.shortDateTime.string(from: end))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                if let loc = b.location, !loc.isEmpty {
                                    Text(loc).font(.caption2).foregroundColor(.secondary)
                                }
                                if let status = b.status { Text(status.capitalized).font(.caption2).foregroundColor(.secondary) }
                            }
                            .padding(10)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(10)
                            .shadow(radius: 0.5)
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

struct CoachCalendarInlineView_Previews: PreviewProvider {
    static var previews: some View {
        CoachCalendarInlineView(coach: Coach(id: "demo", name: "Demo Coach", specialties: ["Tennis"], experienceYears: 3, availability: ["Morning"]))
            .environmentObject(FirestoreManager())
            .previewLayout(.sizeThatFits)
    }
}
