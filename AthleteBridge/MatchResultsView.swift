// MatchResultsView.swift

import SwiftUI

/// `MatchResultsView` shows coaches matched to a client. Optionally accepts `searchQuery`
/// so an external screen (e.g. Find a Coach) can pre-filter by coach name.
 struct MatchResultsView: View {
     let client: Client
     let searchQuery: String?

     @EnvironmentObject var firestore: FirestoreManager
     @State private var coachReviews: [String: [FirestoreManager.ReviewItem]] = [:]
     @State private var coachBookingCounts: [String: Int] = [:]

     init(client: Client, searchQuery: String? = nil) {
         self.client = client
         self.searchQuery = searchQuery
     }

     private func filteredCoaches() -> [Coach] {
         let all = firestore.coaches
         guard let q = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else { return all }
         return all.filter { $0.name.localizedCaseInsensitiveContains(q) }
     }

     var body: some View {
         let items = filteredCoaches()
         List(items) { coach in
             NavigationLink(destination: CoachDetailView(coach: coach).environmentObject(firestore)) {
                 VStack(alignment: .leading, spacing: 8) {
                     HStack(alignment: .top) {
                         VStack(alignment: .leading) {
                             Text(coach.name)
                                 .font(.headline)
                             if !coach.specialties.isEmpty {
                                 Text(coach.specialties.joined(separator: ", "))
                                     .font(.subheadline)
                                     .foregroundColor(.secondary)
                             }
                             Text("Experience: \(coach.experienceYears) years")
                                 .font(.caption)
                                 .foregroundColor(.secondary)
                         }
                         Spacer()
                         if let reviews = coachReviews[coach.id], !reviews.isEmpty {
                             let avg = averageRating(from: reviews)
                             VStack {
                                 Text(String(format: "%.1f", avg))
                                     .font(.headline)
                                 Text("(\(reviews.count))")
                                     .font(.caption)
                                     .foregroundColor(.secondary)
                             }
                         } else {
                             Text("No reviews")
                                 .font(.caption)
                                 .foregroundColor(.secondary)
                         }
                     }

                     // Show number of bookings for this coach (lazy-loaded)
                     HStack {
                         Text("Bookings:").font(.caption).foregroundColor(.secondary)
                         if let count = coachBookingCounts[coach.id] {
                             Text("\(count)").font(.caption).bold()
                         } else {
                             Text("—").font(.caption).foregroundColor(.secondary)
                         }
                         Spacer()
                     }
                 }
                 .padding(.vertical, 6)
             }
             .onAppear {
                 // lazy-load reviews if missing
                 if coachReviews[coach.id] == nil {
                     firestore.fetchReviewsForCoach(coachId: coach.id) { items in
                         DispatchQueue.main.async {
                             coachReviews[coach.id] = items
                         }
                     }
                 }
                 // lazy-load booking counts if missing
                 if coachBookingCounts[coach.id] == nil {
                     firestore.fetchBookingsForCoach(coachId: coach.id) { items in
                         DispatchQueue.main.async {
                             coachBookingCounts[coach.id] = items.count
                         }
                     }
                 }
             }
         }
         .navigationTitle("Your Matches")
         .onAppear {
             // ensure coaches are loaded
             firestore.fetchCoaches()
         }
     }

     private func averageRating(from reviews: [FirestoreManager.ReviewItem]) -> Double {
         let nums = reviews.compactMap { r -> Double? in
             if let s = r.rating, let d = Double(s) { return d }
             return nil
         }
         guard !nums.isEmpty else { return 0 }
         return nums.reduce(0, +) / Double(nums.count)
     }
 }

 // New simple coach detail view that lists reviews for a coach
 struct CoachDetailView: View {
     let coach: Coach
     @EnvironmentObject var firestore: FirestoreManager
     @State private var reviews: [FirestoreManager.ReviewItem] = []
     @State private var bookings: [FirestoreManager.BookingItem] = []
     @State private var loadingBookings: Bool = true

     var body: some View {
         List {
             Section(header: Text(coach.name).font(.title2)) {
                 if !coach.specialties.isEmpty {
                     Text("Specialties: \(coach.specialties.joined(separator: ", "))")
                 }
                 Text("Experience: \(coach.experienceYears) years")
                 if !coach.availability.isEmpty {
                     Text("Availability: \(coach.availability.joined(separator: ", "))")
                         .font(.caption)
                         .foregroundColor(.secondary)
                 }
             }

             // Calendar grid showing selectable time slots; existing bookings are greyed out
             Section(header: Text("Calendar")) {
                 // Show today's calendar for this coach; pass coach.id (String) and a concrete date
                 CoachCalendarGridView(coachID: coach.id, date: Date())
                     .environmentObject(firestore)
             }

             Section(header: Text("Reviews")) {
                 if reviews.isEmpty {
                     Text("No reviews yet").foregroundColor(.secondary)
                 } else {
                     ForEach(reviews) { r in
                         VStack(alignment: .leading) {
                             HStack {
                                 Text(r.clientName ?? "Client")
                                     .font(.headline)
                                 Spacer()
                                 Text(r.rating ?? "-")
                                     .font(.subheadline)
                             }
                             if let msg = r.ratingMessage { Text(msg).font(.body) }
                             if let date = r.createdAt { Text(DateFormatter.shortDateTime.string(from: date)).font(.caption).foregroundColor(.secondary) }
                         }
                         .padding(.vertical, 6)
                     }
                 }
             }
         }
         .navigationTitle("Coach")
         .onAppear {
             firestore.fetchReviewsForCoach(coachId: coach.id) { items in
                 DispatchQueue.main.async { self.reviews = items }
             }
             // fetch bookings for this coach and show them in the Calendar section
             loadingBookings = true
             firestore.fetchBookingsForCoach(coachId: coach.id) { items in
                 DispatchQueue.main.async {
                     // sort ascending by start date to show upcoming first
                     self.bookings = items.sorted { (a,b) in
                         (a.startAt ?? Date.distantFuture) < (b.startAt ?? Date.distantFuture)
                     }
                     self.loadingBookings = false
                 }
             }
         }
     }
 }
