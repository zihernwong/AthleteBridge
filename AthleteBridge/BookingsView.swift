import SwiftUI

struct BookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var showingNewBooking = false
    @State private var selectedBookingForAccept: FirestoreManager.BookingItem? = nil
    @State private var selectedBookingForReview: FirestoreManager.BookingItem? = nil
    @State private var selectedDate = Date()
    @State private var currentMonthAnchor = Date() // month displayed by calendar

    private var currentUserRole: String? { firestore.currentUserType?.uppercased() }

    var body: some View {
        NavigationStack {
            // Replace List with ScrollView + VStack to avoid UICollectionView feedback loop on device
            ScrollView {
                VStack(spacing: 16) {
                    // === Today’s Bookings (for both roles) ===
                    todaysBookingsSection

                    // === Month Calendar === (below Today and above My/ Accepted Bookings)
                    monthCalendarSection

                    // Requested bookings section for coaches
                    if currentUserRole == "COACH" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Requested Bookings").font(.headline)
                            let requested = firestore.coachBookings.filter { ($0.status ?? "").lowercased() == "requested" }
                            if requested.isEmpty {
                                Text("No requested bookings").foregroundColor(.secondary)
                            } else {
                                ForEach(requested, id: \ .id) { b in
                                    VStack(alignment: .leading, spacing: 6) {
                                        BookingRowView(item: b)
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
            }
            .sheet(isPresented: $showingNewBooking) {
                BookingEditorView(showSheet: $showingNewBooking)
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

    // === Today’s Bookings Section ===
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
                    BookingRowView(item: b)
                }
            }
        }
        .padding(.horizontal)
    }

    private func acceptBooking(_ b: FirestoreManager.BookingItem) {
        firestore.updateBookingStatus(bookingId: b.id, status: "accepted") { err in
            DispatchQueue.main.async {
                if let err = err {
                    // simple error indicator
                    print("acceptBooking error: \(err)")
                } else {
                    // Refresh coach bookings
                    firestore.fetchBookingsForCurrentCoachSubcollection()
                    firestore.showToast("Booking accepted")
                }
            }
        }
    }

    private var clientPendingAcceptanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bookings Pending Acceptance").font(.headline)
            let pending = firestore.bookings.filter { ($0.status ?? "").lowercased() == "pending acceptance" }
            if pending.isEmpty {
                Text("No pending bookings").foregroundColor(.secondary)
            } else {
                ForEach(pending, id: \ .id) { b in
                    VStack(alignment: .leading, spacing: 6) {
                        BookingRowView(item: b)
                            .overlay(alignment: .trailing) {
                                Button(action: { acceptBooking(b) }) {
                                    Text("Review Booking")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .padding(.top, -4)
                            }
                    }
                    .padding(.vertical, 2)
                }
            }
            NavigationLink(destination:
                            ConfirmedBookingsView()
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

    private var coachBookingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    private var displayTitle: String {
        let role = firestore.currentUserType?.uppercased()
        if role == "COACH" {
            return item.clientName ?? item.clientID
        } else {
            return item.coachName ?? item.coachID
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayTitle).font(.headline)
                Spacer()
                Text(item.status?.capitalized ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
