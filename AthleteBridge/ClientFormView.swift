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

    var body: some View {
        NavigationView {
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
                        TextField("e.g. Confidence, Leadership", text: $goals)
                    }
                    
                    Section(header: Text("Preferred Availability")) {
                        Text("Preferred Availability")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ChipMultiSelect(items: availabilityOptions, selection: $selectedAvailability)
                    }
                    
                    NavigationLink("Find Coaches") {
                        LazyView {
                            // Fallback to Morning if user didn't select any availability
                            let prefs = selectedAvailability.isEmpty ? ["Morning"] : Array(selectedAvailability)
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
                }
                .navigationTitle("Find a Coach")
                 .onAppear {
                     // ensure coaches list is loaded so suggestions work
                     if firestore.coaches.isEmpty {
                         firestore.fetchCoaches()
                     }
                 }
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
