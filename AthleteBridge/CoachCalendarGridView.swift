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
                             // Hourly rate (or fallback)
                             if let rate = coach.hourlyRate {
                                 Text(String(format: "$%.0f / hr", rate))
                                     .font(.caption)
                                     .foregroundColor(.primary)
                             } else {
                                 Text("Hourly rate to be discussed")
                                     .font(.caption)
                                     .foregroundColor(.secondary)
                             }
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
     // selected date for the embedded coach calendar
     @State private var selectedDate: Date = Date()

     var body: some View {
         List {
             Section {
                 // content
                 if !coach.specialties.isEmpty {
                     Text("Specialties: \(coach.specialties.joined(separator: ", "))")
                 }
                 Text("Experience: \(coach.experienceYears) years")
                 // Hourly rate display
                 if let rate = coach.hourlyRate {
                     Text(String(format: "Hourly Rate: $%.0f / hr", rate))
                         .font(.subheadline)
                 } else {
                     Text("HourlyRate to be discussed")
                         .font(.subheadline)
                         .foregroundColor(.secondary)
                 }
                 if !coach.availability.isEmpty {
                     Text("Availability: \(coach.availability.joined(separator: ", "))")
                         .font(.caption)
                         .foregroundColor(.secondary)
                 }
             } header: {
                 Text(coach.name).font(.title2)
             }

             Section {
                 // Calendar controls: previous / selected date / next
                 HStack {
                     Button(action: {
                         // previous day
                         selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                         print("[CoachDetailView] <- pressed, selectedDate=\(selectedDate)")
                     }) {
                         Image(systemName: "chevron.left")
                             .font(.headline)
                     }
                     .buttonStyle(.plain)
                     Spacer()
                     Text(DateFormatter.localizedString(from: selectedDate, dateStyle: .medium, timeStyle: .none))
                         .font(.subheadline)
                         .bold()
                     Spacer()
                     Button(action: {
                         // next day
                         selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                         print("[CoachDetailView] -> pressed, selectedDate=\(selectedDate)")
                     }) {
                         Image(systemName: "chevron.right")
                             .font(.headline)
                     }
                     .buttonStyle(.plain)
                 }
                 .padding(.vertical, 6)

                 // Embedded calendar grid that reflects the selectedDate (pass binding so changes propagate)
                 CoachCalendarGridView(coachID: coach.id, date: $selectedDate, showOnlyAvailable: false, onSlotSelected: nil)
                     .environmentObject(firestore)
             } header: {
                 Text("Calendar")
             }

             Section {
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
                             if let date = r.createdAt { Text(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)).font(.caption).foregroundColor(.secondary) }
                         }
                         .padding(.vertical, 6)
                     }
                 }
             } header: {
                 Text("Reviews")
             }
         }
         .navigationTitle("Coach")
         .onAppear {
             firestore.fetchReviewsForCoach(coachId: coach.id) { items in
                 DispatchQueue.main.async { self.reviews = items }
             }
             // fetch bookings for this coach and show them in the Calendar section
             loadingBookings = true
             // initial fetch: get bookings around the selectedDate (the day)
             let cal = Calendar.current
             let dayStart = cal.startOfDay(for: selectedDate)
             let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
             firestore.fetchBookingsForCoach(coachId: coach.id, start: dayStart, end: dayEnd) { items in
                 DispatchQueue.main.async {
                     // sort ascending by start date to show upcoming first
                     self.bookings = items.sorted { (a,b) in
                         (a.startAt ?? Date.distantFuture) < (b.startAt ?? Date.distantFuture)
                     }
                     self.loadingBookings = false
                     // booking load completed; the grid will update via binding/onChange
                 }
             }
         }
         .onChange(of: selectedDate) { old, new in
             // when date changes, fetch bookings for that specific day and refresh the calendar
             let cal = Calendar.current
             let dayStart = cal.startOfDay(for: new)
             let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
             self.loadingBookings = true
             firestore.fetchBookingsForCoach(coachId: coach.id, start: dayStart, end: dayEnd) { items in
                 DispatchQueue.main.async {
                     self.bookings = items.sorted { (a,b) in
                         (a.startAt ?? Date.distantFuture) < (b.startAt ?? Date.distantFuture)
                     }
                     self.loadingBookings = false
                     // the grid will update via binding/onChange
                 }
             }
         }
     }
 }

 struct CoachCalendarGridView: View {
     let coachID: String
     @EnvironmentObject var firestore: FirestoreManager
     @Binding var date: Date
     var showOnlyAvailable: Bool = false
     var onSlotSelected: ((FirestoreManager.BookingItem) -> Void)?

     @State private var bookings: [FirestoreManager.BookingItem] = []
     @State private var loading: Bool = true
     @State private var showingNewBookingSheet: Bool = false
     @State private var prefillStart: Date? = nil
     @State private var prefillEnd: Date? = nil

     // Configuration
     private let startHour = 6
     private let endHour = 22
     private let slotMinutes = 30

     private var slots: [Date] {
         generateTimeSlots(for: date, startHour: startHour, endHour: endHour, intervalMinutes: slotMinutes)
     }

     var body: some View {
         VStack(alignment: .leading, spacing: 8) {
             HStack {
                 DatePicker("Date", selection: $date, displayedComponents: .date)
                     .datePickerStyle(.compact)
                     .labelsHidden()
                 Spacer()
             }
             .padding(.vertical, 4)

             HStack(spacing: 12) {
                 HStack(spacing: 6) {
                     RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.35)).frame(width: 18, height: 18)
                     Text("Booked").font(.caption).foregroundColor(.secondary)
                 }
                 HStack(spacing: 6) {
                     RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.2)).frame(width: 18, height: 18)
                     Text("Available").font(.caption).foregroundColor(.secondary)
                 }
                 Spacer()
             }
             .padding(.bottom, 4)

             if loading {
                 HStack { Spacer(); ProgressView(); Spacer() }
             } else {
                 // Grid of slots
                 let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                 ScrollView {
                     LazyVGrid(columns: columns, spacing: 10) {
                         ForEach(slots, id: \.self) { slot in
                             let booked = isSlotBooked(slotStart: slot, slotMinutes: slotMinutes, bookings: bookings)
                             let slotEnd = Calendar.current.date(byAdding: .minute, value: slotMinutes, to: slot) ?? slot
                             Button(action: {
                                 if !booked {
                                     prefillStart = slot
                                     prefillEnd = slotEnd
                                     // if caller supplied a selection handler, call it with a synthetic BookingItem
                                     if let onSelect = onSlotSelected {
                                         var bi = FirestoreManager.BookingItem()
                                         bi.startAt = slot
                                         bi.endAt = slotEnd
                                         bi.coachID = coachID
                                         onSelect(bi)
                                     } else {
                                         showingNewBookingSheet = true
                                     }
                                 }
                             }) {
                                 VStack(alignment: .leading, spacing: 4) {
                                     Text(shortTimeString(from: slot))
                                         .font(.subheadline)
                                         .foregroundColor(.primary)
                                     if booked, let overlap = overlappingBookingForSlot(slotStart: slot, slotMinutes: slotMinutes, bookings: bookings) {
                                         Text(overlap.clientName ?? overlap.clientID)
                                             .font(.caption2)
                                             .foregroundColor(.secondary)
                                             .lineLimit(1)
                                     } else {
                                         Text("Available")
                                             .font(.caption2)
                                             .foregroundColor(.secondary)
                                     }
                                 }
                                 .padding(8)
                                 .frame(maxWidth: .infinity, alignment: .leading)
                                 .background(booked ? Color.gray.opacity(0.25) : Color.accentColor.opacity(0.12))
                                 .cornerRadius(8)
                             }
                             .buttonStyle(PlainButtonStyle())
                         }
                     }
                     .padding(.vertical, 4)
                 }
                 .frame(minHeight: 120, maxHeight: 420)
             }
         }
         .onAppear(perform: loadBookings)
         .onChange(of: date) { _ in loadBookings() }
         .sheet(isPresented: $showingNewBookingSheet) {
             // Present the NewBookingForm prefilled with coach and times if available
             NewBookingForm(showSheet: $showingNewBookingSheet, initialCoachId: coachID, initialStartAt: prefillStart, initialEndAt: prefillEnd, initialLocationId: nil)
                 .environmentObject(firestore)
                 .environmentObject(AuthViewModel())
         }
     }

     private func loadBookings() {
         loading = true
         firestore.fetchBookingsForCoach(coachId: coachID, start: Calendar.current.startOfDay(for: date), end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))!) { items in
             DispatchQueue.main.async {
                 self.bookings = items.sorted { (a,b) in
                     (a.startAt ?? Date.distantFuture) < (b.startAt ?? Date.distantFuture)
                 }
                 self.loading = false
             }
         }
     }

     private func generateTimeSlots(for date: Date, startHour: Int, endHour: Int, intervalMinutes: Int) -> [Date] {
         var result: [Date] = []
         let calendar = Calendar.current
         var components = calendar.dateComponents([.year, .month, .day], from: date)
         components.hour = startHour
         components.minute = 0

         guard let startDate = calendar.date(from: components) else { return [] }
         var current = startDate
         while true {
             let hour = calendar.component(.hour, from: current)
             if hour >= endHour { break }
             result.append(current)
             if let next = calendar.date(byAdding: .minute, value: intervalMinutes, to: current) {
                 current = next
             } else { break }
         }
         return result
     }

     private func isSlotBooked(slotStart: Date, slotMinutes: Int, bookings: [FirestoreManager.BookingItem]) -> Bool {
         let slotEnd = Calendar.current.date(byAdding: .minute, value: slotMinutes, to: slotStart) ?? slotStart
         for b in bookings {
             if let s = b.startAt, let e = b.endAt {
                 if s < slotEnd && e > slotStart {
                     return true
                 }
             }
         }
         return false
     }

     private func overlappingBookingForSlot(slotStart: Date, slotMinutes: Int, bookings: [FirestoreManager.BookingItem]) -> FirestoreManager.BookingItem? {
         let slotEnd = Calendar.current.date(byAdding: .minute, value: slotMinutes, to: slotStart) ?? slotStart
         for b in bookings {
             if let s = b.startAt, let e = b.endAt {
                 if s < slotEnd && e > slotStart {
                     return b
                 }
             }
         }
         return nil
     }

     private func shortTimeString(from date: Date) -> String {
         let f = DateFormatter()
         f.timeStyle = .short
         f.dateStyle = .none
         return f.string(from: date)
     }
 }
