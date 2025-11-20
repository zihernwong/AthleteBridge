import SwiftUI

struct ClientFormView: View {
    @State private var goals = ""
    @State private var availability = "Morning"
    
    let availabilityOptions = ["Morning", "Afternoon", "Evening"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Your Coaching Goals")) {
                    TextField("e.g. Confidence, Leadership", text: $goals)
                }
                
                Section(header: Text("Preferred Availability")) {
                    Picker("Availability", selection: $availability) {
                        ForEach(availabilityOptions, id: \.self) { option in
                            Text(option)
                        }
                    }
                }
                
                NavigationLink("Find Coaches") {
                    let client = Client(name: "You",
                                        goals: goals.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                        preferredAvailability: availability)
                    
                    MatchResultsView(client: client)
                }
            }
            .navigationTitle("Find a Coach")
        }
    }
}


