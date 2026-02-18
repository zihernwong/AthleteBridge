import SwiftUI

struct StringingTabView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var deepLink: DeepLinkManager

    // Deep link state
    @State private var pendingDeepLinkOrderId: String? = nil
    @State private var deepLinkedOrder: StringerOrder? = nil
    @State private var navigateToDeepLinkedOrder = false

    /// Whether the current user has the Stringer additional role.
    /// Checks both the additionalTypes array and the stringers collection (source of truth).
    private var isStringerRole: Bool {
        firestore.currentAdditionalTypes.contains(AdditionalUserType.stringer.rawValue) || currentUserStringer != nil
    }

    /// The current user's stringer profile, if they are a registered stringer.
    /// Since the Stringer collection now uses the user's UID as the document key,
    /// we match on stringer.id (which equals the user's UID).
    private var currentUserStringer: BadmintonStringer? {
        guard let uid = auth.user?.uid else { return nil }
        return firestore.stringers.first(where: { $0.id == uid })
    }

    var body: some View {
        List {
            if isStringerRole {
                stringerManagerView
            } else {
                customerView
            }
        }
        .navigationTitle("Stringing")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditStringerSheet) {
            if let stringer = currentUserStringer {
                EditStringerView(stringer: stringer)
                    .environmentObject(firestore)
            }
        }
        .navigationDestination(isPresented: $navigateToDeepLinkedOrder) {
            if let order = deepLinkedOrder {
                let isStringer = currentUserStringer != nil && order.stringerId == currentUserStringer?.id
                StringerOrderDetailView(
                    order: order,
                    stringer: isStringer ? currentUserStringer : firestore.stringers.first(where: { $0.id == order.stringerId }),
                    isStringerView: isStringer
                )
                .environmentObject(firestore)
            }
        }
        .onAppear {
            firestore.fetchOrdersForBuyer()
            if firestore.stringers.isEmpty {
                firestore.fetchStringers()
            }
            if let stringer = currentUserStringer {
                firestore.fetchOrdersForStringer(stringerId: stringer.id)
            }

            // Handle deep link on cold start
            if case .stringing(let orderId) = deepLink.pendingDestination, let orderId = orderId {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    handleStringerOrderDeepLink(orderId: orderId)
                }
            }
        }
        .onChange(of: deepLink.pendingDestination) { _old, destination in
            guard case .stringing(let orderId) = destination, let orderId = orderId else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                handleStringerOrderDeepLink(orderId: orderId)
            }
        }
        .onChange(of: firestore.stringerIncomingOrders) { _, _ in
            if let oid = pendingDeepLinkOrderId {
                handleStringerOrderDeepLink(orderId: oid)
            }
        }
        .onChange(of: firestore.myStringerOrders) { _, _ in
            if let oid = pendingDeepLinkOrderId {
                handleStringerOrderDeepLink(orderId: oid)
            }
        }
    }

    // MARK: - Deep Link Handler

    private func handleStringerOrderDeepLink(orderId: String) {
        if let order = firestore.stringerIncomingOrders.first(where: { $0.id == orderId })
            ?? firestore.myStringerOrders.first(where: { $0.id == orderId }) {
            pendingDeepLinkOrderId = nil
            deepLink.pendingDestination = nil
            deepLinkedOrder = order
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                navigateToDeepLinkedOrder = true
            }
        } else {
            // Not found yet — store for retry and fetch fresh data
            pendingDeepLinkOrderId = orderId
            firestore.fetchOrdersForBuyer()
            if let stringer = currentUserStringer {
                firestore.fetchOrdersForStringer(stringerId: stringer.id)
            }
        }
    }

    // MARK: - Stringer Role View (manage incoming orders)

    @State private var showEditStringerSheet = false

    private var pendingOrders: [StringerOrder] {
        firestore.stringerIncomingOrders.filter { $0.status == "placed" }
    }

    private var activeOrders: [StringerOrder] {
        firestore.stringerIncomingOrders.filter { $0.status == "accepted" || $0.status == "stringing" }
    }

    private var historyOrders: [StringerOrder] {
        firestore.stringerIncomingOrders.filter { $0.status == "completed" || $0.status == "declined" }
    }

    @ViewBuilder
    private var stringerManagerView: some View {
        if let stringer = currentUserStringer {
            // Edit Profile button
            Section {
                Button {
                    showEditStringerSheet = true
                } label: {
                    HStack {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundColor(Color("LogoBlue"))
                        Text("Edit Stringer Profile")
                            .foregroundColor(.primary)
                    }
                }
            }

            // Inline incoming orders
            if firestore.stringerIncomingOrders.isEmpty {
                Section {
                    Text("No incoming orders yet.")
                        .foregroundColor(.secondary)
                }
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
        } else {
            // Stringer role but no stringer profile yet — prompt to register
            Section {
                NavigationLink {
                    StringersView()
                        .environmentObject(firestore)
                        .environmentObject(auth)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                            .foregroundColor(Color("LogoGreen"))
                        Text("Register as a Stringer")
                    }
                }
            } header: {
                Text("Get Started")
            } footer: {
                Text("Create your stringer profile to start receiving orders.")
            }
        }
    }

    // MARK: - Customer View (browse, place orders, track)

    @ViewBuilder
    private var customerView: some View {
        Section {
            Text("Browse Stringers from the homepage to find stringers and view your placed orders.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
