import SwiftUI

struct StringingTabView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

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
        .onAppear {
            firestore.fetchOrdersForBuyer()
            if firestore.stringers.isEmpty {
                firestore.fetchStringers()
            }
            if let stringer = currentUserStringer {
                firestore.fetchOrdersForStringer(stringerId: stringer.id)
            }
        }
    }

    // MARK: - Stringer Role View (manage incoming orders)

    @ViewBuilder
    private var stringerManagerView: some View {
        // Incoming orders (primary section for stringers)
        if let stringer = currentUserStringer {
            Section {
                NavigationLink {
                    StringerIncomingOrdersView(stringer: stringer)
                        .environmentObject(firestore)
                } label: {
                    HStack {
                        Image(systemName: "tray.and.arrow.down")
                            .foregroundColor(Color("LogoGreen"))
                        Text("Incoming Orders")
                        Spacer()
                        let pendingCount = firestore.stringerIncomingOrders.filter { $0.status == "placed" }.count
                        if pendingCount > 0 {
                            Text("\(pendingCount) pending")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            } header: {
                Text("Orders I Received")
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

        // My placed orders
        Section {
            NavigationLink {
                MyStringerOrdersView()
                    .environmentObject(firestore)
            } label: {
                HStack {
                    Image(systemName: "cart")
                        .foregroundColor(Color("LogoBlue"))
                    Text("My Orders")
                    Spacer()
                    if !firestore.myStringerOrders.isEmpty {
                        Text("\(firestore.myStringerOrders.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("Orders I Placed")
        }

        // Browse stringers
        Section {
            NavigationLink {
                StringersView()
                    .environmentObject(firestore)
                    .environmentObject(auth)
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    Text("Browse Stringers")
                }
            }
        }
    }

    // MARK: - Customer View (browse, place orders, track)

    @ViewBuilder
    private var customerView: some View {
        // Browse stringers (primary action for customers)
        Section {
            NavigationLink {
                StringersView()
                    .environmentObject(firestore)
                    .environmentObject(auth)
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color("LogoBlue"))
                    Text("Find a Stringer")
                }
            }
        } header: {
            Text("Place an Order")
        } footer: {
            Text("Browse available stringers and place a stringing order.")
        }

        // My placed orders
        Section {
            NavigationLink {
                MyStringerOrdersView()
                    .environmentObject(firestore)
            } label: {
                HStack {
                    Image(systemName: "cart")
                        .foregroundColor(Color("LogoGreen"))
                    Text("My Orders")
                    Spacer()
                    if !firestore.myStringerOrders.isEmpty {
                        Text("\(firestore.myStringerOrders.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("Track Orders")
        }
    }
}
