import SwiftUI

/// Home view for coaches that combines Stringing and Reviews sections
/// into a single unified page similar to ClientFormView for clients.
struct CoachHomeView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var deepLink: DeepLinkManager
    // Deep link state for stringing orders
    @State private var pendingDeepLinkOrderId: String? = nil
    @State private var deepLinkedOrder: StringerOrder? = nil
    @State private var navigateToDeepLinkedOrder = false

    // Deep link state for club notifications
    @State private var clubDeepLinkPlace: PlaceToPlay? = nil
    @State private var clubDeepLinkType: String? = nil // "joinRequest", "members", or "announcement"
    @State private var clubDeepLinkAnnouncementId: String? = nil
    @State private var navigateToClubDeepLink = false

    var body: some View {
        ZStack {
            // Subtle background logo similar to ClientFormView
            if let bg = appLogoImageSwiftUI() {
                bg
                    .resizable()
                    .scaledToFit()
                    .opacity(0.04)
                    .frame(maxWidth: 500)
                    .allowsHitTesting(false)
            }

            List {
                // MARK: - Tournaments Section
                Section(header: Text("Tournaments").font(.subheadline).fontWeight(.semibold)) {
                    NavigationLink {
                        UpcomingTournamentsView()
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        HStack {
                            Image(systemName: "trophy")
                                .foregroundColor(Color("LogoGreen"))
                            Text("Find Upcoming Tournaments")
                                .font(.body)
                        }
                    }

                    NavigationLink {
                        TournamentPartnerView()
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        HStack {
                            Image(systemName: "person.2")
                                .foregroundColor(Color("LogoBlue"))
                            Text("Find a Tournament Partner")
                                .font(.body)
                        }
                    }
                }

                // MARK: - Places to Play Section
                Section(header: Text("Places to Play").font(.subheadline).fontWeight(.semibold)) {
                    NavigationLink {
                        PlacesToPlayView()
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(Color("LogoGreen"))
                            Text("Browse Places")
                                .font(.body)
                        }
                    }

                    NavigationLink {
                        PlayersToPlayWithView()
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(Color("LogoBlue"))
                            Text("Players to Play With")
                                .font(.body)
                        }
                    }

                    if firestore.currentAdditionalTypes.contains(AdditionalUserType.placesToPlayContact.rawValue) {
                        NavigationLink {
                            PlacesToPlayContactView()
                                .environmentObject(firestore)
                        } label: {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundColor(Color("LogoGreen"))
                                Text("Manage Places Contact")
                                    .font(.body)
                            }
                        }
                    }
                }

                // MARK: - My Clubs Section
                Section(header: Text("My Clubs").font(.subheadline).fontWeight(.semibold)) {
                    NavigationLink {
                        MyClubsView()
                            .environmentObject(firestore)
                            .environmentObject(auth)
                            .environmentObject(deepLink)
                    } label: {
                        HStack {
                            Image(systemName: "person.3")
                                .foregroundColor(Color("LogoGreen"))
                            Text("View My Clubs")
                                .font(.body)
                        }
                    }
                }

                // MARK: - Stringing Section
                Section(header: Text("Stringing").font(.subheadline).fontWeight(.semibold)) {
                    NavigationLink {
                        StringingTabView()
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        HStack {
                            Image(systemName: "scissors")
                                .foregroundColor(Color("LogoGreen"))
                            Text("View Stringer Dashboard")
                                .font(.body)
                            Spacer()
                            let activeCount = activeStringingOrdersCount
                            if activeCount > 0 {
                                Text("\(activeCount) active")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    NavigationLink {
                        StringersView()
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            Text("Browse Stringers")
                                .font(.body)
                        }
                    }
                }

                // MARK: - Reviews Section
                Section(header: Text("Reviews").font(.subheadline).fontWeight(.semibold)) {
                    NavigationLink {
                        ReviewsView()
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    } label: {
                        HStack {
                            Image(systemName: "star.bubble")
                                .foregroundColor(Color("LogoBlue"))
                            Text("View My Coaching Reviews")
                                .font(.body)
                            Spacer()
                            let reviewCount = reviewsAboutUser.count
                            if reviewCount > 0 {
                                Text("\(reviewCount)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Fetch data for both sections
            firestore.fetchOrdersForBuyer()
            if firestore.stringers.isEmpty {
                firestore.fetchStringers()
            }
            if let uid = auth.user?.uid {
                // If user is a stringer, fetch their incoming orders
                if let stringer = firestore.stringers.first(where: { $0.id == uid }) {
                    firestore.fetchOrdersForStringer(stringerId: stringer.id)
                }
            }
            // Fetch reviews for coach view
            firestore.fetchAllReviews()
            // Fetch places for club deep links
            firestore.fetchPlacesToPlay()

            // Handle stringing deep link on cold start
            if case .stringing(let orderId) = deepLink.pendingDestination, let orderId = orderId {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    handleStringerOrderDeepLink(orderId: orderId)
                }
            }
            // Handle pending club deep link
            handleClubDeepLink(deepLink.pendingDestination)
        }
        .onChange(of: deepLink.pendingDestination) { _old, destination in
            if case .stringing(let orderId) = destination, let orderId = orderId {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    handleStringerOrderDeepLink(orderId: orderId)
                }
            }
            handleClubDeepLink(destination)
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
        .onChange(of: firestore.placesToPlay) { _, _ in
            if deepLink.pendingDestination != nil {
                handleClubDeepLink(deepLink.pendingDestination)
            }
        }
        .navigationDestination(isPresented: $navigateToDeepLinkedOrder) {
            if let order = deepLinkedOrder {
                let uid = auth.user?.uid ?? ""
                let isStringer = order.stringerId == uid
                StringerOrderDetailView(
                    order: order,
                    stringer: firestore.stringers.first(where: { $0.id == order.stringerId }),
                    isStringerView: isStringer
                )
                .environmentObject(firestore)
            }
        }
        .navigationDestination(isPresented: $navigateToClubDeepLink) {
            if let place = clubDeepLinkPlace {
                if clubDeepLinkType == "joinRequest" {
                    PlacesToPlayContactView()
                        .environmentObject(firestore)
                } else if clubDeepLinkType == "announcement" {
                    ClubAnnouncementsView(
                        place: place,
                        highlightAnnouncementId: clubDeepLinkAnnouncementId
                    )
                    .environmentObject(firestore)
                } else {
                    PlaceDetailView(place: place)
                        .environmentObject(firestore)
                        .environmentObject(auth)
                }
            }
        }
    }

    // MARK: - Computed Properties

    /// Returns the count of active stringing orders (accepted or stringing) for the current user
    private var activeStringingOrdersCount: Int {
        guard let uid = auth.user?.uid else { return 0 }
        guard firestore.stringers.contains(where: { $0.id == uid }) else { return 0 }
        return firestore.stringerIncomingOrders.filter { $0.status == "accepted" || $0.status == "stringing" }.count
    }

    /// Reviews about the current user (as a coach)
    private var reviewsAboutUser: [FirestoreManager.ReviewItem] {
        guard let uid = auth.user?.uid else { return [] }
        return firestore.reviews.filter { $0.coachID == uid }
    }

    /// Handle stringing order deep link — checks both incoming (stringer) and placed (buyer) orders
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
            pendingDeepLinkOrderId = orderId
            firestore.fetchOrdersForBuyer()
            if let uid = auth.user?.uid,
               let stringer = firestore.stringers.first(where: { $0.id == uid }) {
                firestore.fetchOrdersForStringer(stringerId: stringer.id)
            }
        }
    }

    /// Handle club deep link navigation
    private func handleClubDeepLink(_ destination: DeepLinkDestination?) {
        guard let destination = destination else { return }
        switch destination {
        case .clubJoinRequest(let placeId):
            if let place = firestore.placesToPlay.first(where: { $0.id == placeId }) {
                clubDeepLinkPlace = place
                clubDeepLinkType = "joinRequest"
                deepLink.pendingDestination = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navigateToClubDeepLink = true
                }
            } else {
                firestore.fetchPlacesToPlay()
            }
        case .clubMembers(let placeId):
            if let place = firestore.placesToPlay.first(where: { $0.id == placeId }) {
                clubDeepLinkPlace = place
                clubDeepLinkType = "members"
                deepLink.pendingDestination = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navigateToClubDeepLink = true
                }
            } else {
                firestore.fetchPlacesToPlay()
            }
        case .clubAnnouncement(let placeId, let announcementId):
            if let place = firestore.placesToPlay.first(where: { $0.id == placeId }) {
                clubDeepLinkPlace = place
                clubDeepLinkType = "announcement"
                clubDeepLinkAnnouncementId = announcementId
                deepLink.pendingDestination = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navigateToClubDeepLink = true
                }
            } else {
                firestore.fetchPlacesToPlay()
            }
        default:
            break
        }
    }
}

struct CoachHomeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CoachHomeView()
                .environmentObject(FirestoreManager())
                .environmentObject(AuthViewModel())
                .environmentObject(DeepLinkManager.shared)
        }
    }
}
