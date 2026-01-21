import Foundation

struct Coach: Identifiable, Hashable {
    // Use Firestore document id (or Auth UID) as the stable identifier
    let id: String
    let name: String
    let specialties: [String]
    let experienceYears: Int
    let availability: [String] // e.g., "Morning", "Evening"
    let bio: String? // optional biography text
    let hourlyRate: Double? // optional hourly rate in USD
    let photoURLString: String? // optional raw photo path/URL from Firestore
    // Optional meeting preference for coach (e.g., "In-Person" / "Virtual")
    let meetingPreference: String?
    // Optional location info
    let zipCode: String?
    let city: String?
    // Payments map: key is platform (e.g., venmo, paypal), value is username/handle
    let payments: [String: String]?

    init(id: String = UUID().uuidString, name: String, specialties: [String], experienceYears: Int, availability: [String], bio: String? = nil, hourlyRate: Double? = nil, photoURLString: String? = nil, meetingPreference: String? = nil, zipCode: String? = nil, city: String? = nil, payments: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.specialties = specialties
        self.experienceYears = experienceYears
        self.availability = availability
        self.bio = bio
        self.hourlyRate = hourlyRate
        self.photoURLString = photoURLString
        self.meetingPreference = meetingPreference
        self.zipCode = zipCode
        self.city = city
        self.payments = payments
    }
}

struct Client: Identifiable, Hashable {
    // Use Firestore document id (or Auth UID) as the stable identifier
    let id: String
    let name: String
    let goals: [String]
    let preferredAvailability: [String]
    // Optional meeting preference (e.g. "In-Person" / "Virtual")
    let meetingPreference: String?
    // Optional skill level for clients
    let skillLevel: String?
    // Optional location info
    let zipCode: String?
    let city: String?
    // Optional biography text
    let bio: String?

    init(id: String = UUID().uuidString, name: String, goals: [String], preferredAvailability: [String], meetingPreference: String? = nil, skillLevel: String? = nil, zipCode: String? = nil, city: String? = nil, bio: String? = nil) {
        self.id = id
        self.name = name
        self.goals = goals
        self.preferredAvailability = preferredAvailability
        self.meetingPreference = meetingPreference
        self.skillLevel = skillLevel
        self.zipCode = zipCode
        self.city = city
        self.bio = bio
    }
}
