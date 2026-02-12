import Foundation

enum CoachTier: String, CaseIterable {
    case free = "free"
    case plus = "plus"
    case pro = "pro"

    var displayName: String {
        switch self {
        case .free: return "Coach Free"
        case .plus: return "Coach Plus"
        case .pro: return "Coach Pro"
        }
    }

    /// Placeholder for future feature gating. Returns true for all features currently.
    func hasAccess(to feature: String) -> Bool {
        return true
    }
}

struct Coach: Identifiable, Hashable {
    // Use Firestore document id (or Auth UID) as the stable identifier
    let id: String
    let name: String
    let specialties: [String]
    let experienceYears: Int
    let availability: [String] // e.g., "Morning", "Evening"
    let bio: String? // optional biography text
    let hourlyRate: Double? // optional hourly rate in USD
    let tournamentSoftwareLink: String?
    let photoURLString: String? // optional raw photo path/URL from Firestore
    // Optional meeting preference for coach (e.g., "In-Person" / "Virtual")
    let meetingPreference: String?
    // Optional location info
    let zipCode: String?
    let city: String?
    // Payments map: key is platform (e.g., venmo, paypal), value is username/handle
    let payments: [String: String]?
    // New: optional rate range [lower, upper]
    let rateRange: [Double]?
    // Subscription tier (synced from Stripe via Cloud Function)
    let subscriptionTier: CoachTier
    // Whether the coach has verified their phone number
    let phoneVerified: Bool

    init(id: String = UUID().uuidString, name: String, specialties: [String], experienceYears: Int, availability: [String], bio: String? = nil, hourlyRate: Double? = nil, photoURLString: String? = nil, meetingPreference: String? = nil, zipCode: String? = nil, city: String? = nil, payments: [String: String]? = nil, rateRange: [Double]? = nil, tournamentSoftwareLink: String? = nil, subscriptionTier: CoachTier = .free, phoneVerified: Bool = false) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespaces)
        self.specialties = specialties.map { $0.trimmingCharacters(in: .whitespaces) }
        self.experienceYears = max(0, experienceYears) // Clamp negative values to 0
        self.availability = availability.map { $0.trimmingCharacters(in: .whitespaces) }
        self.bio = bio?.trimmingCharacters(in: .whitespaces)
        self.hourlyRate = hourlyRate.map { max(0, $0) } // Clamp negative values to 0
        self.photoURLString = photoURLString
        self.meetingPreference = meetingPreference?.trimmingCharacters(in: .whitespaces)
        self.zipCode = zipCode?.trimmingCharacters(in: .whitespaces)
        self.city = city?.trimmingCharacters(in: .whitespaces)
        self.payments = payments
        self.tournamentSoftwareLink = tournamentSoftwareLink
        self.subscriptionTier = subscriptionTier
        self.phoneVerified = phoneVerified
        // Normalize rate range: ensure min <= max, clamp negatives to 0
        if let range = rateRange, range.count >= 2 {
            let lower = max(0, range[0])
            let upper = max(0, range[1])
            self.rateRange = [min(lower, upper), max(lower, upper)]
        } else if let range = rateRange, range.count == 1 {
            self.rateRange = [max(0, range[0])]
        } else {
            self.rateRange = rateRange
        }
    }

    /// Returns true if the coach has a valid, non-empty name
    var hasValidName: Bool {
        !name.isEmpty
    }

    /// Returns the minimum rate from rateRange, or hourlyRate as fallback
    var minimumRate: Double? {
        rateRange?.first ?? hourlyRate
    }

    /// Returns the maximum rate from rateRange, or hourlyRate as fallback
    var maximumRate: Double? {
        if let range = rateRange, range.count >= 2 {
            return range[1]
        }
        return rateRange?.first ?? hourlyRate
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
    let tournamentSoftwareLink: String?
    // Whether the client has verified their phone number
    let phoneVerified: Bool

    init(id: String = UUID().uuidString,
         name: String,
         goals: [String],
         preferredAvailability: [String],
         meetingPreference: String? = nil,
         skillLevel: String? = nil,
         zipCode: String? = nil,
         city: String? = nil,
         bio: String? = nil,
         tournamentSoftwareLink: String? = nil,
         phoneVerified: Bool = false) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespaces)
        self.goals = goals.map { $0.trimmingCharacters(in: .whitespaces) }
        self.preferredAvailability = preferredAvailability.map { $0.trimmingCharacters(in: .whitespaces) }
        self.meetingPreference = meetingPreference?.trimmingCharacters(in: .whitespaces)
        self.skillLevel = skillLevel?.trimmingCharacters(in: .whitespaces)
        self.zipCode = zipCode?.trimmingCharacters(in: .whitespaces)
        self.city = city?.trimmingCharacters(in: .whitespaces)
        self.bio = bio?.trimmingCharacters(in: .whitespaces)
        self.tournamentSoftwareLink = tournamentSoftwareLink
        self.phoneVerified = phoneVerified
    }

    /// Returns true if the client has a valid, non-empty name
    var hasValidName: Bool {
        !name.isEmpty
    }
}

// MARK: - Verified Badge

import SwiftUI

/// Small blue checkmark badge shown next to names of phone-verified users.
struct VerifiedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .foregroundColor(.blue)
            .font(.caption)
    }
}

struct TournamentParticipantInfo: Hashable {
    let gender: String
    let events: [String]
    let skillLevels: [String]
}

struct Tournament: Identifiable, Hashable {
    let id: String
    let name: String
    let startDate: Date
    let endDate: Date
    let location: String
    let createdBy: String
    let signupLink: String?
    let participants: [String: TournamentParticipantInfo]

    init(id: String = UUID().uuidString, name: String, startDate: Date, endDate: Date, location: String, createdBy: String = "", signupLink: String? = nil, participants: [String: TournamentParticipantInfo] = [:]) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespaces)
        self.startDate = startDate
        self.endDate = endDate
        self.location = location.trimmingCharacters(in: .whitespaces)
        self.createdBy = createdBy
        self.signupLink = signupLink
        self.participants = participants
    }
}

struct PlaceToPlay: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    /// Weekly schedule: day name -> time range string (e.g. "6:00 AM - 9:00 PM")
    let playingTimes: [String: String]
    let pricePerSession: String
    let createdBy: String
}

struct BadmintonStringer: Identifiable, Hashable {
    let id: String
    let name: String
    let meetupLocationNames: [String]
    /// Maps string name to additional cost (e.g. "BG65" -> "$5")
    let stringsOffered: [String: String]
    let createdBy: String
}

struct StringerReview: Identifiable, Hashable {
    let id: String
    let stringerId: String
    let reviewerName: String
    let rating: Int // 1-5
    let comment: String
    let createdBy: String
    let createdAt: Date
}

struct StringerOrder: Identifiable, Hashable {
    let id: String
    let stringerId: String
    let racketName: String
    let hasOwnString: Bool
    let selectedString: String? // nil if hasOwnString
    let stringCost: String? // cost for selected string
    let tension: Int
    let timelinePreference: String
    let createdBy: String
    let createdAt: Date
    let status: String // "placed", "accepted", "stringing", "completed", "declined"
    let buyerName: String
}
