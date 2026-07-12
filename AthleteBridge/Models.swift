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

    /// Feature gating by subscription tier.
    /// Free coaches are restricted from premium features; Plus and Pro have full access.
    func hasAccess(to feature: String) -> Bool {
        switch self {
        case .free:
            // Features locked on the free tier
            let lockedFeatures: Set<String> = ["paymentSummary"]
            return !lockedFeatures.contains(feature)
        case .plus, .pro:
            return true
        }
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
    // Places to play this coach is associated with (array of PlaceToPlay document IDs)
    let linkedPlaceIds: [String]
    // Client cancellations within this many hours of a session forfeit the deposit (0 = no policy)
    let cancellationWindowHours: Int

    init(id: String = UUID().uuidString, name: String, specialties: [String], experienceYears: Int, availability: [String], bio: String? = nil, hourlyRate: Double? = nil, photoURLString: String? = nil, meetingPreference: String? = nil, zipCode: String? = nil, city: String? = nil, payments: [String: String]? = nil, rateRange: [Double]? = nil, tournamentSoftwareLink: String? = nil, subscriptionTier: CoachTier = .free, phoneVerified: Bool = false, linkedPlaceIds: [String] = [], cancellationWindowHours: Int = 0) {
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
        self.linkedPlaceIds = linkedPlaceIds
        self.cancellationWindowHours = max(0, cancellationWindowHours)
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

// MARK: - Country Codes for Phone Verification

enum CountryCode: String, CaseIterable, Identifiable {
    case us, ca, gb, au, nz, my, sg, ph, hk, cn, jp, kr, `in`, id, th, vn, de, fr, es, it, br, mx

    var id: String { rawValue }

    var dialCode: String {
        switch self {
        case .us: return "+1"
        case .ca: return "+1"
        case .gb: return "+44"
        case .au: return "+61"
        case .nz: return "+64"
        case .my: return "+60"
        case .sg: return "+65"
        case .ph: return "+63"
        case .hk: return "+852"
        case .cn: return "+86"
        case .jp: return "+81"
        case .kr: return "+82"
        case .in: return "+91"
        case .id: return "+62"
        case .th: return "+66"
        case .vn: return "+84"
        case .de: return "+49"
        case .fr: return "+33"
        case .es: return "+34"
        case .it: return "+39"
        case .br: return "+55"
        case .mx: return "+52"
        }
    }

    var flag: String {
        switch self {
        case .us: return "🇺🇸"
        case .ca: return "🇨🇦"
        case .gb: return "🇬🇧"
        case .au: return "🇦🇺"
        case .nz: return "🇳🇿"
        case .my: return "🇲🇾"
        case .sg: return "🇸🇬"
        case .ph: return "🇵🇭"
        case .hk: return "🇭🇰"
        case .cn: return "🇨🇳"
        case .jp: return "🇯🇵"
        case .kr: return "🇰🇷"
        case .in: return "🇮🇳"
        case .id: return "🇮🇩"
        case .th: return "🇹🇭"
        case .vn: return "🇻🇳"
        case .de: return "🇩🇪"
        case .fr: return "🇫🇷"
        case .es: return "🇪🇸"
        case .it: return "🇮🇹"
        case .br: return "🇧🇷"
        case .mx: return "🇲🇽"
        }
    }

    var name: String {
        switch self {
        case .us: return "United States"
        case .ca: return "Canada"
        case .gb: return "United Kingdom"
        case .au: return "Australia"
        case .nz: return "New Zealand"
        case .my: return "Malaysia"
        case .sg: return "Singapore"
        case .ph: return "Philippines"
        case .hk: return "Hong Kong"
        case .cn: return "China"
        case .jp: return "Japan"
        case .kr: return "South Korea"
        case .in: return "India"
        case .id: return "Indonesia"
        case .th: return "Thailand"
        case .vn: return "Vietnam"
        case .de: return "Germany"
        case .fr: return "France"
        case .es: return "Spain"
        case .it: return "Italy"
        case .br: return "Brazil"
        case .mx: return "Mexico"
        }
    }
}

// MARK: - Additional User Types

/// Additional user types that can be combined (not mutually exclusive like COACH/CLIENT)
enum AdditionalUserType: String, CaseIterable, Identifiable {
    case stringer = "Stringer"
    case tournamentOrganizer = "TournamentOrganizer"
    case placesToPlayContact = "PlacesToPlayContact"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stringer: return "Badminton Stringer"
        case .tournamentOrganizer: return "Tournament Organizer"
        case .placesToPlayContact: return "Club Admin"
        }
    }

    var badgeColor: Color {
        switch self {
        case .stringer: return .orange
        case .tournamentOrganizer: return .purple
        case .placesToPlayContact: return .green
        }
    }

    var iconName: String {
        switch self {
        case .stringer: return "scissors"
        case .tournamentOrganizer: return "trophy"
        case .placesToPlayContact: return "location.fill"
        }
    }
}

/// Small colored chip badge for additional user types.
struct AdditionalTypeBadge: View {
    let type: AdditionalUserType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.iconName)
                .font(.caption2)
            Text(type.displayName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(type.badgeColor.opacity(0.15))
        .foregroundColor(type.badgeColor)
        .cornerRadius(12)
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

struct ClubAnnouncement: Identifiable, Hashable {
    let id: String          // Firestore doc ID
    let placeId: String
    let title: String
    let body: String
    let senderName: String
    let createdBy: String   // sender UID
    let createdAt: Date
}

struct ClubMember: Identifiable, Hashable {
    let id: String      // user UID
    let name: String
    let joinedAt: Date
}

struct PlaceToPlay: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    /// Weekly schedule: day name -> time range string (e.g. "6:00 AM - 9:00 PM")
    let playingTimes: [String: String]
    let pricePerSession: String
    /// Club profile picture uploaded by an admin (falls back to map imagery in UI)
    let photoURL: String?
    let createdBy: String
    /// Legacy single-contact fields (still written for the first admin so the
    /// Android app keeps working). Prefer `admins` for all new logic.
    let contactUid: String?
    let contactName: String?
    /// Club admins (formerly "places to play contacts"). A club can have several.
    let admins: [ClubMember]
    let members: [ClubMember]
    let pendingMembers: [ClubMember]

    var adminIds: [String] { admins.map { $0.id } }

    func isAdmin(_ uid: String) -> Bool {
        !uid.isEmpty && adminIds.contains(uid)
    }
}

struct PlayerToPlayWith: Identifiable, Hashable {
    let id: String          // Firestore doc ID (= user's UID)
    let name: String
    let skillLevel: String
    let city: String
    let availability: [String]
    let connectedVenueIds: [String]
    let createdBy: String
    let createdAt: Date
}

struct StringerLocation: Identifiable, Hashable {
    let id: String       // UUID string
    let name: String     // display name from search result
    let address: String  // full address string
    let latitude: Double
    let longitude: Double
}

struct BadmintonStringer: Identifiable, Hashable {
    let id: String
    let name: String
    let meetupLocationNames: [String]       // legacy: plain name strings
    let meetupLocations: [StringerLocation] // rich locations with coordinates
    /// Maps string name to additional cost (e.g. "BG65" -> "$5")
    let stringsOffered: [String: String]
    let laborCost: String // labor price per racket (e.g. "$10")
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
    let laborCost: String? // labor price per racket
    let orderTotal: String? // labor + string cost
    let tension: Int
    let timelinePreference: String
    let createdBy: String
    let createdAt: Date
    let status: String // "placed", "accepted", "stringing", "completed", "declined"
    let buyerName: String
    // Timestamp per status stage, written on every status change (shared with Android)
    var statusHistory: [String: Date] = [:]

    /// Ordered pipeline stages for the progress timeline.
    static let timelineStages = ["placed", "accepted", "stringing", "ready_for_pickup", "picked_up"]

    func stageTimestamp(_ stage: String) -> Date? {
        if stage == "placed" { return statusHistory[stage] ?? createdAt }
        return statusHistory[stage]
    }

    func isStageReached(_ stage: String) -> Bool {
        let current = status.lowercased()
        guard let stageIdx = Self.timelineStages.firstIndex(of: stage) else { return false }
        if let currentIdx = Self.timelineStages.firstIndex(of: current) {
            return stageIdx <= currentIdx
        }
        return current == "completed"
    }
}

// MARK: - Signup Events

struct SignupEventSignup: Identifiable, Hashable {
    let id: String          // map key
    let name: String
    let email: String
    let userId: String?     // nil for web signups
    let signedUpAt: Date
    let paid: Bool
}

struct SignupEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let eventDate: Date
    let location: String
    let placeId: String      // linked PlaceToPlay document ID
    let placeName: String    // denormalized place name for display
    let maxSignups: Int
    let signupCount: Int
    let createdBy: String
    let signups: [SignupEventSignup]
    // People waiting for a spot, promoted first-in-first-out when someone drops out
    var waitlist: [SignupEventSignup] = []

    func isWaitlisted(userId: String) -> Bool {
        waitlist.contains { $0.userId == userId }
    }
    /// 1-based position in the waitlist queue, or nil if not waitlisted.
    func waitlistPosition(userId: String) -> Int? {
        let sorted = waitlist.sorted { $0.signedUpAt < $1.signedUpAt }
        guard let idx = sorted.firstIndex(where: { $0.userId == userId }) else { return nil }
        return idx + 1
    }
    var spotsRemaining: Int { max(0, maxSignups - signupCount) }
    var isFull: Bool { signupCount >= maxSignups }
    var shareURL: URL? { URL(string: "https://athletebridge-63176.web.app/signup/?event=\(id)") }
}
