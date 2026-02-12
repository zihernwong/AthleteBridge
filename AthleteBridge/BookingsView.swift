import SwiftUI

struct BookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var deepLink: DeepLinkManager

    @State private var showingNewBooking = false
    @State private var selectedBookingForAccept: FirestoreManager.BookingItem? = nil
    @State private var selectedBookingForReview: FirestoreManager.BookingItem? = nil
    @State private var selectedBookingForRejection: FirestoreManager.BookingItem? = nil
    @State private var selectedBookingForDetail: FirestoreManager.BookingItem? = nil
    @State private var navigateToConfirmedBookings = false
    @State private var confirmedBookingsDeepLinkId: String? = nil
    @State private var pendingDeepLinkBookingId: String? = nil
    @State private var selectedDate = Date()
    @State private var currentMonthAnchor = Date() // month displayed by calendar

    private var currentUserRole: String? { firestore.currentUserType?.uppercased() }

    var body: some View {
        NavigationStack {
            // Replace List with ScrollView + VStack to avoid UICollectionView feedback loop on device
            ScrollView {
                VStack(spacing: 16) {
                    // Coach-specific header with Input Time Away and Locations links
                    if currentUserRole == "COACH" {
                        coachHeaderSection
                    }

                    // === Today's Bookings (for both roles) ===
                    todaysBookingsSection

                    // === Month Calendar === (below Today and above My/ Accepted Bookings)
                    monthCalendarSection

                    // Requested bookings section for coaches
                    if currentUserRole == "COACH" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bookings Awaiting Your Acceptance").font(.headline)
                            // Include bookings that need this coach's acceptance:
                            // - status "requested" (no one has accepted yet)
                            // - status "partially_accepted" AND this coach hasn't accepted yet
                            // - start time must be in the future
                            let currentCoachId = auth.user?.uid ?? ""
                            let now = Date()
                            let requested = firestore.coachBookings.filter { booking in
                                // Filter out bookings that have already started
                                guard let startAt = booking.startAt, startAt > now else { return false }

                                let status = (booking.status ?? "").lowercased()
                                if status == "requested" {
                                    return true
                                }
                                if status == "partially_accepted" {
                                    // Check if current coach has already accepted
                                    let acceptances = booking.coachAcceptances ?? [:]
                                    return acceptances[currentCoachId] != true
                                }
                                return false
                            }
                            if requested.isEmpty {
                                Text("No requested bookings").foregroundColor(.secondary)
                            } else {
                                ForEach(requested, id: \ .id) { b in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Button(action: { selectedBookingForDetail = b }) {
                                            BookingRowView(item: b)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .overlay(alignment: .trailing) {
                                            Button(action: { self.selectedBookingForAccept = b }) {
                                                Text("Accept")
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.blue)
                                            .padding(.top, -4) // nudge upward slightly
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Role-specific rendering
                    if currentUserRole == "CLIENT" {
                        clientPendingAcceptanceSection
                    } else if currentUserRole == "COACH" {
                        coachBookingsSection
                    } else {
                        // fallback: show both while role is unknown
                        clientPendingAcceptanceSection
                        coachBookingsSection
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Bookings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if currentUserRole == "CLIENT" {
                        Button(action: { showingNewBooking = true }) { Image(systemName: "plus") }
                    }
                }
            }
            .onAppear {
                // fetch both lists (safe) — we can optimize later to fetch only what's needed
                firestore.fetchBookingsForCurrentClientSubcollection()
                firestore.fetchBookingsForCurrentCoachSubcollection()
                firestore.fetchCoaches()

                // Handle deep link if pendingDestination was set before this view appeared
                if case .booking(let bookingId) = deepLink.pendingDestination {
                    print("[DeepLink-Bookings] onAppear: detected pending booking deep link: \(bookingId)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        handleBookingDeepLink(bookingId: bookingId)
                    }
                }
            }
            .sheet(isPresented: $showingNewBooking) {
                BookingEditorView(showSheet: $showingNewBooking)
                    .environmentObject(firestore)
                    .environmentObject(auth)
            }
            .navigationDestination(isPresented: $navigateToConfirmedBookings) {
                CoachConfirmedBookingsView(initialBookingId: confirmedBookingsDeepLinkId)
                    .environmentObject(firestore)
                    .environmentObject(auth)
            }
            .sheet(item: $selectedBookingForAccept) { booking in
                AcceptBookingView(booking: booking)
                    .environmentObject(firestore)
                    .environmentObject(auth)
            }
            .sheet(item: $selectedBookingForReview) { booking in
                ReviewBookingView(booking: booking)
                    .environmentObject(firestore)
                    .environmentObject(auth)
            }
            .sheet(item: $selectedBookingForRejection) { booking in
                RejectedBookingView(booking: booking)
                    .environmentObject(firestore)
            }
            .sheet(item: $selectedBookingForDetail) { booking in
                BookingDetailView(booking: booking)
                    .environmentObject(firestore)
                    .environmentObject(auth)
            }
            .onChange(of: deepLink.pendingDestination) { _old, destination in
                guard case .booking(let bookingId) = destination else { return }
                print("[DeepLink-Bookings] onChange: pendingDestination changed to booking: \(bookingId)")
                // Delay to let tab switch and view settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    handleBookingDeepLink(bookingId: bookingId)
                }
            }
            .onChange(of: firestore.bookings) { _, _ in
                if let bid = pendingDeepLinkBookingId {
                    print("[DeepLink-Bookings] onChange(bookings): retrying for pending ID \(bid), bookings count=\(firestore.bookings.count)")
                    handleBookingDeepLink(bookingId: bid)
                }
            }
            .onChange(of: firestore.coachBookings) { _, _ in
                if let bid = pendingDeepLinkBookingId {
                    print("[DeepLink-Bookings] onChange(coachBookings): retrying for pending ID \(bid), coachBookings count=\(firestore.coachBookings.count)")
                    handleBookingDeepLink(bookingId: bid)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NotificationManager.didReceiveForegroundNotification)) { _ in
                firestore.fetchBookingsForCurrentClientSubcollection()
                firestore.fetchBookingsForCurrentCoachSubcollection()
            }
        }
    }

    private func handleBookingDeepLink(bookingId: String) {
        print("[DeepLink-Bookings] handleBookingDeepLink called for: \(bookingId)")
        print("[DeepLink-Bookings]   bookings count: \(firestore.bookings.count), ids: \(firestore.bookings.map { $0.id })")
        print("[DeepLink-Bookings]   coachBookings count: \(firestore.coachBookings.count), ids: \(firestore.coachBookings.map { $0.id })")

        if let booking = firestore.bookings.first(where: { $0.id == bookingId }) {
            let notifType = deepLink.pendingBookingType
            let status = (booking.status ?? "").lowercased()
            pendingDeepLinkBookingId = nil
            deepLink.pendingDestination = nil
            deepLink.pendingBookingType = nil

            if notifType == "booking_rejected" || status == "rejected" || status == "declined" || status == "declined_by_client" {
                print("[DeepLink-Bookings]   FOUND in client bookings (rejected) → opening RejectedBookingView")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.selectedBookingForRejection = booking
                }
            } else if status == "confirmed" || status == "fully_confirmed" || status == "accepted" || status == "approved" {
                print("[DeepLink-Bookings]   FOUND in client bookings (confirmed) → opening BookingDetailView")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.selectedBookingForDetail = booking
                }
            } else {
                // Status is "pending acceptance" or "partially_confirmed" — client needs to review
                print("[DeepLink-Bookings]   FOUND in client bookings (pending) → opening ReviewBookingView")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.selectedBookingForReview = booking
                }
            }
        } else if let booking = firestore.coachBookings.first(where: { $0.id == bookingId }) {
            let notifType = deepLink.pendingBookingType
            let status = (booking.status ?? "").lowercased()
            pendingDeepLinkBookingId = nil
            deepLink.pendingDestination = nil
            deepLink.pendingBookingType = nil
            if notifType == "booking_confirmed" || status == "confirmed" || status == "fully_confirmed" {
                print("[DeepLink-Bookings]   FOUND in coach bookings (confirmed) → navigating to CoachConfirmedBookingsView with bookingId=\(bookingId)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.confirmedBookingsDeepLinkId = bookingId
                    self.navigateToConfirmedBookings = true
                }
            } else {
                print("[DeepLink-Bookings]   FOUND in coach bookings → opening AcceptBookingView")
                // Use asyncAfter to ensure SwiftUI state is settled before presenting sheet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.selectedBookingForAccept = booking
                }
            }
        } else {
            // Booking not found — store ID for retry and trigger a fresh fetch
            print("[DeepLink-Bookings]   NOT FOUND in either list — storing for retry and fetching fresh data")
            pendingDeepLinkBookingId = bookingId
            firestore.fetchBookingsForCurrentClientSubcollection()
            firestore.fetchBookingsForCurrentCoachSubcollection()
        }
    }

    // Helper: determine if two dates are the same day
    private func isSameDay(_ d1: Date, _ d2: Date) -> Bool {
        Calendar.current.isDate(d1, inSameDayAs: d2)
    }

    // Helper: all bookings combined relevant to current user
    private var allRelevantBookings: [FirestoreManager.BookingItem] {
        let role = currentUserRole
        if role == "CLIENT" { return firestore.bookings }
        if role == "COACH" { return firestore.coachBookings }
        // unknown role: combine
        return firestore.bookings + firestore.coachBookings
    }

    // === Coach Header Section with Input Time Away and Locations ===
    private var coachHeaderSection: some View {
        HStack(spacing: 16) {
            if let coach = firestore.currentCoach {
                NavigationLink(destination: AwayTimePickerView(coach: coach).environmentObject(firestore).environmentObject(auth)) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.minus")
                        Text("Input Time Away")
                    }
                    .font(.subheadline)
                }
            }
            NavigationLink(destination: LocationsView().environmentObject(firestore)) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                    Text("Locations")
                }
                .font(.subheadline)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    // === Today's Bookings Section ===
    private var todaysBookingsSection: some View {
        let today = Date()
        let todays = allRelevantBookings.filter { b in
            if let start = b.startAt { return isSameDay(start, today) }
            return false
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Today").font(.headline)
            if todays.isEmpty {
                Text("No bookings today").foregroundColor(.secondary)
            } else {
                ForEach(todays, id: \ .id) { b in
                    Button(action: { selectedBookingForDetail = b }) {
                        BookingRowView(item: b)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal)
    }

    // NOTE: Client-side confirmation happens inside `ReviewBookingView` via `updateBookingStatus(..., status: "confirmed")`.
    // We keep a tiny helper here in case we ever want a one-tap confirm action.
    private func confirmBooking(_ b: FirestoreManager.BookingItem) {
        firestore.updateBookingStatus(bookingId: b.id, status: "confirmed") { err in
            DispatchQueue.main.async {
                if let err = err {
                    print("confirmBooking error: \(err)")
                } else {
                    firestore.fetchBookingsForCurrentClientSubcollection()
                    firestore.showToast("Booking confirmed")
                }
            }
        }
    }

    private var clientPendingAcceptanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bookings Awaiting Your Confirmation").font(.headline)
            // Include bookings that need this client's confirmation:
            // - status "pending acceptance" (all coaches accepted, waiting for client)
            // - status "partially_confirmed" AND this client hasn't confirmed yet
            // - start time must be in the future
            let currentClientId = auth.user?.uid ?? ""
            let startOfToday = Calendar.current.startOfDay(for: Date())
            let pending = firestore.bookings.filter { booking in
                // Exclude bookings that occur in the past
                if let start = booking.startAt, start < startOfToday {
                    return false
                }
                let status = (booking.status ?? "").lowercased()
                if status == "pending acceptance" {
                    return true
                }
                if status == "partially_confirmed" {
                    // Check if current client has already confirmed
                    let confirmations = booking.clientConfirmations ?? [:]
                    return confirmations[currentClientId] != true
                }
                return false
            }
            if pending.isEmpty {
                Text("No pending bookings").foregroundColor(.secondary)
            } else {
                ForEach(pending, id: \ .id) { b in
                    VStack(alignment: .leading, spacing: 6) {
                        BookingRowView(item: b)
                            .overlay(alignment: .trailing) {
                                Button(action: { selectedBookingForReview = b }) {
                                    Text("Review Booking")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color("LogoGreen"))
                                .padding(.top, -4)
                            }
                    }
                    .padding(.vertical, 2)
                }
            }
            NavigationLink(destination:
                            ClientRequestedBookingsView()
                                .environmentObject(firestore)
                                .environmentObject(auth)) {
                Text("View Requested Bookings")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("LogoBlue"))
            .frame(maxWidth: .infinity, alignment: .leading)

            NavigationLink(destination:
                            ClientConfirmedBookingsView()
                                .environmentObject(firestore)
                                .environmentObject(auth)) {
                Text("View Confirmed Bookings")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("LogoGreen"))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    private var coachBookingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Removed label per request
            NavigationLink(destination:
                            CoachConfirmedBookingsView()
                                .environmentObject(firestore)
                                .environmentObject(auth)) {
                Text("View Confirmed Bookings")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    // === Month Calendar Section ===
    private var monthCalendarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            calendarHeaderView
            MonthCalendarView(monthAnchor: $currentMonthAnchor,
                              selectedDate: $selectedDate,
                              bookings: allRelevantBookings)
            // Selected date details
            let dayBookings = allRelevantBookings.filter { b in
                if let start = b.startAt { return isSameDay(start, selectedDate) }
                return false
            }
//            if !dayBookings.isEmpty {
//                VStack(alignment: .leading, spacing: 8) {
//                    Text("Bookings on \(DateFormatter.localizedString(from: selectedDate, dateStyle: .medium, timeStyle: .none))")
//                        .font(.headline)
//                    ForEach(dayBookings, id: \ .id) { b in
//                        BookingRowView(item: b)
//                    }
//                }
//                .padding(.vertical, 4)
//            }
        }
        .padding(.horizontal)
    }

    private var calendarHeaderView: some View {
        HStack {
            Button(action: { currentMonthAnchor = Calendar.current.date(byAdding: .month, value: -1, to: currentMonthAnchor) ?? currentMonthAnchor }) {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(monthTitle(for: currentMonthAnchor)).font(.headline)
            Spacer()
            Button(action: { currentMonthAnchor = Calendar.current.date(byAdding: .month, value: 1, to: currentMonthAnchor) ?? currentMonthAnchor }) {
                Image(systemName: "chevron.right")
            }
        }
    }

    private func monthTitle(for date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "LLLL yyyy"
        return df.string(from: date)
    }
}

// === Simple Month Calendar View ===
struct MonthCalendarView: View {
    @Binding var monthAnchor: Date
    @Binding var selectedDate: Date
    let bookings: [FirestoreManager.BookingItem]

    private var calendar: Calendar { Calendar.current }

    private var monthDays: [Date] {
        // Start of month
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthAnchor))!
        // Range of days in month
        let range = calendar.range(of: .day, in: .month, for: startOfMonth)!
        // First weekday offset
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let leadingPlaceholders = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Date] = []
        // Leading placeholders (use previous month dates purely for spacing)
        if leadingPlaceholders > 0 {
            for i in stride(from: leadingPlaceholders, to: 0, by: -1) {
                let d = calendar.date(byAdding: .day, value: -i, to: startOfMonth)!
                days.append(d)
            }
        }
        // Actual days
        for day in range {
            let d = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth)!
            days.append(d)
        }
        // Trailing to complete weeks to 6 rows (optional)
        while days.count % 7 != 0 { days.append(calendar.date(byAdding: .day, value: 1, to: days.last!)!) }
        return days
    }

    private func bookingsCount(on date: Date) -> Int {
        bookings.filter { b in
            if let start = b.startAt { return calendar.isDate(start, inSameDayAs: date) }
            return false
        }.count
    }

    var body: some View {
        VStack(spacing: 8) {
            // Weekday headers
            let symbols = calendar.shortStandaloneWeekdaySymbols
            HStack {
                ForEach(symbols, id: \ .self) { s in
                    Text(s).font(.caption).frame(maxWidth: .infinity)
                }
            }
            // Grid of days (7 columns)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(monthDays, id: \ .self) { d in
                    DayCell(date: d,
                            isCurrentMonth: calendar.isDate(d, equalTo: monthAnchor, toGranularity: .month),
                            isSelected: calendar.isDate(d, inSameDayAs: selectedDate),
                            count: bookingsCount(on: d))
                    .onTapGesture { selectedDate = d }
                }
            }
        }
    }
}

struct DayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let count: Int

    var body: some View {
        let day = Calendar.current.component(.day, from: date)
        VStack(spacing: 4) {
            Text("\(day)")
                .font(.subheadline)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isCurrentMonth ? .primary : .secondary)
                .frame(maxWidth: .infinity)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                Spacer().frame(height: 8)
            }
        }
        .padding(6)
        .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// Small reusable row view for displaying a booking
struct BookingRowView: View {
    let item: FirestoreManager.BookingItem
    @EnvironmentObject var firestore: FirestoreManager

    private var isGroup: Bool {
        item.isGroupBooking ?? false ||
        (item.coachIDs?.count ?? 0) > 1 ||
        (item.clientIDs?.count ?? 0) > 1
    }

    private func statusColor(for status: String?) -> Color {
        switch (status ?? "").lowercased() {
        case "confirmed", "fully_confirmed":
            return Color("LogoGreen")
        case "requested":
            return Color("LogoBlue")
        case "pending acceptance":
            return .orange
        case "rejected", "declined", "declined_by_client":
            return .red
        case "partially_accepted", "partially_confirmed":
            return .orange
        default:
            return .secondary
        }
    }

    private var displayTitle: String {
        if isGroup {
            return "Group Session"
        }

        let role = firestore.currentUserType?.uppercased()
        if role == "COACH" {
            // Try clientName from booking, then lookup from clients list, then fallback to "Client"
            if let name = item.clientName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                return name
            }
            if let client = firestore.clients.first(where: { $0.id == item.clientID }), !client.name.trimmingCharacters(in: .whitespaces).isEmpty {
                return client.name
            }
            return "Client"
        } else {
            // Try coachName from booking, then lookup from coaches list, then fallback to "Coach"
            if let name = item.coachName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                return name
            }
            if let coach = firestore.coaches.first(where: { $0.id == item.coachID }), !coach.name.trimmingCharacters(in: .whitespaces).isEmpty {
                return coach.name
            }
            return "Coach"
        }
    }

    private var isDisplayedPersonVerified: Bool {
        let role = firestore.currentUserType?.uppercased()
        if role == "COACH" {
            // Showing client name — check client's phoneVerified status is not available in UserSummary,
            // so skip for now (clients shown to coaches)
            return false
        } else {
            // Showing coach name — look up coach's phoneVerified
            if let coach = firestore.coaches.first(where: { $0.id == item.coachID }) {
                return coach.phoneVerified
            }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isGroup {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(.blue)
                }
                Text(displayTitle).font(.headline)
                if !isGroup && isDisplayedPersonVerified { VerifiedBadge() }
                Spacer()
                Text(item.status?.replacingOccurrences(of: "_", with: " ").capitalized ?? "")
                    .font(.caption)
                    .foregroundColor(statusColor(for: item.status))
            }

            // Show participant summary for group bookings
            if isGroup {
                // Show coaches with their acceptance status
                if !item.allCoachIDs.isEmpty {
                    let bookingRejected = (item.status ?? "").lowercased() == "rejected"
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coaches:").font(.subheadline).foregroundColor(.secondary)
                        ForEach(Array(zip(item.allCoachIDs, item.allCoachNames)), id: \.0) { coachId, coachName in
                            let accepted = item.coachAcceptances?[coachId] ?? false
                            let isRejector = item.rejectedBy == coachId
                            HStack(spacing: 4) {
                                if isRejector || (bookingRejected && !accepted) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                } else if accepted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color("LogoGreen"))
                                        .font(.caption)
                                } else {
                                    Image(systemName: "clock")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                }
                                Text(coachName)
                                    .font(.subheadline)
                                    .foregroundColor(isRejector || (bookingRejected && !accepted) ? .red : (accepted ? .primary : .secondary))
                            }
                        }
                    }
                }
                // Show clients with their confirmation status for multi-client bookings
                if item.allClientIDs.count > 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clients:").font(.subheadline).foregroundColor(.secondary)
                        ForEach(Array(zip(item.allClientIDs, item.allClientNames)), id: \.0) { clientId, clientName in
                            let confirmed = item.clientConfirmations?[clientId] ?? false
                            HStack(spacing: 4) {
                                Image(systemName: confirmed ? "checkmark.circle.fill" : "clock")
                                    .foregroundColor(confirmed ? Color("LogoGreen") : .orange)
                                    .font(.caption)
                                Text(clientName)
                                    .font(.subheadline)
                                    .foregroundColor(confirmed ? .primary : .secondary)
                            }
                        }
                    }
                } else if !item.allClientNames.isEmpty {
                    Text("Clients: \(item.allClientNames.joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text(item.participantSummary)
                    .font(.caption)
                    .foregroundColor(.blue)
            }

            if let start = item.startAt {
                Text("Start: \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let end = item.endAt {
                Text("End: \(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let location = item.location {
                Text(location).font(.body)
            }
            if let notes = item.notes {
                Text(notes).font(.footnote).foregroundColor(.secondary)
            }
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
