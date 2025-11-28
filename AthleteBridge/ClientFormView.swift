import SwiftUI

struct ClientFormView: View {
    @EnvironmentObject var firestore: FirestoreManager
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
                        // Fallback to Morning if user didn't select any availability
                        let prefs = selectedAvailability.isEmpty ? ["Morning"] : Array(selectedAvailability)
                        let client = Client(name: "You",
                                            goals: goals.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                            preferredAvailability: prefs)
                        
                        MatchResultsView(client: client, searchQuery: searchText)
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
