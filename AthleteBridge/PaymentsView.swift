import SwiftUI
import FirebaseFirestore

struct PaymentsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var platform: String = "Paypal"
    @State private var username: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false
    @State private var localPayments: [String: String] = [:]

    // New state: present coach payment methods for an unpaid booking
    @State private var showCoachPaymentsSheet: Bool = false
    @State private var selectedCoachPayments: [String: String] = [:]
    @State private var selectedCoachName: String = "Coach"

    // State for payments summary sheet (client)
    @State private var showClientSummary: Bool = false
    // State for coach revenue summary sheet
    @State private var showCoachSummary: Bool = false

    // State for client bookings tab (Unpaid vs Paid)
    @State private var selectedPaymentTab: Int = 0 // 0 = Unpaid, 1 = Paid

    // New state for summary filters
    @State private var summaryRange: SummaryRange = .last30
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()

    private let paymentOptions: [String] = ["Paypal", "Venmo", "Zelle", "Cash App"]

    private var payments: [String: String] {
        // Fallback to manager if local state is empty and manager has data
        if !localPayments.isEmpty { return localPayments }
        return firestore.currentCoach?.payments ?? [:]
    }

    private var isCoach: Bool {
        // conservative: require currentCoach profile present
        if let uid = auth.user?.uid, firestore.currentCoach?.id == uid { return true }
        return (firestore.currentUserType ?? "").uppercased() == "COACH"
    }

    // Partition client bookings by payment status in a single pass
    private var clientBookingsPartitioned: (paid: [FirestoreManager.BookingItem], unpaid: [FirestoreManager.BookingItem]) {
        var paid: [FirestoreManager.BookingItem] = []
        var unpaid: [FirestoreManager.BookingItem] = []
        for b in firestore.bookings {
            if (b.paymentStatus ?? "").lowercased() == "paid" { paid.append(b) }
            else { unpaid.append(b) }
        }
        return (paid, unpaid)
    }
    private var paidBookings: [FirestoreManager.BookingItem] { clientBookingsPartitioned.paid }
    private var unpaidBookings: [FirestoreManager.BookingItem] { clientBookingsPartitioned.unpaid }

    // Partition coach bookings in a single pass
    private var coachBookingsPartitioned: (paid: [FirestoreManager.BookingItem], unpaid: [FirestoreManager.BookingItem]) {
        var paid: [FirestoreManager.BookingItem] = []
        var unpaid: [FirestoreManager.BookingItem] = []
        for b in firestore.coachBookings {
            if (b.paymentStatus ?? "").lowercased() == "paid" { paid.append(b) }
            else { unpaid.append(b) }
        }
        return (paid, unpaid)
    }
    private var coachPaidBookings: [FirestoreManager.BookingItem] { coachBookingsPartitioned.paid }
    private var coachUnpaidBookings: [FirestoreManager.BookingItem] { coachBookingsPartitioned.unpaid }

    // Helper: resolve coach name from a booking's coachID, falling back to booking.coachName
    private func nameForCoachId(_ coachId: String?) -> String? {
        guard let id = coachId, !id.isEmpty else { return nil }
        if let coach = firestore.coaches.first(where: { $0.id == id }) {
            return coach.name
        }
        return nil
    }

    private func coachDisplayName(for booking: FirestoreManager.BookingItem) -> String {
        return nameForCoachId(booking.coachID) ?? booking.coachName ?? "Coach"
    }

    // Helper: display client name for coach-side rows
    private func clientDisplayName(for booking: FirestoreManager.BookingItem) -> String {
        (booking.clientName?.isEmpty == false ? booking.clientName! : nil) ?? "Client"
    }

    // Helper: send notification to coach that client has marked booking as paid
    private func notifyCoachOfPayment(for booking: FirestoreManager.BookingItem) {
        let coachId = booking.coachID
        guard !coachId.isEmpty else {
            self.errorMessage = "Missing coach ID for this booking."
            return
        }

        // Get client name from current client profile or fallback
        var clientName = "A client"
        if let client = firestore.currentClient, !client.name.isEmpty {
            clientName = client.name
        }

        // Send notification to coach
        let db = Firestore.firestore()
        let notifRef = db.collection("pendingNotifications").document(coachId).collection("notifications").document()
        let notifPayload: [String: Any] = [
            "title": "Payment Notification",
            "body": "\(clientName) has marked booking as paid. Please confirm",
            "bookingId": booking.id,
            "senderId": auth.user?.uid ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "delivered": false
        ]
        notifRef.setData(notifPayload) { err in
            DispatchQueue.main.async {
                if let err = err {
                    errorMessage = "Failed to notify coach: \(err.localizedDescription)"
                } else {
                    errorMessage = "Coach has been notified of your payment."
                }
            }
        }
    }

    // Helper: trigger payment flow for an unpaid booking — now fetch and show coach payment methods
    private func makePayment(for booking: FirestoreManager.BookingItem) {
        // Resolve coach ID string (uid or path tolerated by helper)
        let coachId = booking.coachID
        guard !coachId.isEmpty else {
            self.errorMessage = "Missing coach ID for this booking."
            return
        }
        // Fetch payments and coach name, then present sheet
        FirestoreManager.shared.fetchCoachPayments(coachIdOrPath: coachId) { map in
            DispatchQueue.main.async {
                self.selectedCoachPayments = map
                self.selectedCoachName = self.coachDisplayName(for: booking)
                self.showCoachPaymentsSheet = true
            }
        }
        // Optionally also refresh name from Firestore if local cache lacked it
        FirestoreManager.shared.fetchCoachDisplayName(coachIdOrPath: coachId) { name in
            DispatchQueue.main.async {
                if !name.isEmpty { self.selectedCoachName = name }
            }
        }
    }

    // Ensure username has an appropriate leading character for selected platform when empty or only previous prefix
    private func applyPrefixIfNeeded(for platform: String) {
        let p = platform.lowercased()
        if p == "cash app" || p == "cashapp" {
            if username.isEmpty || username == "@" { username = "$" }
            // avoid duplicating $ if user already started typing
            if !username.isEmpty, !username.hasPrefix("$") && username != "@" { /* leave as-is */ }
        } else if p == "venmo" {
            if username.isEmpty || username == "$" { username = "@" }
            if !username.isEmpty, !username.hasPrefix("@") && username != "$" { /* leave as-is */ }
        }
    }

    // Get RateUSD from a booking (prefer direct property, fallback to Mirror for safety)
    private func rateUSDValue(for booking: FirestoreManager.BookingItem) -> Double? {
        // Try Mirror first to match existing behavior
        let mirror = Mirror(reflecting: booking)
        if let child = mirror.children.first(where: { $0.label == "RateUSD" || $0.label == "rateUSD" }) {
            if let rate = child.value as? Double { return rate }
            if let str = child.value as? String, let val = Double(str) { return val }
        }
        return nil
    }

    // Sum paid bookings' RateUSD; treat nil as 0 (CLIENT side)
    private var totalPaidUSD: Double {
        paidBookings.reduce(0.0) { acc, b in acc + (rateUSDValue(for: b) ?? 0.0) }
    }

    // Coach totals (all-time)
    private var totalCoachPaidUSD: Double {
        coachPaidBookings.reduce(0.0) { $0 + (rateUSDValue(for: $1) ?? 0.0) }
    }

    private func formatUSD(_ amount: Double) -> String {
        if amount >= 1000 {
            return String(format: "$%.0f", amount)
        }
        return String(format: "$%.2f", amount)
    }

    // New enum and state for summary date range filtering
    private enum SummaryRange: String, CaseIterable, Identifiable {
        case all = "All"
        case last30 = "Last 30 Days"
        case last90 = "Last 90 Days"
        case ytd = "Year to Date"
        case custom = "Custom"
        var id: String { rawValue }
        var title: String { rawValue }
    }

    private func inSelectedRange(_ date: Date?) -> Bool {
        guard let d = date else { return false }
        switch summaryRange {
        case .all:
            return true
        case .last30:
            if let start = Calendar.current.date(byAdding: .day, value: -30, to: Date()) { return d >= start && d <= Date() }
            return true
        case .last90:
            if let start = Calendar.current.date(byAdding: .day, value: -90, to: Date()) { return d >= start && d <= Date() }
            return true
        case .ytd:
            let cal = Calendar.current
            let comps = cal.dateComponents([.year], from: Date())
            if let year = comps.year, let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) { return d >= start && d <= Date() }
            return true
        case .custom:
            return d >= customStart && d <= customEnd
        }
    }

    private var filteredPaid: [FirestoreManager.BookingItem] {
        paidBookings.filter { inSelectedRange($0.startAt) }
    }

    private var filteredTotalPaidUSD: Double {
        filteredPaid.reduce(0.0) { $0 + (rateUSDValue(for: $1) ?? 0.0) }
    }

    // Coach filtered metrics
    private var filteredCoachPaid: [FirestoreManager.BookingItem] {
        coachPaidBookings.filter { inSelectedRange($0.startAt) }
    }
    private var filteredCoachTotalPaidUSD: Double {
        filteredCoachPaid.reduce(0.0) { $0 + (rateUSDValue(for: $1) ?? 0.0) }
    }
    private var clientDistributionForCoach: [(name: String, count: Int, total: Double)] {
        var map: [String: (count: Int, total: Double)] = [:]
        for b in filteredCoachPaid {
            let name = clientDisplayName(for: b)
            let amt = rateUSDValue(for: b) ?? 0.0
            let cur = map[name] ?? (0, 0.0)
            map[name] = (cur.count + 1, cur.total + amt)
        }
        return map.map { (key, val) in (name: key, count: val.count, total: val.total) }
            .sorted { $0.total > $1.total }
    }

    // Client-side distribution by coach for the client summary sheet
    private var coachDistribution: [(name: String, count: Int, total: Double)] {
        var map: [String: (count: Int, total: Double)] = [:]
        for b in filteredPaid {
            let name = coachDisplayName(for: b)
            let amt = rateUSDValue(for: b) ?? 0.0
            let cur = map[name] ?? (0, 0.0)
            map[name] = (cur.count + 1, cur.total + amt)
        }
        return map.map { (key, val) in (name: key, count: val.count, total: val.total) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header: show summary for clients, else show default payments header
            if (firestore.currentUserType ?? "").uppercased() == "CLIENT" {
                HStack(spacing: 12) {
                    Text("Total Paid: \(formatUSD(totalPaidUSD))")
                        .font(.title2).bold()
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Payments summary button for clients
                Button(action: { showClientSummary = true }) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Payments Summary")
                            .bold()
                        Spacer()
                        Text(formatUSD(totalPaidUSD))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            } else {
                // Coach header shows Total Revenue + summary button
                HStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Payments").font(.title2).bold()
                        Text("Total Revenue: \(formatUSD(totalCoachPaidUSD))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: { showCoachSummary = true }) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Revenue Summary").bold()
                        Spacer()
                        Text(formatUSD(totalCoachPaidUSD)).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }

            // Input form for new/updated payment entry — SHOW ONLY FOR COACHES
            if isCoach {
                if !payments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved Payment Handles")
                            .font(.headline)
                        ForEach(payments.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }), id: \.key) { key, value in
                            HStack {
                                Text(key.capitalized)
                                Spacer()
                                Text(value)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                            Divider().opacity(0.2)
                        }
                    }
                } else {
                    Text("No payment handles saved yet.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(spacing: 10) {
                    // Platform dropdown
                    HStack {
                        Text("Platform")
                        Spacer()
                        Picker("Platform", selection: $platform) {
                            ForEach(paymentOptions, id: \.self) { opt in
                                Text(opt).tag(opt)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(10)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)

                    // Username/handle text field with dynamic placeholder per platform
                    let dynamicPlaceholder: String = {
                        let p = platform.lowercased()
                        if p == "cash app" || p == "cashapp" { return "Cash App Handle e.g., $username" }
                        if p == "venmo" { return "Venmo Username e.g., @username" }
                        if p == "paypal" { return "Paypal Username paypal.me/username" }
                        if p == "zelle" { return "Zelle phone or email" }
                        return "Username/handle for this platform"
                    }()

                    HStack {
                        TextField(dynamicPlaceholder, text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .disableAutocorrection(true)
                    }
                    .padding(10)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)

                    Button(action: saveEntry) {
                        if isSaving { ProgressView().progressViewStyle(.circular) }
                        Text(isSaving ? "Saving…" : "Save Payment")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .buttonStyle(.borderedProminent)
                }
            }

            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Previous bookings for clients — tabbed Unpaid / Paid
            if (firestore.currentUserType ?? "").uppercased() == "CLIENT" {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("", selection: $selectedPaymentTab) {
                        Text("Unpaid").tag(0)
                        Text("Paid").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if firestore.bookings.isEmpty {
                        Text("No bookings found.")
                            .foregroundColor(.secondary)
                    } else if selectedPaymentTab == 0 {
                        if unpaidBookings.isEmpty {
                            Text("No unpaid bookings.")
                                .foregroundColor(.secondary)
                        } else {
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach(unpaidBookings, id: \.id) { b in
                                        bookingRow(for: b)
                                        Divider().opacity(0.15)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        if paidBookings.isEmpty {
                            Text("No paid bookings.")
                                .foregroundColor(.secondary)
                        } else {
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach(paidBookings, id: \.id) { b in
                                        bookingRow(for: b)
                                        Divider().opacity(0.15)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            // Initialize local payments from manager
            localPayments = firestore.currentCoach?.payments ?? [:]
            // Fetch appropriate bookings by user type (avoid corrupting client/coach queries)
            let userType = (firestore.currentUserType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if userType == "CLIENT" {
                if let _ = auth.user?.uid { firestore.fetchBookingsForCurrentClientSubcollection() }
            } else if userType == "COACH" {
                firestore.fetchBookingsForCurrentCoachSubcollection()
            }
            // Load coaches for id->name mapping
            firestore.fetchCoaches()
            // Initialize prefix based on current platform if field is empty
            applyPrefixIfNeeded(for: platform)
        }
        .onChange(of: platform) { _, newVal in
            // When platform changes, auto-populate a sensible first character if applicable
            applyPrefixIfNeeded(for: newVal)
        }
        .onChange(of: firestore.currentCoach?.payments ?? [:]) { _, newValue in
            // Keep local state in sync if manager updates behind the scenes
            localPayments = newValue
        }
        // Present a sheet with the coach's payment methods when requested
        .sheet(isPresented: $showCoachPaymentsSheet) {
            NavigationStack {
                List {
                    if selectedCoachPayments.isEmpty {
                        Section("Payment Methods") {
                            Text("No payment methods provided yet.")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Section("Payment Methods") {
                            ForEach(selectedCoachPayments.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }), id: \.key) { key, value in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(key.capitalized).bold()
                                        Spacer()
                                        Text(value).foregroundColor(.secondary)
                                    }
                                    // Provide simple deep links for common platforms
                                    if let url = paymentDeepLink(for: key, value: value) {
                                        Link("Open \(key.capitalized)", destination: url)
                                            .font(.footnote)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Pay \(selectedCoachName)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showCoachPaymentsSheet = false }
                    }
                }
            }
        }
        // Present payments summary for clients
        .sheet(isPresented: $showClientSummary) {
            NavigationStack {
                List {
                    // Range selector
                    Section("Filter") {
                        Picker("Range", selection: $summaryRange) {
                            ForEach(SummaryRange.allCases) { r in
                                Text(r.title).tag(r)
                            }
                        }
                        .pickerStyle(.segmented)
                        if summaryRange == .custom {
                            DatePicker("Start", selection: $customStart, displayedComponents: [.date])
                            DatePicker("End", selection: $customEnd, in: customStart...Date(), displayedComponents: [.date])
                        }
                    }

                    Section("Totals") {
                        HStack { Text("Total Paid"); Spacer(); Text(formatUSD(filteredTotalPaidUSD)).bold() }
                        HStack { Text("Paid Bookings"); Spacer(); Text("\(filteredPaid.count)") }
                        HStack { Text("Unpaid Bookings"); Spacer(); Text("\(unpaidBookings.count)") }
                    }

                    Section("Recently Paid") {
                        ForEach(filteredPaid.prefix(10), id: \.id) { b in
                            HStack {
                                Text(coachDisplayName(for: b))
                                Spacer()
                                Text(formatUSD(rateUSDValue(for: b) ?? 0.0))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Section("By Coach") {
                        ForEach(coachDistribution, id: \.name) { entry in
                            HStack {
                                Text(entry.name)
                                Spacer()
                                Text("\(entry.count) • \(formatUSD(entry.total))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Payments Summary")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { showClientSummary = false } }
                }
            }
        }
        // Present revenue summary for coaches
        .sheet(isPresented: $showCoachSummary) {
            NavigationStack {
                List {
                    // Range selector
                    Section("Filter") {
                        Picker("Range", selection: $summaryRange) {
                            ForEach(SummaryRange.allCases) { r in
                                Text(r.title).tag(r)
                            }
                        }
                        .pickerStyle(.segmented)
                        if summaryRange == .custom {
                            DatePicker("Start", selection: $customStart, displayedComponents: [.date])
                            DatePicker("End", selection: $customEnd, in: customStart...Date(), displayedComponents: [.date])
                        }
                    }

                    Section("Totals") {
                        HStack { Text("Total Revenue"); Spacer(); Text(formatUSD(filteredCoachTotalPaidUSD)).bold() }
                        HStack { Text("Paid Bookings"); Spacer(); Text("\(filteredCoachPaid.count)") }
                        HStack { Text("Unpaid Bookings"); Spacer(); Text("\(coachUnpaidBookings.count)") }
                    }

                    Section("Recently Paid") {
                        ForEach(filteredCoachPaid.prefix(10), id: \.id) { b in
                            HStack {
                                Text(clientDisplayName(for: b))
                                Spacer()
                                Text(formatUSD(rateUSDValue(for: b) ?? 0.0))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Section("By Client") {
                        ForEach(clientDistributionForCoach, id: \.name) { entry in
                            HStack {
                                Text(entry.name)
                                Spacer()
                                Text("\(entry.count) • \(formatUSD(entry.total))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Revenue Summary")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { showCoachSummary = false } }
                }
            }
        }
    }

    private func bookingRow(for b: FirestoreManager.BookingItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(coachDisplayName(for: b)).font(.headline)
                Spacer()
                Text((b.paymentStatus ?? "").capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            // Show RateUSD for this booking
            Text(rateUSD(for: b))
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let start = b.startAt {
                Text("Start: \(DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let end = b.endAt {
                Text("End: \(DateFormatter.localizedString(from: end, dateStyle: .medium, timeStyle: .short))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let notes = b.notes, !notes.isEmpty {
                Text(notes).font(.footnote).foregroundColor(.secondary)
            }

            // Show Make Payment button only for unpaid bookings
            if (b.paymentStatus ?? "").lowercased() != "paid" {
                HStack {
                    // Client-only: notify coach of payment button
                    if (firestore.currentUserType ?? "").uppercased() == "CLIENT" {
                        Button(action: {
                            notifyCoachOfPayment(for: b)
                        }) {
                            Text("Notify Coach of Payment")
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                    Button(action: { makePayment(for: b) }) {
                        Text("Make Payment")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 8)
    }

    // Resolve the USD rate directly from the booking's RateUSD field using reflection (works for Swift structs)
    private func rateUSD(for booking: FirestoreManager.BookingItem) -> String {
        let mirror = Mirror(reflecting: booking)
        if let child = mirror.children.first(where: { $0.label == "RateUSD" || $0.label == "rateUSD" }) {
            // Handle Double
            if let rate = child.value as? Double {
                return String(format: "$%.0f/hr", rate)
            }
            // Handle String
            if let rateStr = child.value as? String, !rateStr.isEmpty {
                return rateStr.contains("$") ? rateStr : "$\(rateStr)/hr"
            }
        }
        return "Rate: N/A"
    }

    // Build a deep link URL for common platforms
    private func paymentDeepLink(for key: String, value: String) -> URL? {
        let k = key.lowercased()
        var v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return nil }
        switch k {
        case "venmo":
            // Venmo deep link should not include leading '@'
            if v.hasPrefix("@") { v.removeFirst() }
            return URL(string: "https://venmo.com/u/\(v)")
        case "paypal":
            if v.range(of: "^[A-Za-z0-9.-_]+$", options: .regularExpression) != nil {
                return URL(string: "https://paypal.me/\(v)")
            }
            return nil
        case "cashapp":
            return URL(string: "https://cash.app/\(v)")
        case "zelle":
            return nil
        default:
            return nil
        }
    }

    private func saveEntry() {
        errorMessage = nil
        let raw = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        // Canonicalize keys for storage
        let key: String = {
            if lower == "cash app" || lower == "cashapp" { return "cashapp" }
            if lower == "venmo" { return "venmo" }
            if lower == "paypal" { return "paypal" }
            if lower == "zelle" { return "zelle" }
            return lower
        }()
        var value = username.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove UI guidance prefixes before saving
        if key == "cashapp", value.hasPrefix("$") { value.removeFirst() }
        if key == "venmo", value.hasPrefix("@") { value.removeFirst() }
        guard !key.isEmpty && !value.isEmpty else { return }
        guard isCoach else { errorMessage = "You must be a coach to update payments."; return }

        var next = payments
        next[key] = value
        isSaving = true
        FirestoreManager.shared.updateCurrentCoachPayments(next) { err in
            isSaving = false
            if let err = err {
                errorMessage = "Failed to save: \(err.localizedDescription)"
            } else {
                localPayments = next
                username = ""
                // Re-apply prefix for convenience for another entry
                applyPrefixIfNeeded(for: platform)
            }
        }
    }
}

struct PaymentsView_Previews: PreviewProvider {
    static var previews: some View {
        PaymentsView().environmentObject(FirestoreManager()).environmentObject(AuthViewModel())
    }
}
