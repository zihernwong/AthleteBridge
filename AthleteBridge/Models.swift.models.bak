import Foundation

struct Coach: Identifiable, Hashable {
    // Use Firestore document id (or Auth UID) as the stable identifier
    let id: String
    let name: String
    let specialties: [String]
    let experienceYears: Int
    let availability: [String] // e.g., "Morning", "Evening"

    init(id: String = UUID().uuidString, name: String, specialties: [String], experienceYears: Int, availability: [String]) {
        self.id = id
        self.name = name
        self.specialties = specialties
        self.experienceYears = experienceYears
        self.availability = availability
    }
}

struct Client: Identifiable, Hashable {
    // Use Firestore document id (or Auth UID) as the stable identifier
    let id: String
    let name: String
    let goals: [String]
    let preferredAvailability: [String]

    init(id: String = UUID().uuidString, name: String, goals: [String], preferredAvailability: [String]) {
        self.id = id
        self.name = name
        self.goals = goals
        self.preferredAvailability = preferredAvailability
    }
}
