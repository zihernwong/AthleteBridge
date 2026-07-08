import SwiftUI
import FirebaseAuth

struct StringerOrderDetailView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss
    let order: StringerOrder
    let stringer: BadmintonStringer?
    let isStringerView: Bool

    private struct ChatSheetId: Identifiable { let id: String }
    @State private var presentedChat: ChatSheetId? = nil
    @State private var isUpdating = false

    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }

    /// Live order from Firestore arrays, falls back to the initially passed order
    private var liveOrder: StringerOrder {
        if isStringerView {
            return firestore.stringerIncomingOrders.first(where: { $0.id == order.id }) ?? order
        } else {
            return firestore.myStringerOrders.first(where: { $0.id == order.id }) ?? order
        }
    }

    private var otherPartyUid: String {
        isStringerView ? liveOrder.createdBy : liveOrder.stringerId
    }

    private var otherPartyName: String {
        isStringerView ? liveOrder.buyerName : resolvedStringerName
    }

    private var resolvedStringerName: String {
        stringer?.name ?? firestore.stringers.first(where: { $0.id == liveOrder.stringerId })?.name ?? "Stringer"
    }

    var body: some View {
        let ord = liveOrder
        List {
            // Header
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(otherPartyName)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(isStringerView ? "Buyer" : "Stringer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    StatusBadge(status: ord.status)
                }
            }

            // Progress timeline (hidden for declined orders)
            if ord.status.lowercased() != "declined" {
                Section(header: Text("Order Progress")) {
                    let stageLabels: [String: String] = [
                        "placed": "Order Placed",
                        "accepted": "Accepted by Stringer",
                        "stringing": "Stringing in Progress",
                        "ready_for_pickup": "Ready for Pickup",
                        "picked_up": "Picked Up"
                    ]
                    ForEach(StringerOrder.timelineStages, id: \.self) { stage in
                        let reached = ord.isStageReached(stage)
                        HStack(spacing: 10) {
                            Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(reached ? Color("LogoGreen") : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stageLabels[stage] ?? stage)
                                    .fontWeight(reached ? .semibold : .regular)
                                    .foregroundColor(reached ? .primary : .secondary)
                                if reached, let ts = ord.stageTimestamp(stage) {
                                    Text(DateFormatter.localizedString(from: ts, dateStyle: .medium, timeStyle: .short))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            // Order Details
            Section(header: Text("Order Details")) {
                detailRow(icon: "sportscourt", label: "Racket", value: ord.racketName)

                if ord.hasOwnString {
                    detailRow(icon: "figure.badminton", label: "String", value: "Own string")
                } else if let s = ord.selectedString {
                    let costSuffix = ord.stringCost.map { !$0.isEmpty ? " (\($0))" : "" } ?? ""
                    detailRow(icon: "figure.badminton", label: "String", value: "\(s)\(costSuffix)")
                }

                detailRow(icon: "gauge", label: "Tension", value: "\(ord.tension) lbs")
                detailRow(icon: "clock", label: "Timeline", value: ord.timelinePreference)

                if let labor = ord.laborCost, !labor.isEmpty {
                    detailRow(icon: "wrench.and.screwdriver", label: "Labor", value: labor)
                }

                if let total = ord.orderTotal, !total.isEmpty {
                    HStack {
                        Label("Total", systemImage: "dollarsign.circle")
                            .font(.body)
                        Spacer()
                        Text(total)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(Color("LogoGreen"))
                    }
                }

                HStack {
                    Label("Placed", systemImage: "calendar")
                        .font(.body)
                    Spacer()
                    Text(ord.createdAt, style: .date)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            // Message Button
            Section {
                Button(action: { openChat() }) {
                    HStack {
                        Spacer()
                        Label(isStringerView ? "Message Buyer" : "Message Stringer", systemImage: "message.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color("LogoBlue"))
                    .cornerRadius(10)
                }
                .listRowBackground(Color.clear)
            }

            // Action Buttons
            if !isUpdating {
                if isStringerView {
                    stringerActionSection
                } else {
                    buyerActionSection
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Order Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Refresh order data so deep-linked views show the latest status
            if isStringerView {
                if let s = stringer { firestore.fetchOrdersForStringer(stringerId: s.id) }
            } else {
                firestore.fetchOrdersForBuyer()
            }
        }
        .sheet(item: $presentedChat) { sheet in
            NavigationStack {
                ChatView(chatId: sheet.id)
                    .environmentObject(firestore)
            }
        }
    }

    // MARK: - Detail Row Helper

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Message

    private func openChat() {
        guard !currentUid.isEmpty else {
            firestore.showToast("Please sign in to message")
            return
        }
        let expectedChatId = [currentUid, otherPartyUid].sorted().joined(separator: "_")
        presentedChat = ChatSheetId(id: expectedChatId)
        firestore.createOrGetChat(withCoachId: otherPartyUid) { chatId in
            DispatchQueue.main.async {
                let target = chatId ?? expectedChatId
                if target != expectedChatId {
                    presentedChat = ChatSheetId(id: target)
                }
            }
        }
    }

    // MARK: - Stringer Action Buttons

    @ViewBuilder
    private var stringerActionSection: some View {
        switch liveOrder.status {
        case "placed":
            Section {
                HStack(spacing: 12) {
                    Button(action: { updateStatusAsStringer("accepted") }) {
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

                    Button(action: { updateStatusAsStringer("declined") }) {
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
            }

        case "accepted":
            Section {
                Button(action: { updateStatusAsStringer("stringing") }) {
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
            }

        case "stringing":
            Section {
                Button(action: { updateStatusAsStringer("ready_for_pickup") }) {
                    Text("Mark as Ready For Pickup")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.teal.opacity(0.15))
                        .foregroundColor(.teal)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Buyer Action Buttons

    @ViewBuilder
    private var buyerActionSection: some View {
        switch liveOrder.status {
        case "ready_for_pickup":
            Section {
                Button(action: { updateStatusAsBuyer("picked_up") }) {
                    Text("Mark as Picked Up")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color("LogoGreen").opacity(0.15))
                        .foregroundColor(Color("LogoGreen"))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Status Update Actions

    private func updateStatusAsStringer(_ newStatus: String) {
        guard let stringer = stringer else { return }
        isUpdating = true
        let ord = liveOrder
        firestore.updateStringerOrderStatus(
            orderId: ord.id,
            status: newStatus,
            buyerUid: ord.createdBy,
            stringerName: stringer.name
        ) { err in
            DispatchQueue.main.async {
                isUpdating = false
                if err == nil {
                    firestore.fetchOrdersForStringer(stringerId: stringer.id)
                    dismiss()
                }
            }
        }
    }

    private func updateStatusAsBuyer(_ newStatus: String) {
        isUpdating = true
        let ord = liveOrder
        firestore.updateStringerOrderStatusAsBuyer(
            orderId: ord.id,
            status: newStatus,
            stringerUid: ord.stringerId,
            buyerName: ord.buyerName
        ) { err in
            DispatchQueue.main.async {
                isUpdating = false
                if err == nil {
                    firestore.fetchOrdersForBuyer()
                    dismiss()
                }
            }
        }
    }
}
