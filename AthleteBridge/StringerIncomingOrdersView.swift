import SwiftUI

struct StringerIncomingOrdersView: View {
    @EnvironmentObject var firestore: FirestoreManager
    let stringer: BadmintonStringer

    private var pendingOrders: [StringerOrder] {
        firestore.stringerIncomingOrders.filter { $0.status == "placed" }
    }

    private var activeOrders: [StringerOrder] {
        firestore.stringerIncomingOrders.filter { $0.status == "accepted" || $0.status == "stringing" }
    }

    private var historyOrders: [StringerOrder] {
        firestore.stringerIncomingOrders.filter { $0.status == "completed" || $0.status == "declined" }
    }

    var body: some View {
        List {
            if firestore.stringerIncomingOrders.isEmpty {
                Text("No orders yet.")
                    .foregroundColor(.secondary)
            }

            if !pendingOrders.isEmpty {
                Section(header: Text("Pending")) {
                    ForEach(pendingOrders) { order in
                        NavigationLink {
                            StringerOrderDetailView(order: order, stringer: stringer, isStringerView: true)
                                .environmentObject(firestore)
                        } label: {
                            StringerOrderRow(order: order)
                        }
                    }
                }
            }

            if !activeOrders.isEmpty {
                Section(header: Text("Active")) {
                    ForEach(activeOrders) { order in
                        NavigationLink {
                            StringerOrderDetailView(order: order, stringer: stringer, isStringerView: true)
                                .environmentObject(firestore)
                        } label: {
                            StringerOrderRow(order: order)
                        }
                    }
                }
            }

            if !historyOrders.isEmpty {
                Section(header: Text("History")) {
                    ForEach(historyOrders) { order in
                        NavigationLink {
                            StringerOrderDetailView(order: order, stringer: stringer, isStringerView: true)
                                .environmentObject(firestore)
                        } label: {
                            StringerOrderRow(order: order)
                        }
                    }
                }
            }
        }
        .navigationTitle("Incoming Orders")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            firestore.fetchOrdersForStringer(stringerId: stringer.id)
        }
    }
}

// MARK: - Order Row (summary only, no action buttons)

private struct StringerOrderRow: View {
    let order: StringerOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: buyer name + status badge
            HStack {
                Text(order.buyerName)
                    .font(.headline)
                Spacer()
                StatusBadge(status: order.status)
            }

            // Order details
            HStack(spacing: 4) {
                Image(systemName: "sportscourt")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(order.racketName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if order.hasOwnString {
                Text("Has own string")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let s = order.selectedString {
                HStack(spacing: 4) {
                    Text(s)
                        .font(.caption)
                        .fontWeight(.medium)
                    if let cost = order.stringCost, !cost.isEmpty {
                        Text("(\(cost))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "gauge")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("\(order.tension) lbs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(order.timelinePreference)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let total = order.orderTotal, !total.isEmpty {
                HStack(spacing: 4) {
                    Text("Order Total:")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(total)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color("LogoGreen"))
                }
            }

            Text(order.createdAt, style: .date)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: String

    private var color: Color {
        switch status {
        case "placed": return Color("LogoBlue")
        case "accepted": return .orange
        case "stringing": return .purple
        case "completed": return Color("LogoGreen")
        case "declined": return .red
        default: return .gray
        }
    }

    var body: some View {
        Text(status.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}
