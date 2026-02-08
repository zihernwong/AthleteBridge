import SwiftUI

struct ClientFormView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @State private var goals = ""
    // Support multi-select availability
    @State private var selectedAvailability: Set<String> = []
    @State private var searchText: String = ""
    
    let availabilityOptions = ["Morning", "Afternoon", "Evening"]
    
    // Computed suggestions from coach names matching the prefix
    private var suggestions: [String] {
        let typed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard typed.count >= 1 else { return [] }
        let names = firestore.coaches.map { $0.name }
        let filtered = names.filter { $0.lowercased().hasPrefix(typed) }
        return Array(filtered.prefix(6))
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

                    NavigationLink("Find Upcoming Tournaments") {
                        UpcomingTournamentsView()
                            .environmentObject(firestore)
                            .environmentObject(auth)
                    }

                    Section(header: Text("Find a Tournament Partner")) {
                        NavigationLink("Find Partners") {
                            TournamentPartnerView()
                                .environmentObject(firestore)
                                .environmentObject(auth)
                        }
                    }
                }
                .navigationTitle("Find a Coach")
                 .onAppear {
                     // ensure coaches list is loaded so suggestions work
                     if firestore.coaches.isEmpty {
                         firestore.fetchCoaches()
                     }
                     firestore.fetchClients()
                 }
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
    }
}
