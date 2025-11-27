import SwiftUI

/// CoachCalendarGridView
/// - Displays a grid of time slots for a single date for a given coach.
/// - Booked slots are shown greyed-out; available slots are blue and tappable.
/// - When an available slot is tapped the `onSlotSelected` closure is called with the start and end Date.
struct CoachCalendarGridView: View {
    @EnvironmentObject var firestore: FirestoreManager

    let coachID: String
    let date: Date
    let slotMinutes: Int = 30
    let startHour: Int = 6    // 6:00 AM
    let endHour: Int = 20     // 8:00 PM (exclusive)

    // Callback when a free slot is selected
    var onSlotSelected: ((Date, Date) -> Void)? = nil

    private var calendar: Calendar { Calendar.current }

    // Filter the firestore coachBookings for this coach and date
    private var todaysBookings: [FirestoreManager.BookingItem] {
        firestore.coachBookings.filter { $0.coachID == coachID && isSameDay($0.startAt, date) }
    }

    // Generate list of slot start times for the date
    private var slots: [Date] {
        var s: [Date] = []
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        for hour in startHour..<endHour {
            for minute in stride(from: 0, to: 60, by: slotMinutes) {
                var comps = components
                comps.hour = hour
                comps.minute = minute
                comps.second = 0
                if let dt = calendar.date(from: comps) {
                    s.append(dt)
                }
            }
        }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dateString(date)).font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    CapsuleView(color: Color.gray.opacity(0.3), text: "Booked")
                    CapsuleView(color: Color.blue.opacity(0.25), text: "Available")
                }
            }

            // Grid of slots
            let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(slots, id: \.self) { slotStart in
                    let slotEnd = calendar.date(byAdding: .minute, value: slotMinutes, to: slotStart) ?? slotStart
                    let booked = isSlotBooked(start: slotStart, end: slotEnd)
                    Button(action: {
                        if !booked {
                            onSlotSelected?(slotStart, slotEnd)
                        }
                    }) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(timeString(slotStart))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(booked ? bookedLabel(for: slotStart, end: slotEnd) : "Available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(booked ? Color(UIColor.systemGray5) : Color.blue.opacity(0.2))
                        .cornerRadius(8)
                    }
                    .disabled(booked)
                }
            }
        }
        .padding()
    }

    // MARK: - Helpers
    private func isSameDay(_ d1: Date?, _ d2: Date) -> Bool {
        guard let d1 = d1 else { return false }
        return calendar.isDate(d1, inSameDayAs: d2)
    }

    private func isSlotBooked(start: Date, end: Date) -> Bool {
        for b in todaysBookings {
            if let s = b.startAt, let e = b.endAt {
                if rangesOverlap(aStart: s, aEnd: e, bStart: start, bEnd: end) {
                    return true
                }
            }
        }
        return false
    }

    private func rangesOverlap(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date) -> Bool {
        return aStart < bEnd && bStart < aEnd
    }

    private func bookedLabel(for start: Date, end: Date) -> String {
        // show client name if present, else short id
        if let booking = todaysBookings.first(where: { b in
            guard let s = b.startAt, let e = b.endAt else { return false }
            return rangesOverlap(aStart: s, aEnd: e, bStart: start, bEnd: end)
        }) {
            if let name = booking.clientName, !name.isEmpty { return name }
            return "Booked"
        }
        return "Booked"
    }

    private func timeString(_ d: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: d)
    }

    private func dateString(_ d: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: d)
    }
}

private struct CapsuleView: View {
    let color: Color
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(color)
            .cornerRadius(12)
    }
}

// MARK: - Preview
struct CoachCalendarGridView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a temporary FirestoreManager with sample bookings
        let fm = FirestoreManager()
        // create sample booking items
        let now = Date()
        let cal = Calendar.current
        let todayStart = cal.date(bySettingHour: 6, minute: 0, second: 0, of: now) ?? now
        let sample1 = FirestoreManager.BookingItem(id: "b1", clientID: "c1", clientName: "Alice", coachID: "coach123", coachName: "Reuben", startAt: todayStart.addingTimeInterval(60*60*2), endAt: todayStart.addingTimeInterval(60*60*3), location: "Target Center", notes: "" , status: "Requested")
        let sample2 = FirestoreManager.BookingItem(id: "b2", clientID: "c2", clientName: "Bob", coachID: "coach123", coachName: "Reuben", startAt: todayStart.addingTimeInterval(60*60*5), endAt: todayStart.addingTimeInterval(60*60*6), location: "Lake Marion", notes: "", status: "Confirmed")
        fm.coachBookings = [sample1, sample2]

        return CoachCalendarGridView(coachID: "coach123", date: now, onSlotSelected: { start, end in
            print("Selected slot: \(start) -> \(end)")
        }).environmentObject(fm)
    }
}
