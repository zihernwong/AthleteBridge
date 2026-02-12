import SwiftUI

struct MyStringerOrdersView: View {
    @EnvironmentObject var firestore: FirestoreManager

    var body: some View {
        List {
            if firestore.myStringerOrders.isEmpty {
                Text("You haven't placed any stringing orders yet.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(firestore.myStringerOrders) { order in
                    MyOrderRow(order: order, firestore: firestore)
                }
            }
        }
        .navigationTitle("My Stringing Orders")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            firestore.fetchOrdersForBuyer()
            if firestore.stringers.isEmpty {
                firestore.fetchStringers()
            }
        }
    }
}

private struct MyOrderRow: View {
    let order: StringerOrder
    let firestore: FirestoreManager

    private var stringerName: String {
        firestore.stringers.first(where: { $0.id == order.stringerId })?.name ?? "Stringer"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: stringer name + status
            HStack {
                Text(stringerName)
                    .font(.headline)
                Spacer()
                StatusBadge(status: order.status)
            }

            // Racket info
            HStack(spacing: 4) {
                Image(systemName: "sportscourt")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(order.racketName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // String details
            if order.hasOwnString {
                Text("Using own string")
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
        }
        .padding(.vertical, 4)
    }
}
