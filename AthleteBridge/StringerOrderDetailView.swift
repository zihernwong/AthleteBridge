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

    private var otherPartyUid: String {
        isStringerView ? order.createdBy : order.stringerId
    }

    private var otherPartyName: String {
        isStringerView ? order.buyerName : resolvedStringerName
    }

    private var resolvedStringerName: String {
        stringer?.name ?? firestore.stringers.first(where: { $0.id == order.stringerId })?.name ?? "Stringer"
    }

    var body: some View {
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
                    StatusBadge(status: order.status)
                }
            }

            // Order Details
            Section(header: Text("Order Details")) {
                detailRow(icon: "sportscourt", label: "Racket", value: order.racketName)

                if order.hasOwnString {
                    detailRow(icon: "figure.badminton", label: "String", value: "Own string")
                } else if let s = order.selectedString {
                    let costSuffix = order.stringCost.map { !$0.isEmpty ? " (\($0))" : "" } ?? ""
                    detailRow(icon: "figure.badminton", label: "String", value: "\(s)\(costSuffix)")
                }

                detailRow(icon: "gauge", label: "Tension", value: "\(order.tension) lbs")
                detailRow(icon: "clock", label: "Timeline", value: order.timelinePreference)

                if let labor = order.laborCost, !labor.isEmpty {
                    detailRow(icon: "wrench.and.screwdriver", label: "Labor", value: labor)
                }

                if let total = order.orderTotal, !total.isEmpty {
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
                    Text(order.createdAt, style: .date)
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

            // Action Buttons (stringer only)
            if isStringerView && !isUpdating {
                actionSection
            } else if isStringerView && isUpdating {
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

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionSection: some View {
        switch order.status {
        case "placed":
            Section {
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
            }

        case "accepted":
            Section {
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
            }

        case "stringing":
            Section {
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
            }

        default:
            EmptyView()
        }
    }

    private func updateStatus(_ newStatus: String) {
        guard let stringer = stringer else { return }
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
                    dismiss()
                }
            }
        }
    }
}
