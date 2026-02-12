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
                        StringerOrderRow(order: order, stringer: stringer, firestore: firestore)
                    }
                }
            }

            if !activeOrders.isEmpty {
                Section(header: Text("Active")) {
                    ForEach(activeOrders) { order in
                        StringerOrderRow(order: order, stringer: stringer, firestore: firestore)
                    }
                }
            }

            if !historyOrders.isEmpty {
                Section(header: Text("History")) {
                    ForEach(historyOrders) { order in
                        StringerOrderRow(order: order, stringer: stringer, firestore: firestore)
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

// MARK: - Order Row with Actions

private struct StringerOrderRow: View {
    let order: StringerOrder
    let stringer: BadmintonStringer
    let firestore: FirestoreManager
    @State private var isUpdating = false

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

            Text(order.createdAt, style: .date)
                .font(.caption2)
                .foregroundColor(.secondary)

            // Action buttons
            if !isUpdating {
                actionButtons
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch order.status {
        case "placed":
            HStack(spacing: 12) {
                Button(action: { updateStatus("accepted") }) {
                    Text("Accept")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color("LogoGreen"))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { updateStatus("declined") }) {
                    Text("Decline")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }

        case "accepted":
            Button(action: { updateStatus("stringing") }) {
                Text("Mark as Stringing")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(.purple)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

        case "stringing":
            Button(action: { updateStatus("completed") }) {
                Text("Mark as Completed")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color("LogoGreen").opacity(0.15))
                    .foregroundColor(Color("LogoGreen"))
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

        default:
            EmptyView()
        }
    }

    private func updateStatus(_ newStatus: String) {
        isUpdating = true
        firestore.updateStringerOrderStatus(
            orderId: order.id,
            status: newStatus,
            buyerUid: order.createdBy,
            stringerName: stringer.name
        ) { err in
            DispatchQueue.main.async {
                isUpdating = false
                if err == nil {
                    firestore.fetchOrdersForStringer(stringerId: stringer.id)
                }
            }
        }
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
