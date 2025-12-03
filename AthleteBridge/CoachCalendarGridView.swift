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
    
    // Local search text for inline Find a Coach search bar (used when searchQuery is nil)
    @State private var localSearchText: String = ""

    // Inline suggestions for the Find-a-Coach search (contains match)
    private var coachSuggestionsLocal: [Coach] {
        let typed = localSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard typed.count >= 1 else { return [] }
        return firestore.coaches.filter { coach in
            if coach.name.lowercased().contains(typed) { return true }
            let specs = coach.specialties.map { $0.lowercased() }
            if specs.contains(where: { $0.contains(typed) }) { return true }
            return false
        }
    }

     init(client: Client, searchQuery: String? = nil) {
         self.client = client
         self.searchQuery = searchQuery
     }

     private func filteredCoaches() -> [Coach] {
         let all = firestore.coaches
         // If the caller provided a searchQuery, prefer that. Otherwise use localSearchText.
         let rawQuery = (searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? searchQuery : (localSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : localSearchText)
         guard let q = rawQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else { return all }

         // Tokenize query by commas and whitespace so multi-term searches work: "tennis, confidence" or "tennis confidence"
         let separators = CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines)
         let tokens = q.lowercased().split { separators.contains($0.unicodeScalars.first!) }.map { String($0) }.filter { !$0.isEmpty }

         return all.filter { coach in
             let nameLower = coach.name.lowercased()
             // Match if any token appears in the coach name
             if tokens.contains(where: { nameLower.contains($0) }) { return true }

             // Match if any token appears in any specialty
             let specialtiesLower = coach.specialties.map { $0.lowercased() }
             if tokens.contains(where: { token in specialtiesLower.contains(where: { $0.contains(token) }) }) {
                 return true
             }

             // Also match against combined specialties string (helps multi-word specialties)
             let combinedSpecs = specialtiesLower.joined(separator: " ")
             if tokens.contains(where: { combinedSpecs.contains($0) }) { return true }

             return false
         }
     }

     var body: some View {
         let items = filteredCoaches()

         // If an external searchQuery was provided, show just the list filtered by it.
         // Otherwise show a local SearchBar above the list.
         Group {
             if searchQuery == nil {
                 VStack(spacing: 0) {
                     SearchBar(text: $localSearchText, placeholder: "Search coach by name")
                         .padding([.horizontal, .top])

                     // Suggestion chips (match Reviews UI)
                     if !coachSuggestionsLocal.isEmpty {
                         ScrollView(.horizontal, showsIndicators: false) {
                             HStack(spacing: 8) {
                                 ForEach(coachSuggestionsLocal.prefix(8), id: \.id) { coach in
                                     Button(action: {
                                         localSearchText = coach.name
                                         // dismiss keyboard
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
                             .padding(.horizontal)
                         }
                     }

                     List(items) { coach in
                         coachRow(for: coach)
                             .onAppear {
                                 lazyLoadForCoach(coach)
                             }
                     }
                 }
             } else {
                 List(items) { coach in
                     coachRow(for: coach)
                         .onAppear { lazyLoadForCoach(coach) }
                 }
             }
         }
         .navigationTitle("Your Matches")
         .onAppear { firestore.fetchCoaches() }
     }

    // Small helper to render a coach row
    @ViewBuilder
    private func coachRow(for coach: Coach) -> some View {
        NavigationLink(destination: CoachDetailView(coach: coach).environmentObject(firestore)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(coach.name).font(.headline)
                        if !coach.specialties.isEmpty {
                            Text(coach.specialties.joined(separator: ", ")).font(.subheadline).foregroundColor(.secondary)
                        }
                        Text("Experience: \(coach.experienceYears) years").font(.caption).foregroundColor(.secondary)
                        if let rate = coach.hourlyRate {
                            Text(String(format: "$%.0f / hr", rate)).font(.caption).foregroundColor(.primary)
                        } else {
                            Text("Hourly rate to be discussed").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if let reviews = coachReviews[coach.id], !reviews.isEmpty {
                        let avg = averageRating(from: reviews)
                        VStack {
                            Text(String(format: "%.1f", avg)).font(.headline)
                            Text("(\(reviews.count))").font(.caption).foregroundColor(.secondary)
                        }
                    } else {
                        Text("No reviews").font(.caption).foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Bookings:").font(.caption).foregroundColor(.secondary)
                    if let count = coachBookingCounts[coach.id] { Text("\(count)").font(.caption).bold() }
                    else { Text("—").font(.caption).foregroundColor(.secondary) }
                    Spacer()
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func lazyLoadForCoach(_ coach: Coach) {
        if coachReviews[coach.id] == nil {
            firestore.fetchReviewsForCoach(coachId: coach.id) { items in
                DispatchQueue.main.async { coachReviews[coach.id] = items }
            }
        }
        if coachBookingCounts[coach.id] == nil {
            firestore.fetchBookingsForCoach(coachId: coach.id) { items in
                DispatchQueue.main.async { coachBookingCounts[coach.id] = items.count }
            }
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

    // Added helper duplicate to use inside coachRow scope
    private func averageRatingFor(_ reviews: [FirestoreManager.ReviewItem]) -> Double {
        return averageRating(from: reviews)
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
                                     .foregroundColor(.secondary)
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
     @Binding var date: Date
     var showOnlyAvailable: Bool = false
     var onSlotSelected: ((FirestoreManager.BookingItem) -> Void)?

     @EnvironmentObject var firestore: FirestoreManager
     @EnvironmentObject var auth: AuthViewModel
     @State private var bookings: [FirestoreManager.BookingItem] = []
     @State private var loading: Bool = true
     // Sheet state for creating a new booking when tapping an available slot
     @State private var showBookingSheet: Bool = false
     @State private var selectedSlotStart: Date = Date()
     @State private var selectedSlotEnd: Date = Date().addingTimeInterval(60*30)

     // Configuration: generate slots between these hours
     private let startHour = 6
     private let endHour = 22
     private let slotMinutes = 30

     // Strongly-typed slot model to help the compiler
     private struct Slot: Identifiable {
         let id: UUID = UUID()
         let start: Date
         let end: Date
         let label: String
     }

     var body: some View {
         ScrollView {
             VStack(alignment: .leading, spacing: 8) {
                 if loading {
                     HStack { Spacer(); ProgressView(); Spacer() }
                         .padding(.vertical, 8)
                 } else {
                     let slots = generateSlots(for: date)
                     LazyVStack(spacing: 6) {
                         ForEach(slots) { slot in
                             // find any booking that overlaps this slot
                             let overlapping = bookings.first { b in
                                 guard let bStart = b.startAt, let bEnd = b.endAt else { return false }
                                 return (bStart < slot.end) && (bEnd > slot.start)
                             }

                             HStack(spacing: 12) {
                                 Text(slot.label)
                                     .font(.caption2)
                                     .frame(width: 60, alignment: .leading)
                                     .foregroundColor(.secondary)

                                 ZStack(alignment: .leading) {
                                     RoundedRectangle(cornerRadius: 8)
                                         .fill(overlapping != nil ? Color.red.opacity(0.85) : Color.green.opacity(0.12))
                                         .frame(height: 44)

                                     HStack {
                                         if let b = overlapping {
                                             // Only display booking time range and status (no client name)
                                             Text(timeRangeString(for: b))
                                                 .font(.subheadline)
                                                 .foregroundColor(.white)
                                                 .padding(.leading, 10)
                                             Spacer()
                                             if let status = b.status {
                                                 Text(status.capitalized)
                                                     .font(.caption2)
                                                     .foregroundColor(.white.opacity(0.9))
                                                     .padding(.trailing, 10)
                                             }
                                         } else {
                                             Text("Available")
                                                 .font(.subheadline)
                                                 .foregroundColor(.primary)
                                                 .padding(.leading, 10)
                                             Spacer()
                                         }
                                     }
                                 }
                                 .onTapGesture {
                                     if let b = overlapping {
                                         onSlotSelected?(b)
                                     } else {
                                         // available slot tapped — present booking form prefilled
                                         selectedSlotStart = slot.start
                                         selectedSlotEnd = slot.end
                                         // present sheet with NewBookingFormView
                                         showBookingSheet = true
                                     }
                                 }
                             }
                             .padding(.horizontal, 6)
                         }
                     }
                     .padding(.vertical, 6)
                 }
             }
         }
         .onAppear { fetchForSelectedDate() }
         .onChange(of: date) { _ in fetchForSelectedDate() }
         // Present booking form when user taps available slot
         .sheet(isPresented: $showBookingSheet) {
             NewBookingFormView(showSheet: $showBookingSheet, initialCoachId: coachID, initialStart: selectedSlotStart, initialEnd: selectedSlotEnd)
                 .environmentObject(firestore)
                 .environmentObject(auth)
         }
         // When the booking sheet is dismissed, refresh bookings for the selected date
         .onChange(of: showBookingSheet) { newVal in
             if newVal == false {
                 fetchForSelectedDate()
             }
         }
     }

     private func fetchForSelectedDate() {
         loading = true
         let cal = Calendar.current
         let dayStart = cal.startOfDay(for: date)
         let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
         firestore.fetchBookingsForCoach(coachId: coachID, start: dayStart, end: dayEnd) { items in
             DispatchQueue.main.async {
                 self.bookings = items.sorted { (a,b) in
                     (a.startAt ?? Date.distantFuture) < (b.startAt ?? Date.distantFuture)
                 }
                 self.loading = false
             }
         }
     }

     private func generateSlots(for date: Date) -> [Slot] {
         var slots: [Slot] = []
         let cal = Calendar.current
         for hour in startHour..<endHour {
             for minute in stride(from: 0, to: 60, by: slotMinutes) {
                 var comps = cal.dateComponents([.year, .month, .day], from: date)
                 comps.hour = hour
                 comps.minute = minute
                 comps.second = 0
                 if let start = cal.date(from: comps) {
                     let end = cal.date(byAdding: .minute, value: slotMinutes, to: start) ?? start
                     let label = DateFormatter.localizedString(from: start, dateStyle: .none, timeStyle: .short)
                     slots.append(Slot(start: start, end: end, label: label))
                 }
             }
         }
         return slots
     }

     private func timeRangeString(for booking: FirestoreManager.BookingItem) -> String {
         if let s = booking.startAt, let e = booking.endAt {
             let sstr = DateFormatter.localizedString(from: s, dateStyle: .none, timeStyle: .short)
             let estr = DateFormatter.localizedString(from: e, dateStyle: .none, timeStyle: .short)
             return "\(sstr) - \(estr)"
         }
         return ""
     }

 }
