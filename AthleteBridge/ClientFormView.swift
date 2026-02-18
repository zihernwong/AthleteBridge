import SwiftUI

struct ClientFormView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var deepLink: DeepLinkManager
    @State private var goals = ""
    // Support multi-select availability
    @State private var selectedAvailability: Set<String> = []
    @State private var searchText: String = ""

    // Deep link state for stringing orders
    @State private var pendingDeepLinkOrderId: String? = nil
    @State private var deepLinkedOrder: StringerOrder? = nil
    @State private var navigateToDeepLinkedOrder = false

    // Deep link state for club notifications
    @State private var clubDeepLinkPlace: PlaceToPlay? = nil
    @State private var clubDeepLinkType: String? = nil // "joinRequest", "members", or "announcement"
    @State private var clubDeepLinkAnnouncementId: String? = nil
    @State private var navigateToClubDeepLink = false
    
    let availabilityOptions = ["Morning", "Afternoon", "Evening"]
    
    // Computed suggestions from coach names matching the prefix
    private var suggestions: [String] {
        let typed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard typed.count >= 1 else { return [] }
        let names = firestore.coaches.map { $0.name }
        let filtered = names.filter { $0.lowercased().hasPrefix(typed) }
        return Array(filtered.prefix(6))
    }

    /// Returns the count of active stringing orders (accepted or stringing) for the current user
    private var activeStringingOrdersCount: Int {
        guard let uid = auth.user?.uid else { return 0 }
        guard firestore.stringers.contains(where: { $0.id == uid }) else { return 0 }
        return firestore.stringerIncomingOrders.filter { $0.status == "accepted" || $0.status == "stringing" }.count
    }

    // Computed suggestions for improvement areas based on coaches' specialties
    private var goalSuggestions: [String] {
        // Get the last item being typed (after the last comma)
        let components = goals.split(separator: ",", omittingEmptySubsequences: false)
        guard let lastComponent = components.last else { return [] }
        let typed = lastComponent.trimmingCharacters(in: .whitespaces).lowercased()
        guard typed.count >= 1 else { return [] }

        // Get already selected goals to exclude from suggestions
        let alreadySelected = Set(components.dropLast().map { $0.trimmingCharacters(in: .whitespaces).lowercased() })

        // Collect all unique specialties from coaches
        let allSpecialties = Set(firestore.coaches.flatMap { $0.specialties })

        // Filter specialties that match the typed text and aren't already selected
        let filtered = allSpecialties.filter { specialty in
            let lowercased = specialty.lowercased()
            return lowercased.contains(typed) && !alreadySelected.contains(lowercased)
        }

        return Array(filtered.sorted().prefix(6))
    }

    var body: some View {
            ZStack {
                if let bg = appLogoImageSwiftUI() {
                    bg
                        .resizable()
                        .scaledToFit()
                        .opacity(0.04)
                        .frame(maxWidth: 500)
                        .allowsHitTesting(false)
                }

                Form {
                    Section(header: Text("Search by coach name (optional)")) {
                        VStack(spacing: 6) {
                            TextField("Search coaches by name", text: $searchText)
                                .textFieldStyle(.roundedBorder)

                            if !suggestions.isEmpty {
                                // suggestion chips
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(suggestions, id: \.self) { s in
                                            Button(action: {
                                                searchText = s
                                                // dismiss keyboard
                                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                            }) {
                                                Text(s)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(Color(UIColor.secondarySystemBackground))
                                                    .cornerRadius(16)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }

                    Section(header: Text("Desired Improvement Areas")) {
                        VStack(spacing: 6) {
                            TextField("e.g. Confidence, Leadership", text: $goals)
                                .textFieldStyle(.roundedBorder)

                            if !goalSuggestions.isEmpty {
                                // suggestion chips for improvement areas
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(goalSuggestions, id: \.self) { suggestion in
                                            Button(action: {
                                                // Replace the last partial entry with the selected suggestion
                                                var components = goals.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
                                                if components.isEmpty {
                                                    goals = suggestion
                                                } else {
                                                    components[components.count - 1] = " " + suggestion
                                                    goals = components.joined(separator: ",")
                                                }
                                                // Add comma for next entry
                                                goals += ", "
                                                // dismiss keyboard
                                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                            }) {
                                                Text(suggestion)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(Color(UIColor.secondarySystemBackground))
                                                    .cornerRadius(16)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    
                    Section(header: Text("Preferred Availability")) {
                        Text("Preferred Availability")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        AvailabilityChipSelect(items: availabilityOptions, selection: $selectedAvailability)
                    }
                    
                    NavigationLink("Find Coaches") {
                        LazyView {
                            // Only filter by availability if user explicitly selected preferences
                            let prefs = Array(selectedAvailability)
                            let client = Client(name: "You",
                                                goals: goals.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                                preferredAvailability: prefs)

                            // Determine whether the signed-in user should be treated as a coach.
                            let isCoachUser: Bool = {
                                if let t = firestore.currentUserType?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), t == "COACH" { return true }
                                if let coach = firestore.currentCoach, coach.id == auth.user?.uid { return true }
                                if let uid = auth.user?.uid, firestore.coaches.contains(where: { $0.id == uid }) { return true }
                                return false
                            }()

                            if isCoachUser {
                                CoachLogoView()
                            } else {
                                MatchResultsView(client: client, searchQuery: searchText)
                            }
                        }
                     }

                    Section(header: Text("Tournaments")) {
                        NavigationLink {
                            UpcomingTournamentsView()
                                .environmentObject(firestore)
                                .environmentObject(auth)
                        } label: {
                            HStack {
                                Image(systemName: "trophy")
                                    .foregroundColor(Color("LogoGreen"))
                                Text("Find Upcoming Tournaments")
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
                            }
                        }
                    }

                    Section(header: Text("My Clubs")) {
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
                            }
                        }
                    }

                    Section(header: Text("Places to Play")) {
                        NavigationLink {
                            PlacesToPlayView()
                                .environmentObject(firestore)
                                .environmentObject(auth)
                        } label: {
                            HStack {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(Color("LogoGreen"))
                                Text("Browse Places")
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
                                }
                            }
                        }
                    }

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

                    Section(header: Text("Reviews")) {
                        NavigationLink {
                            ReviewsView()
                                .environmentObject(firestore)
                                .environmentObject(auth)
                        } label: {
                            HStack {
                                Image(systemName: "star.bubble")
                                    .foregroundColor(Color("LogoGreen"))
                                Text("Write & View Reviews")
                            }
                        }
                    }
                }
                .navigationTitle("Find a Coach")
                .navigationBarTitleDisplayMode(.inline)
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
                 .onAppear {
                     // ensure coaches list is loaded so suggestions work
                     if firestore.coaches.isEmpty {
                         firestore.fetchCoaches()
                     }
                     firestore.fetchClients()
                     firestore.fetchOrdersForBuyer()
                     if firestore.stringers.isEmpty {
                         firestore.fetchStringers()
                     }
                     if let uid = auth.user?.uid,
                        let stringer = firestore.stringers.first(where: { $0.id == uid }) {
                         firestore.fetchOrdersForStringer(stringerId: stringer.id)
                     }
                     // Fetch places for club deep links
                     firestore.fetchPlacesToPlay()

                     // Handle stringing deep link
                     if case .stringing(let orderId) = deepLink.pendingDestination, let orderId = orderId {
                         DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                             handleStringerOrderDeepLink(orderId: orderId)
                         }
                     }
                     // Handle club deep link
                     handleClubDeepLink(deepLink.pendingDestination)
                 }
                 .onChange(of: deepLink.pendingDestination) { _old, destination in
                     if case .stringing(let orderId) = destination, let orderId = orderId {
                         DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                             handleStringerOrderDeepLink(orderId: orderId)
                         }
                     }
                     // Also handle club deep links
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
     }

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

// Simple logo page shown to coach users in place of the matching UI
struct CoachLogoView: View {
    var body: some View {
        VStack {
            Spacer()
            if let img = appLogoImageSwiftUI() {
                img.resizable().scaledToFit().frame(maxWidth: 300).padding()
            } else {
                Image("AthleteBridgeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300)
                    .padding()
            }
            Text("AthleteBridge")
                .font(.title)
                .bold()
                .padding(.bottom, 40)
            Spacer()
        }
        .navigationTitle("AthleteBridge")
        .navigationBarTitleDisplayMode(.inline)
    }
}
