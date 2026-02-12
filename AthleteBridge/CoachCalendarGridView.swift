import SwiftUI
import FirebaseAuth

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
            if coach.specialties.contains(where: { $0.lowercased().contains(typed) }) { return true }
            return false
        }
    }

     init(client: Client, searchQuery: String? = nil) {
         self.client = client
         self.searchQuery = searchQuery
     }

     private func filteredCoaches() -> [Coach] {
         var candidates = firestore.coaches

        // Filter by availability preferences
        let availPrefs = client.preferredAvailability.compactMap { pref -> String? in
            let trimmed = pref.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.isEmpty ? nil : trimmed
        }
        if !availPrefs.isEmpty {
           candidates = candidates.filter { coach in
               coach.availability.contains { avail in
                   let lower = avail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                   return availPrefs.contains { pref in lower.contains(pref) }
               }
           }
        }

        // Filter by client's desired improvement areas (goals) - match against coach specialties
        let goalPrefs = client.goals.compactMap { goal -> String? in
            let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.isEmpty ? nil : trimmed
        }
        if !goalPrefs.isEmpty {
            candidates = candidates.filter { coach in
                let coachSpecs = coach.specialties.map { $0.lowercased() }
                // Coach must have at least one specialty matching a client goal
                return goalPrefs.contains { goal in
                    coachSpecs.contains { spec in spec.contains(goal) || goal.contains(spec) }
                }
            }
        }

        // Filter by search query (coach name or specialties)
        let rawQuery = (searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? searchQuery : (localSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : localSearchText)
        guard let q = rawQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else { return candidates }

        let queryLower = q.lowercased()

        return candidates.filter { coach in
            let nameLower = coach.name.lowercased()
            // Match full search phrase against coach name
            if nameLower.contains(queryLower) { return true }
            // Also check if query matches any specialty
            let combinedSpecs = coach.specialties.joined(separator: " ").lowercased()
            if combinedSpecs.contains(queryLower) { return true }
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

                     if items.isEmpty {
                         noMatchesView
                     } else {
                         List(items) { coach in
                             coachRow(for: coach)
                                 .onAppear {
                                     lazyLoadForCoach(coach)
                                 }
                         }
                     }
                 }
             } else {
                 if items.isEmpty {
                     noMatchesView
                 } else {
                     List(items) { coach in
                         coachRow(for: coach)
                             .onAppear { lazyLoadForCoach(coach) }
                     }
                 }
             }
         }
         .navigationTitle("Your Matches")
         .navigationBarTitleDisplayMode(.inline)
         .onAppear { firestore.fetchCoaches() }
         // Modal fallback when programmatic NavigationLink doesn't trigger inside List rows
         .sheet(item: $presentedChat) { sheet in
             ChatView(chatId: sheet.id)
                 .environmentObject(firestore)
         }
     }

    // Empty state view when no coaches match the filters
    private var noMatchesView: some View {
        VStack(spacing: 20) {
            Spacer()
            if let logo = appLogoImageSwiftUI() {
                logo
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .opacity(0.6)
            } else {
                Image("AthleteBridgeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .opacity(0.6)
            }
            Text("No Matches Found")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Refine your filters to find coaches")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // Small helper to render a coach row
    // Modal fallback when programmatic navigation doesn't trigger; small Identifiable wrapper
    struct ChatSheetId: Identifiable { let id: String }
    @State private var presentedChat: ChatSheetId? = nil

    @ViewBuilder
    private func coachRow(for coach: Coach) -> some View {
        // Build the left tappable area (navigates to CoachDetail) and keep the Message button as a separate sibling
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Left area: navigation link to coach detail
                NavigationLink(destination: CoachDetailView(coach: coach).environmentObject(firestore)) {
                    HStack(alignment: .top, spacing: 12) {
                        let coachURL = firestore.coachPhotoURLs[coach.id] ?? nil
                        AvatarView(url: coachURL ?? nil, size: 56, useCurrentUser: false)

                        VStack(alignment: .leading) {
                            HStack(spacing: 4) {
                                Text(coach.name).font(.headline)
                                if coach.phoneVerified { VerifiedBadge() }
                            }
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
                    }
                }

                Spacer()

                // Right area: reviews and Message button (outside the NavigationLink so taps register)
                if let reviews = coachReviews[coach.id], !reviews.isEmpty {
                    let avg = averageRating(from: reviews)
                    VStack {
                        Text(String(format: "%.1f", avg)).font(.headline)
                        Text("(\(reviews.count))").font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    Text("No reviews").font(.caption).foregroundColor(.secondary)
                }

                // Message button: compute deterministic chatId for this pair and present ChatView modally
                let expectedChatId = ([Auth.auth().currentUser?.uid ?? "", coach.id].sorted().joined(separator: "_"))

                Button(action: {
                    print("[MatchResultsView] Message button tapped for coach.id=\(coach.id)")
                    guard Auth.auth().currentUser?.uid != nil else {
                        firestore.showToast("Please sign in to message coaches")
                        return
                    }
                    // Optimistically present the chat UI immediately using deterministic id
                    let optimisticId = expectedChatId
                    print("[MatchResultsView] presenting chat sheet for optimisticId=\(optimisticId)")
                    self.presentedChat = ChatSheetId(id: optimisticId)

                    // Ensure chat doc exists on server in the background; if server returns a different id, update the sheet
                    firestore.createOrGetChat(withCoachId: coach.id) { chatId in
                        DispatchQueue.main.async {
                            let target = chatId ?? optimisticId
                            print("[MatchResultsView] createOrGetChat returned chatId=\(chatId ?? "nil"), ensuring sheet id=\(target)")
                            if target != optimisticId {
                                self.presentedChat = ChatSheetId(id: target)
                            }
                        }
                    }
                }) {
                    Image(systemName: "message.fill")
                        .font(.title2)
                        .padding(12)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }

            HStack {
                Text("Bookings:").font(.caption).foregroundColor(.secondary)
                if let count = coachBookingCounts[coach.id] { Text("\(count)").font(.caption).bold() }
                else { Text("—").font(.caption).foregroundColor(.secondary) }
                Spacer()
            }
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

 // Keep a single CoachDetailView definition with embedded calendar + confirm overlay
 struct CoachDetailView: View {
    let coach: Coach
    @EnvironmentObject var firestore: FirestoreManager
    @State private var reviews: [FirestoreManager.ReviewItem] = []
    @State private var bookings: [FirestoreManager.BookingItem] = []
    @State private var loadingBookings: Bool = true
    @State private var selectedDate: Date = Date()
    @State private var selectedSlotStart: Date? = nil
    @State private var selectedSlotEnd: Date? = nil
    @State private var startAt: Date = Date()
    @State private var endAt: Date = Date().addingTimeInterval(60*60)
    @State private var showConfirmOverlay: Bool = false
    @State private var gridRefreshToken: UUID = UUID()
    @State private var showOverlapAlert: Bool = false
    @State private var showMinDurationAlert: Bool = false

    // For presenting chat sheet
    private struct ChatSheetId: Identifiable { let id: String }
    @State private var presentedChat: ChatSheetId? = nil

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    let coachURL = firestore.coachPhotoURLs[coach.id] ?? nil
                    AvatarView(url: coachURL ?? nil, size: 88, useCurrentUser: false)
                    VStack(alignment: .leading, spacing: 8) {
                        if let bio = coach.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(bio).font(.body).foregroundColor(.primary)
                        } else {
                            Text("No bio provided").font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                if !coach.specialties.isEmpty { Text("Specialties: \(coach.specialties.joined(separator: ", "))") }
                Text("Experience: \(coach.experienceYears) years")
                if let range = coach.rateRange, range.count >= 2 {
                    Text(String(format: "$%.0f - $%.0f / hr", range[0], range[1]))
                } else {
                    Text("Message coach for rate").foregroundColor(.secondary)
                }
                if !coach.availability.isEmpty {
                    Text("Availability: \(coach.availability.joined(separator: ", "))")
                        .listRowSeparator(.hidden, edges: .bottom)
                }

                // Message Coach button
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, -16)
                    Button(action: {
                        guard Auth.auth().currentUser?.uid != nil else {
                            firestore.showToast("Please sign in to message coaches")
                            return
                        }
                        // Compute deterministic chat ID and present chat view
                        let expectedChatId = [Auth.auth().currentUser?.uid ?? "", coach.id].sorted().joined(separator: "_")
                        presentedChat = ChatSheetId(id: expectedChatId)
                        // Ensure chat doc exists on server in the background
                        firestore.createOrGetChat(withCoachId: coach.id) { chatId in
                            DispatchQueue.main.async {
                                let target = chatId ?? expectedChatId
                                if target != expectedChatId {
                                    presentedChat = ChatSheetId(id: target)
                                }
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "message.fill")
                            Text("Message Coach")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("LogoGreen"))
                    .padding(.vertical, 12)
                    Divider()
                        .padding(.horizontal, -16)
                }
                .listRowSeparator(.hidden)

                // Reviews summary section
                VStack(alignment: .leading, spacing: 8) {
                    let avgRating = reviews.isEmpty ? 0.0 : reviews.compactMap { r -> Double? in
                        if let s = r.rating, let d = Double(s) { return d }
                        return nil
                    }.reduce(0, +) / Double(reviews.count)

                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: Double(i) <= avgRating ? "star.fill" : (Double(i) - 0.5 <= avgRating ? "star.leadinghalf.filled" : "star"))
                                    .foregroundColor(.yellow)
                                    .font(.subheadline)
                            }
                        }

                        Text(String(format: "%.1f", avgRating))
                            .font(.headline)

                        Text("(\(reviews.count) reviews)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    NavigationLink(destination: CoachReviewsListView(coach: coach, reviews: reviews)) {
                        Text("View All Reviews")
                            .font(.subheadline)
                    }
                }
                .padding(.top, 8)
            } header: {
                HStack(spacing: 4) {
                    Text(coach.name).font(.title2)
                    if coach.phoneVerified { VerifiedBadge().font(.body) }
                }
            }

            Section {
                HStack {
                    Button(action: { selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate }) { Image(systemName: "chevron.left").font(.headline) }
                        .buttonStyle(.plain)
                    Spacer()
                    Text(DateFormatter.localizedString(from: selectedDate, dateStyle: .medium, timeStyle: .none)).font(.subheadline).bold()
                    Spacer()
                    Button(action: { selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate }) { Image(systemName: "chevron.right").font(.headline) }
                        .buttonStyle(.plain)
                }
                .padding(.vertical, 6)

                CoachCalendarGridView(coachID: coach.id, date: $selectedDate, showOnlyAvailable: false, onSlotSelected: nil, embedMode: true, onAvailableSlot: { start, end in
                    selectedSlotStart = start
                    // Enforce minimum 1-hour booking from selected slot
                    let minEnd = start.addingTimeInterval(3600)
                    selectedSlotEnd = max(end, minEnd)
                    startAt = start
                    endAt = max(end, minEnd)
                    showConfirmOverlay = true
                })
                .id(gridRefreshToken)
                .environmentObject(firestore)
            } header: { Text("Calendar") }
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            firestore.fetchReviewsForCoach(coachId: coach.id) { items in
                DispatchQueue.main.async { self.reviews = items }
            }
            loadingBookings = true
            let cal = Calendar.current
            let dayStart = cal.startOfDay(for: selectedDate)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            firestore.fetchBookingsForCoach(coachId: coach.id, start: dayStart, end: dayEnd) { items in
                DispatchQueue.main.async {
                    self.bookings = items.sorted { (a,b) in (a.startAt ?? Date.distantFuture) < (b.startAt ?? Date.distantFuture) }
                    self.loadingBookings = false
                }
            }
        }
        .onChange(of: selectedDate) { old, new in
            let cal = Calendar.current
            let dayStart = cal.startOfDay(for: new)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            self.loadingBookings = true
            firestore.fetchBookingsForCoach(coachId: coach.id, start: dayStart, end: dayEnd) { items in
                DispatchQueue.main.async {
                    self.bookings = items.sorted { (a,b) in (a.startAt ?? Date.distantFuture) < (b.startAt ?? Date.distantFuture) }
                    self.loadingBookings = false
                }
            }
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
                                Text("Confirm Date & Time").font(.headline)
                                Text("Coach: \(coach.name)").font(.subheadline).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            Divider()
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Start")
                                MinuteIntervalDatePicker(date: $startAt, minuteInterval: 30)
                                    .frame(height: 150)
                                    .padding(.bottom, 8)
                                Text("End")
                                MinuteIntervalDatePicker(date: $endAt, minuteInterval: 30)
                                    .frame(height: 150)
                            }
                            .padding([.horizontal, .bottom])
                            Divider()
                            HStack(spacing: 12) {
                                Button(role: .cancel) { withAnimation(.easeInOut) { showConfirmOverlay = false } } label: { Text("Cancel").frame(maxWidth: .infinity) }
                                .buttonStyle(.bordered)
                                Button {
                                    guard let uid = Auth.auth().currentUser?.uid else { return }
                                    // Enforce minimum 1-hour booking
                                    if endAt.timeIntervalSince(startAt) < 3600 {
                                        showMinDurationAlert = true
                                        return
                                    }
                                    // Check for overlapping bookings — fetch full day to catch all overlaps
                                    let dayStart = Calendar.current.startOfDay(for: startAt)
                                    let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? startAt
                                    firestore.fetchBookingsForCoach(coachId: coach.id, start: dayStart, end: dayEnd) { existingBookings in
                                        DispatchQueue.main.async {
                                            let overlapping = existingBookings.filter { b in
                                                guard let bStart = b.startAt, let bEnd = b.endAt else { return false }
                                                let status = (b.status ?? "").lowercased()
                                                guard status == "requested" || status == "confirmed" || status == "pending acceptance" else { return false }
                                                return bStart < endAt && bEnd > startAt
                                            }
                                            if !overlapping.isEmpty {
                                                showOverlapAlert = true
                                                return
                                            }
                                            // No overlap — proceed with save
                                            firestore.saveBooking(clientUid: uid, coachUid: coach.id, startAt: startAt, endAt: endAt, location: nil, notes: nil, status: "requested") { err in
                                                DispatchQueue.main.async {
                                                    if let err = err {
                                                        firestore.showToast("Failed: \(err.localizedDescription)")
                                                    } else {
                                                        firestore.fetchBookingsForCurrentClientSubcollection()
                                                        gridRefreshToken = UUID()
                                                        firestore.showToast("Booking saved")
                                                        withAnimation { showConfirmOverlay = false }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } label: { Text("Confirm Booking Time").frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent)
                                .disabled(!(startAt < endAt) || endAt.timeIntervalSince(startAt) < 3600)
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
        .sheet(item: $presentedChat) { sheet in
            ChatView(chatId: sheet.id)
                .environmentObject(firestore)
        }
        .alert("Time Unavailable", isPresented: $showOverlapAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This time is already requested by you or someone else. Please choose a different time.")
        }
        .alert("Minimum Duration", isPresented: $showMinDurationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Minimum booking length is 1 hour. Please select a longer time range.")
        }
    }
 }

 struct CoachCalendarGridView: View {
     let coachID: String
     // NEW: Support multiple coach IDs for group booking availability merge
     var coachIDs: [String]? = nil
     @Binding var date: Date
     var showOnlyAvailable: Bool = false
     var onSlotSelected: ((FirestoreManager.BookingItem) -> Void)?
    // New: embedded mode disables internal sheet and uses a callback for available slot selection
    var embedMode: Bool = false
    var onAvailableSlot: ((Date, Date) -> Void)?

     @EnvironmentObject var firestore: FirestoreManager
     @EnvironmentObject var auth: AuthViewModel
     @State private var bookings: [FirestoreManager.BookingItem] = []
     // NEW: Store bookings per coach for merged availability display
     @State private var allCoachBookings: [String: [FirestoreManager.BookingItem]] = [:]
     @State private var allCoachAwayTimes: [String: [FirestoreManager.AwayTimeItem]] = [:]
     @State private var loading: Bool = true
     @State private var showBookingSheet: Bool = false
     @State private var selectedSlotStart: Date = Date()
     @State private var selectedSlotEnd: Date = Date().addingTimeInterval(60*60)
     @State private var awayTimes: [FirestoreManager.AwayTimeItem] = []

     // Computed property for effective coach IDs (supports both single and multiple)
     private var effectiveCoachIDs: [String] {
         if let ids = coachIDs, !ids.isEmpty {
             return ids
         }
         return coachID.isEmpty ? [] : [coachID]
     }

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

     // Helper: check booking overlap for a slot (checks ALL coaches for group bookings)
     // Excludes cancelled bookings so those time slots show as available
     private func bookingOverlapping(slotStart: Date, slotEnd: Date) -> FirestoreManager.BookingItem? {
         // For multiple coaches, check all their bookings
         if effectiveCoachIDs.count > 1 {
             for coachId in effectiveCoachIDs {
                 if let coachBookings = allCoachBookings[coachId] {
                     if let overlapping = coachBookings.first(where: { b in
                         guard let s = b.startAt, let e = b.endAt else { return false }
                         // Skip cancelled/declined bookings - those time slots are available
                         let st = (b.status ?? "").lowercased()
                         if st == "cancelled" || st == "declined" || st == "declined_by_client" || st == "rejected" { return false }
                         return (s < slotEnd) && (e > slotStart)
                     }) {
                         return overlapping
                     }
                 }
             }
             return nil
         }
         // Single coach - use existing bookings array
         return bookings.first { b in
             guard let s = b.startAt, let e = b.endAt else { return false }
             // Skip cancelled/declined bookings - those time slots are available
             let st = (b.status ?? "").lowercased()
             if st == "cancelled" || st == "declined" || st == "declined_by_client" || st == "rejected" { return false }
             return (s < slotEnd) && (e > slotStart)
         }
     }

     // Helper: check away overlap for a slot (checks ALL coaches for group bookings)
     private func awayOverlapping(slotStart: Date, slotEnd: Date) -> FirestoreManager.AwayTimeItem? {
         // For multiple coaches, check all their away times
         if effectiveCoachIDs.count > 1 {
             for coachId in effectiveCoachIDs {
                 if let coachAwayTimes = allCoachAwayTimes[coachId] {
                     if let overlapping = coachAwayTimes.first(where: { a in
                         return (a.startAt < slotEnd) && (a.endAt > slotStart)
                     }) {
                         return overlapping
                     }
                 }
             }
             return nil
         }
         // Single coach - use existing awayTimes array
         return awayTimes.first { a in
             return (a.startAt < slotEnd) && (a.endAt > slotStart)
         }
     }

     // Helper: get coach name for a booking (for display in merged view)
     private func coachNameForBooking(_ booking: FirestoreManager.BookingItem) -> String? {
         if effectiveCoachIDs.count > 1 {
             return booking.coachName
         }
         return nil
     }

    // Helper to render a single slot row; breaking this out improves compiler type-check time
    @ViewBuilder
    private func slotRowView(slot: Slot,
                             overlappingBooking: FirestoreManager.BookingItem?,
                             overlappingAway: FirestoreManager.AwayTimeItem?,
                             isBlocked: Bool) -> some View {
        HStack(spacing: 12) {
            Text(slot.label)
                .font(.caption2)
                .frame(width: 60, alignment: .leading)
                .foregroundColor(.secondary)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isBlocked ? Color.red.opacity(0.85) : Color.green.opacity(0.12))
                    .frame(height: 44)

                HStack {
                    if isBlocked {
                        if let b = overlappingBooking {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(timeRangeString(for: b))
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                // Show coach name when multiple coaches selected
                                if effectiveCoachIDs.count > 1, let coachName = b.coachName {
                                    Text(coachName)
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .padding(.leading, 10)
                            Spacer()
                            if let status = b.status {
                                Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.trailing, 10)
                            }
                        } else if let away = overlappingAway {
                            VStack(alignment: .leading, spacing: 2) {
                                // Display the reason from the away time
                                Text(away.notes ?? "Away")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                // Show which coach is away when multiple coaches selected
                                if effectiveCoachIDs.count > 1 {
                                    if let coachId = away.coachId,
                                       let coach = firestore.coaches.first(where: { $0.id == coachId }) {
                                        Text(coach.name)
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                            }
                            .padding(.leading, 10)
                            Spacer()
                        }
                    } else {
                        if effectiveCoachIDs.count > 1 {
                            Text("All Coaches Available")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .padding(.leading, 10)
                        } else {
                            Text("Available")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .padding(.leading, 10)
                        }
                        Spacer()
                    }
                }
            }
            .onTapGesture {
                if let b = overlappingBooking {
                    onSlotSelected?(b)
                } else if overlappingAway != nil {
                    // do nothing on away blocks
                } else {
                    selectedSlotStart = slot.start
                    // Enforce minimum 1-hour end time from slot start
                    let minEnd = slot.start.addingTimeInterval(3600)
                    selectedSlotEnd = max(slot.end, minEnd)
                    if embedMode {
                        onAvailableSlot?(slot.start, max(slot.end, minEnd))
                    } else {
                        showBookingSheet = true
                    }
                }
            }
        }
        .padding(.horizontal, 6)
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
                             let overlappingBooking = bookingOverlapping(slotStart: slot.start, slotEnd: slot.end)
                             let overlappingAway = awayOverlapping(slotStart: slot.start, slotEnd: slot.end)
                             let isBlocked = (overlappingBooking != nil) || (overlappingAway != nil)

                             slotRowView(slot: slot,
                                        overlappingBooking: overlappingBooking,
                                        overlappingAway: overlappingAway,
                                        isBlocked: isBlocked)
                         }
                     }
                     .padding(.vertical, 6)
                 }
             }
         }
         .onAppear { fetchForSelectedDate() }
         .onChange(of: date) { _old, _new in fetchForSelectedDate() }
         // Present booking form only when not embedded
         .sheet(isPresented: $showBookingSheet) {
             if !embedMode {
                 BookingEditorView(showSheet: $showBookingSheet, initialCoachId: coachID, initialStart: selectedSlotStart, initialEnd: selectedSlotEnd)
                     .id(selectedSlotStart)
                     .environmentObject(firestore)
                     .environmentObject(auth)
             }
         }
         .onChange(of: showBookingSheet) { _old, newVal in if newVal == false { fetchForSelectedDate() } }
     }

     private func fetchForSelectedDate() {
         loading = true
         let cal = Calendar.current
         let dayStart = cal.startOfDay(for: date)
         let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

         // For multiple coaches, fetch all their bookings and away times
         if effectiveCoachIDs.count > 1 {
             let group = DispatchGroup()
             var newAllCoachBookings: [String: [FirestoreManager.BookingItem]] = [:]
             var newAllCoachAwayTimes: [String: [FirestoreManager.AwayTimeItem]] = [:]
             let lock = NSLock()

             for coachId in effectiveCoachIDs {
                 group.enter()
                 firestore.fetchBookingsForCoach(coachId: coachId, start: dayStart, end: dayEnd) { items in
                     lock.lock()
                     newAllCoachBookings[coachId] = items.sorted { (a,b) in
                         (a.startAt ?? Date.distantFuture) < (b.startAt ?? Date.distantFuture)
                     }
                     lock.unlock()
                     group.leave()
                 }

                 group.enter()
                 firestore.fetchAwayTimesForCoach(coachId: coachId, start: dayStart, end: dayEnd) { items in
                     lock.lock()
                     newAllCoachAwayTimes[coachId] = items
                     lock.unlock()
                     group.leave()
                 }
             }

             group.notify(queue: .main) {
                 self.allCoachBookings = newAllCoachBookings
                 self.allCoachAwayTimes = newAllCoachAwayTimes
                 self.loading = false
             }
         } else {
             // Single coach - use existing logic
             firestore.fetchBookingsForCoach(coachId: coachID, start: dayStart, end: dayEnd) { items in
                 DispatchQueue.main.async {
                     self.bookings = items.sorted { (a,b) in
                         (a.startAt ?? Date.distantFuture) < (b.startAt ?? Date.distantFuture)
                     }
                 }
             }
             firestore.fetchAwayTimesForCoach(coachId: coachID, start: dayStart, end: dayEnd) { items in
                 DispatchQueue.main.async {
                     self.awayTimes = items
                     self.loading = false
                 }
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

// View to display all reviews for a specific coach
struct CoachReviewsListView: View {
    let coach: Coach
    let reviews: [FirestoreManager.ReviewItem]

    var body: some View {
        List {
            if reviews.isEmpty {
                Text("No reviews yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(reviews) { review in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(review.clientName ?? "Client")
                                .font(.headline)
                            Spacer()
                            if let date = review.createdAt {
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Star rating
                        HStack(spacing: 4) {
                            let stars = Int(review.rating ?? "0") ?? 0
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: i <= stars ? "star.fill" : "star")
                                    .foregroundColor(i <= stars ? .yellow : .secondary)
                            }
                        }

                        // Review message
                        if let message = review.ratingMessage, !message.isEmpty {
                            Text(message)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("\(coach.name)'s Reviews")
        .navigationBarTitleDisplayMode(.inline)
    }
}
