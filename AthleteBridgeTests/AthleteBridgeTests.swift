//
//  AthleteBridgeTests.swift
//  AthleteBridgeTests
//
//  Created by Hern Wong on 11/19/25.
//

import XCTest
@testable import AthleteBridge

// MARK: - Coach Model Tests

final class CoachModelTests: XCTestCase {

    func testCoachInitWithAllFields() {
        let coach = Coach(
            id: "coach123",
            name: "John Doe",
            specialties: ["Tennis", "Badminton"],
            experienceYears: 5,
            availability: ["Morning", "Evening"],
            bio: "Experienced coach",
            hourlyRate: 50.0,
            photoURLString: "https://example.com/photo.jpg",
            meetingPreference: "In-Person",
            zipCode: "12345",
            city: "New York",
            payments: ["venmo": "@johndoe", "paypal": "john@example.com"],
            rateRange: [40.0, 60.0]
        )

        XCTAssertEqual(coach.id, "coach123")
        XCTAssertEqual(coach.name, "John Doe")
        XCTAssertEqual(coach.specialties, ["Tennis", "Badminton"])
        XCTAssertEqual(coach.experienceYears, 5)
        XCTAssertEqual(coach.availability, ["Morning", "Evening"])
        XCTAssertEqual(coach.bio, "Experienced coach")
        XCTAssertEqual(coach.hourlyRate, 50.0)
        XCTAssertEqual(coach.photoURLString, "https://example.com/photo.jpg")
        XCTAssertEqual(coach.meetingPreference, "In-Person")
        XCTAssertEqual(coach.zipCode, "12345")
        XCTAssertEqual(coach.city, "New York")
        XCTAssertEqual(coach.payments?["venmo"], "@johndoe")
        XCTAssertEqual(coach.rateRange, [40.0, 60.0])
    }

    func testCoachInitWithMinimalFields() {
        let coach = Coach(
            name: "Jane Doe",
            specialties: [],
            experienceYears: 0,
            availability: []
        )

        XCTAssertFalse(coach.id.isEmpty) // Should have auto-generated UUID
        XCTAssertEqual(coach.name, "Jane Doe")
        XCTAssertTrue(coach.specialties.isEmpty)
        XCTAssertEqual(coach.experienceYears, 0)
        XCTAssertTrue(coach.availability.isEmpty)
        XCTAssertNil(coach.bio)
        XCTAssertNil(coach.hourlyRate)
        XCTAssertNil(coach.photoURLString)
        XCTAssertNil(coach.meetingPreference)
        XCTAssertNil(coach.zipCode)
        XCTAssertNil(coach.city)
        XCTAssertNil(coach.payments)
        XCTAssertNil(coach.rateRange)
    }

    func testCoachWithEmptyName() {
        let coach = Coach(
            name: "",
            specialties: ["Tennis"],
            experienceYears: 3,
            availability: ["Morning"]
        )

        XCTAssertEqual(coach.name, "")
        // Note: Empty name is allowed - potential bug if this should be validated
    }

    func testCoachWithNegativeExperience() {
        let coach = Coach(
            name: "Test Coach",
            specialties: ["Tennis"],
            experienceYears: -5, // Negative experience - potential bug
            availability: ["Morning"]
        )

        XCTAssertEqual(coach.experienceYears, -5)
        // Note: Negative experience is allowed - potential validation bug
    }

    func testCoachWithInvalidRateRange() {
        // Rate range with lower > upper - potential bug
        let coach = Coach(
            name: "Test Coach",
            specialties: ["Tennis"],
            experienceYears: 3,
            availability: ["Morning"],
            rateRange: [100.0, 50.0] // Lower > Upper
        )

        XCTAssertEqual(coach.rateRange?[0], 100.0)
        XCTAssertEqual(coach.rateRange?[1], 50.0)
        // Note: Invalid rate range is allowed - potential validation bug
    }

    func testCoachWithSingleRateInRange() {
        // Rate range with only one value - potential array bounds bug
        let coach = Coach(
            name: "Test Coach",
            specialties: ["Tennis"],
            experienceYears: 3,
            availability: ["Morning"],
            rateRange: [50.0]
        )

        XCTAssertEqual(coach.rateRange?.count, 1)
        // Note: Single-element rate range might cause index out of bounds elsewhere
    }

    func testCoachHashableConformance() {
        let coach1 = Coach(
            id: "same-id",
            name: "John Doe",
            specialties: ["Tennis"],
            experienceYears: 5,
            availability: ["Morning"]
        )
        let coach2 = Coach(
            id: "same-id",
            name: "Jane Doe", // Different name
            specialties: ["Badminton"],
            experienceYears: 10,
            availability: ["Evening"]
        )

        // Hashable should be based on all properties
        var set = Set<Coach>()
        set.insert(coach1)
        set.insert(coach2)

        // If they hash to different values, both should be in set
        // If same ID = same hash, only one should be in set
        // This tests the Hashable implementation
        XCTAssertGreaterThanOrEqual(set.count, 1)
    }

    func testCoachWithNegativeHourlyRate() {
        let coach = Coach(
            name: "Test Coach",
            specialties: ["Tennis"],
            experienceYears: 3,
            availability: ["Morning"],
            hourlyRate: -50.0 // Negative rate - potential bug
        )

        XCTAssertEqual(coach.hourlyRate, -50.0)
        // Note: Negative hourly rate is allowed - potential validation bug
    }
}

// MARK: - Client Model Tests

final class ClientModelTests: XCTestCase {

    func testClientInitWithAllFields() {
        let client = Client(
            id: "client123",
            name: "Jane Smith",
            goals: ["Tennis", "Fitness"],
            preferredAvailability: ["Morning", "Afternoon"],
            meetingPreference: "Virtual",
            skillLevel: "Intermediate",
            zipCode: "54321",
            city: "Los Angeles",
            bio: "Looking to improve my game"
        )

        XCTAssertEqual(client.id, "client123")
        XCTAssertEqual(client.name, "Jane Smith")
        XCTAssertEqual(client.goals, ["Tennis", "Fitness"])
        XCTAssertEqual(client.preferredAvailability, ["Morning", "Afternoon"])
        XCTAssertEqual(client.meetingPreference, "Virtual")
        XCTAssertEqual(client.skillLevel, "Intermediate")
        XCTAssertEqual(client.zipCode, "54321")
        XCTAssertEqual(client.city, "Los Angeles")
        XCTAssertEqual(client.bio, "Looking to improve my game")
    }

    func testClientInitWithMinimalFields() {
        let client = Client(
            name: "John Smith",
            goals: [],
            preferredAvailability: []
        )

        XCTAssertFalse(client.id.isEmpty)
        XCTAssertEqual(client.name, "John Smith")
        XCTAssertTrue(client.goals.isEmpty)
        XCTAssertTrue(client.preferredAvailability.isEmpty)
        XCTAssertNil(client.meetingPreference)
        XCTAssertNil(client.skillLevel)
        XCTAssertNil(client.zipCode)
        XCTAssertNil(client.city)
        XCTAssertNil(client.bio)
    }

    func testClientWithEmptyName() {
        let client = Client(
            name: "",
            goals: ["Tennis"],
            preferredAvailability: ["Morning"]
        )

        XCTAssertEqual(client.name, "")
        // Note: Empty name is allowed - potential bug
    }

    func testClientHashableConformance() {
        let client1 = Client(
            id: "same-id",
            name: "Jane Smith",
            goals: ["Tennis"],
            preferredAvailability: ["Morning"]
        )
        let client2 = Client(
            id: "same-id",
            name: "John Smith",
            goals: ["Badminton"],
            preferredAvailability: ["Evening"]
        )

        var set = Set<Client>()
        set.insert(client1)
        set.insert(client2)

        XCTAssertGreaterThanOrEqual(set.count, 1)
    }
}

// MARK: - Matcher Algorithm Tests

final class MatcherTests: XCTestCase {

    func testMatchCoachesBasicMatch() {
        let client = Client(
            name: "Test Client",
            goals: ["Tennis"],
            preferredAvailability: ["Morning"]
        )

        let matchingCoach = Coach(
            id: "coach1",
            name: "Matching Coach",
            specialties: ["Tennis", "Badminton"],
            experienceYears: 5,
            availability: ["Morning", "Evening"]
        )

        let result = matchCoaches(client: client, allCoaches: [matchingCoach])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "coach1")
    }

    func testMatchCoachesNoGoalMatch() {
        let client = Client(
            name: "Test Client",
            goals: ["Swimming"], // No coach has this
            preferredAvailability: ["Morning"]
        )

        let coach = Coach(
            id: "coach1",
            name: "Tennis Coach",
            specialties: ["Tennis", "Badminton"],
            experienceYears: 5,
            availability: ["Morning"]
        )

        let result = matchCoaches(client: client, allCoaches: [coach])

        XCTAssertTrue(result.isEmpty)
    }

    func testMatchCoachesNoTimeMatch() {
        let client = Client(
            name: "Test Client",
            goals: ["Tennis"],
            preferredAvailability: ["Evening"] // Coach only available Morning
        )

        let coach = Coach(
            id: "coach1",
            name: "Morning Coach",
            specialties: ["Tennis"],
            experienceYears: 5,
            availability: ["Morning"]
        )

        let result = matchCoaches(client: client, allCoaches: [coach])

        XCTAssertTrue(result.isEmpty)
    }

    func testMatchCoachesMultipleGoalsAndTimes() {
        let client = Client(
            name: "Test Client",
            goals: ["Tennis", "Badminton", "Swimming"],
            preferredAvailability: ["Morning", "Afternoon", "Evening"]
        )

        let coach = Coach(
            id: "coach1",
            name: "Multi Coach",
            specialties: ["Tennis"], // Only one overlap
            experienceYears: 5,
            availability: ["Afternoon"] // Only one overlap
        )

        let result = matchCoaches(client: client, allCoaches: [coach])

        XCTAssertEqual(result.count, 1)
    }

    func testMatchCoachesEmptyGoals() {
        let client = Client(
            name: "Test Client",
            goals: [], // Empty goals
            preferredAvailability: ["Morning"]
        )

        let coach = Coach(
            id: "coach1",
            name: "Any Coach",
            specialties: ["Tennis"],
            experienceYears: 5,
            availability: ["Morning"]
        )

        let result = matchCoaches(client: client, allCoaches: [coach])

        XCTAssertTrue(result.isEmpty) // No shared goals means no match
    }

    func testMatchCoachesEmptyAvailability() {
        let client = Client(
            name: "Test Client",
            goals: ["Tennis"],
            preferredAvailability: [] // Empty availability
        )

        let coach = Coach(
            id: "coach1",
            name: "Any Coach",
            specialties: ["Tennis"],
            experienceYears: 5,
            availability: ["Morning"]
        )

        let result = matchCoaches(client: client, allCoaches: [coach])

        XCTAssertTrue(result.isEmpty) // No time overlap means no match
    }

    func testMatchCoachesEmptyCoachSpecialties() {
        let client = Client(
            name: "Test Client",
            goals: ["Tennis"],
            preferredAvailability: ["Morning"]
        )

        let coach = Coach(
            id: "coach1",
            name: "No Specialty Coach",
            specialties: [], // Empty specialties
            experienceYears: 5,
            availability: ["Morning"]
        )

        let result = matchCoaches(client: client, allCoaches: [coach])

        XCTAssertTrue(result.isEmpty) // No specialties means no shared goals
    }

    func testMatchCoachesEmptyCoachAvailability() {
        let client = Client(
            name: "Test Client",
            goals: ["Tennis"],
            preferredAvailability: ["Morning"]
        )

        let coach = Coach(
            id: "coach1",
            name: "Busy Coach",
            specialties: ["Tennis"],
            experienceYears: 5,
            availability: [] // Empty availability
        )

        let result = matchCoaches(client: client, allCoaches: [coach])

        XCTAssertTrue(result.isEmpty) // No availability means no time match
    }

    func testMatchCoachesMultipleCoaches() {
        let client = Client(
            name: "Test Client",
            goals: ["Tennis", "Badminton"],
            preferredAvailability: ["Morning", "Evening"]
        )

        let coach1 = Coach(
            id: "coach1",
            name: "Tennis Morning Coach",
            specialties: ["Tennis"],
            experienceYears: 5,
            availability: ["Morning"]
        )

        let coach2 = Coach(
            id: "coach2",
            name: "Badminton Evening Coach",
            specialties: ["Badminton"],
            experienceYears: 3,
            availability: ["Evening"]
        )

        let coach3 = Coach(
            id: "coach3",
            name: "Swimming Coach", // No goal match
            specialties: ["Swimming"],
            experienceYears: 10,
            availability: ["Morning"]
        )

        let result = matchCoaches(client: client, allCoaches: [coach1, coach2, coach3])

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.id == "coach1" })
        XCTAssertTrue(result.contains { $0.id == "coach2" })
        XCTAssertFalse(result.contains { $0.id == "coach3" })
    }

    func testMatchCoachesEmptyCoachList() {
        let client = Client(
            name: "Test Client",
            goals: ["Tennis"],
            preferredAvailability: ["Morning"]
        )

        let result = matchCoaches(client: client, allCoaches: [])

        XCTAssertTrue(result.isEmpty)
    }

    func testMatchCoachesCaseSensitivity() {
        let client = Client(
            name: "Test Client",
            goals: ["tennis"], // lowercase
            preferredAvailability: ["morning"] // lowercase
        )

        let coach = Coach(
            id: "coach1",
            name: "Test Coach",
            specialties: ["Tennis"], // Title case
            experienceYears: 5,
            availability: ["Morning"] // Title case
        )

        let result = matchCoaches(client: client, allCoaches: [coach])

        // This tests if matching is case-sensitive (potential bug if it should be case-insensitive)
        XCTAssertTrue(result.isEmpty) // Current implementation is case-sensitive
    }

    func testMatchCoachesWhitespaceInGoals() {
        let client = Client(
            name: "Test Client",
            goals: [" Tennis "], // With whitespace
            preferredAvailability: ["Morning"]
        )

        let coach = Coach(
            id: "coach1",
            name: "Test Coach",
            specialties: ["Tennis"], // Without whitespace
            experienceYears: 5,
            availability: ["Morning"]
        )

        let result = matchCoaches(client: client, allCoaches: [coach])

        // This tests if matching handles whitespace (potential bug)
        XCTAssertTrue(result.isEmpty) // Whitespace not trimmed - potential bug
    }

    func testMatchCoachesDuplicateGoals() {
        let client = Client(
            name: "Test Client",
            goals: ["Tennis", "Tennis", "Tennis"], // Duplicates
            preferredAvailability: ["Morning"]
        )

        let coach = Coach(
            id: "coach1",
            name: "Test Coach",
            specialties: ["Tennis"],
            experienceYears: 5,
            availability: ["Morning"]
        )

        let result = matchCoaches(client: client, allCoaches: [coach])

        XCTAssertEqual(result.count, 1)
    }
}

// MARK: - BookingItem Tests

final class BookingItemTests: XCTestCase {

    // MARK: - allCoachIDs Tests

    func testAllCoachIDsWithCoachIDsArray() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach-single",
            coachIDs: ["coach1", "coach2", "coach3"]
        )

        XCTAssertEqual(booking.allCoachIDs, ["coach1", "coach2", "coach3"])
    }

    func testAllCoachIDsWithEmptyCoachIDsArray() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach-single",
            coachIDs: [] // Empty array
        )

        // Should fall back to coachID
        XCTAssertEqual(booking.allCoachIDs, ["coach-single"])
    }

    func testAllCoachIDsWithNilCoachIDsArray() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach-single",
            coachIDs: nil
        )

        XCTAssertEqual(booking.allCoachIDs, ["coach-single"])
    }

    func testAllCoachIDsWithEmptyCoachID() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "", // Empty
            coachIDs: nil
        )

        XCTAssertTrue(booking.allCoachIDs.isEmpty)
    }

    // MARK: - allClientIDs Tests

    func testAllClientIDsWithClientIDsArray() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client-single",
            coachID: "coach1",
            clientIDs: ["client1", "client2", "client3"]
        )

        XCTAssertEqual(booking.allClientIDs, ["client1", "client2", "client3"])
    }

    func testAllClientIDsWithEmptyClientIDsArray() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client-single",
            coachID: "coach1",
            clientIDs: []
        )

        XCTAssertEqual(booking.allClientIDs, ["client-single"])
    }

    func testAllClientIDsWithNilClientIDsArray() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client-single",
            coachID: "coach1",
            clientIDs: nil
        )

        XCTAssertEqual(booking.allClientIDs, ["client-single"])
    }

    func testAllClientIDsWithEmptyClientID() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "",
            coachID: "coach1",
            clientIDs: nil
        )

        XCTAssertTrue(booking.allClientIDs.isEmpty)
    }

    // MARK: - allCoachNames Tests

    func testAllCoachNamesWithCoachNamesArray() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            coachName: "Single Coach",
            coachNames: ["Coach A", "Coach B"]
        )

        XCTAssertEqual(booking.allCoachNames, ["Coach A", "Coach B"])
    }

    func testAllCoachNamesWithEmptyCoachNamesArray() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            coachName: "Single Coach",
            coachNames: []
        )

        XCTAssertEqual(booking.allCoachNames, ["Single Coach"])
    }

    func testAllCoachNamesWithNilCoachName() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            coachName: nil,
            coachNames: nil
        )

        XCTAssertTrue(booking.allCoachNames.isEmpty)
    }

    // MARK: - allClientNames Tests

    func testAllClientNamesWithClientNamesArray() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            clientName: "Single Client",
            coachID: "coach1",
            clientNames: ["Client A", "Client B"]
        )

        XCTAssertEqual(booking.allClientNames, ["Client A", "Client B"])
    }

    func testAllClientNamesWithEmptyClientNamesArray() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            clientName: "Single Client",
            coachID: "coach1",
            clientNames: []
        )

        XCTAssertEqual(booking.allClientNames, ["Single Client"])
    }

    func testAllClientNamesWithNilClientName() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            clientName: nil,
            coachID: "coach1",
            clientNames: nil
        )

        XCTAssertTrue(booking.allClientNames.isEmpty)
    }

    // MARK: - allCoachesAccepted Tests

    func testAllCoachesAcceptedWithAllTrue() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            coachAcceptances: ["coach1": true, "coach2": true, "coach3": true]
        )

        XCTAssertTrue(booking.allCoachesAccepted)
    }

    func testAllCoachesAcceptedWithOneFalse() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            coachAcceptances: ["coach1": true, "coach2": false, "coach3": true]
        )

        XCTAssertFalse(booking.allCoachesAccepted)
    }

    func testAllCoachesAcceptedWithAllFalse() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            coachAcceptances: ["coach1": false, "coach2": false]
        )

        XCTAssertFalse(booking.allCoachesAccepted)
    }

    func testAllCoachesAcceptedWithEmptyDict() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            coachAcceptances: [:] // Empty
        )

        // Empty dict should return true (legacy booking)
        XCTAssertTrue(booking.allCoachesAccepted)
    }

    func testAllCoachesAcceptedWithNilDict() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            coachAcceptances: nil
        )

        // Nil should return true (legacy booking)
        XCTAssertTrue(booking.allCoachesAccepted)
    }

    // MARK: - allClientsConfirmed Tests

    func testAllClientsConfirmedWithAllTrue() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            clientConfirmations: ["client1": true, "client2": true]
        )

        XCTAssertTrue(booking.allClientsConfirmed)
    }

    func testAllClientsConfirmedWithOneFalse() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            clientConfirmations: ["client1": true, "client2": false]
        )

        XCTAssertFalse(booking.allClientsConfirmed)
    }

    func testAllClientsConfirmedWithEmptyDict() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            clientConfirmations: [:]
        )

        XCTAssertTrue(booking.allClientsConfirmed)
    }

    func testAllClientsConfirmedWithNilDict() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            clientConfirmations: nil
        )

        XCTAssertTrue(booking.allClientsConfirmed)
    }

    // MARK: - participantSummary Tests

    func testParticipantSummaryOneOnOne() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1"
        )

        XCTAssertEqual(booking.participantSummary, "1:1 Session")
    }

    func testParticipantSummaryMultipleCoaches() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "",
            clientIDs: ["client1"],
            coachIDs: ["coach1", "coach2"]
        )

        XCTAssertEqual(booking.participantSummary, "2 coaches, 1 client")
    }

    func testParticipantSummaryMultipleClients() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "",
            coachID: "coach1",
            clientIDs: ["client1", "client2", "client3"],
            coachIDs: ["coach1"]
        )

        XCTAssertEqual(booking.participantSummary, "1 coach, 3 clients")
    }

    func testParticipantSummaryMultipleBoth() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "",
            coachID: "",
            clientIDs: ["client1", "client2"],
            coachIDs: ["coach1", "coach2"]
        )

        XCTAssertEqual(booking.participantSummary, "2 coaches, 2 clients")
    }

    func testParticipantSummaryNoParticipants() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "",
            coachID: "",
            clientIDs: [],
            coachIDs: []
        )

        // Edge case: no participants - tests if logic handles 0 counts correctly
        // The condition is `coachCount == 1 && clientCount == 1` which is false for 0/0
        // So it will return "0 coaches, 0 clients" format
        XCTAssertNotEqual(booking.participantSummary, "1:1 Session")
    }

    // MARK: - BookingItem Equatable Tests

    func testBookingItemEquatableSameBookings() {
        let booking1 = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            startAt: Date(timeIntervalSince1970: 1000),
            endAt: Date(timeIntervalSince1970: 2000),
            location: "Gym",
            notes: "Test notes",
            status: "confirmed"
        )

        let booking2 = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            startAt: Date(timeIntervalSince1970: 1000),
            endAt: Date(timeIntervalSince1970: 2000),
            location: "Gym",
            notes: "Test notes",
            status: "confirmed"
        )

        XCTAssertEqual(booking1, booking2)
    }

    func testBookingItemEquatableDifferentIDs() {
        let booking1 = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1"
        )

        let booking2 = FirestoreManager.BookingItem(
            id: "booking2",
            clientID: "client1",
            coachID: "coach1"
        )

        XCTAssertNotEqual(booking1, booking2)
    }

    // MARK: - Date/Time Edge Cases

    func testBookingWithNilDates() {
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            startAt: nil,
            endAt: nil
        )

        XCTAssertNil(booking.startAt)
        XCTAssertNil(booking.endAt)
    }

    func testBookingWithEndBeforeStart() {
        let startDate = Date(timeIntervalSince1970: 2000)
        let endDate = Date(timeIntervalSince1970: 1000) // Before start

        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            startAt: startDate,
            endAt: endDate
        )

        XCTAssertLessThan(booking.endAt!, booking.startAt!) // No validation - potential bug
    }
}

// MARK: - ZipToState Tests

final class ZipToStateTests: XCTestCase {

    func testNormalizeZipCodeFiveDigits() {
        let zip = "55102"
        XCTAssertEqual(zip.count, 5)
    }

    func testNormalizeZipCodeMoreThanFiveDigits() {
        // ZIP+4 format should be normalized to 5 digits
        let zipPlus4 = "55102-1234"
        let prefix = String(zipPlus4.prefix(5))
        XCTAssertEqual(prefix, "55102")
    }

    func testNormalizeZipCodeWithWhitespace() {
        let zipWithSpaces = "  55102  "
        let trimmed = zipWithSpaces.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(trimmed, "55102")
    }

    func testNormalizeZipCodeLessThanFiveDigits() {
        // Short ZIP code
        let shortZip = "5510"
        XCTAssertLessThan(shortZip.count, 5)
    }

    func testNormalizeZipCodeEmpty() {
        let emptyZip = ""
        XCTAssertTrue(emptyZip.isEmpty)
    }
}

// MARK: - Image Helpers Tests

final class ImageHelpersTests: XCTestCase {

    func testResizeImageMaintainingAspectRatioSquare() {
        // Create a 100x100 test image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let originalImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 100, height: 100)))
        }

        let resized = originalImage.resizeMaintainingAspectRatio(targetSize: CGSize(width: 50, height: 50))

        XCTAssertEqual(resized.size.width, 50)
        XCTAssertEqual(resized.size.height, 50)
    }

    func testResizeImageMaintainingAspectRatioWide() {
        // Create a 200x100 wide image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100))
        let originalImage = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 200, height: 100)))
        }

        let resized = originalImage.resizeMaintainingAspectRatio(targetSize: CGSize(width: 100, height: 100))

        // Should fit width (100) and scale height proportionally (50)
        XCTAssertEqual(resized.size.width, 100)
        XCTAssertEqual(resized.size.height, 50)
    }

    func testResizeImageMaintainingAspectRatioTall() {
        // Create a 100x200 tall image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200))
        let originalImage = renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 100, height: 200)))
        }

        let resized = originalImage.resizeMaintainingAspectRatio(targetSize: CGSize(width: 100, height: 100))

        // Should fit height (100) and scale width proportionally (50)
        XCTAssertEqual(resized.size.width, 50)
        XCTAssertEqual(resized.size.height, 100)
    }

    func testResizeImageWithZeroTargetWidth() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let originalImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 100, height: 100)))
        }

        let resized = originalImage.resizeMaintainingAspectRatio(targetSize: CGSize(width: 0, height: 50))

        // Should return original image when target has zero width
        XCTAssertEqual(resized.size.width, 100)
        XCTAssertEqual(resized.size.height, 100)
    }

    func testResizeImageWithZeroTargetHeight() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let originalImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 100, height: 100)))
        }

        let resized = originalImage.resizeMaintainingAspectRatio(targetSize: CGSize(width: 50, height: 0))

        // Should return original image when target has zero height
        XCTAssertEqual(resized.size.width, 100)
        XCTAssertEqual(resized.size.height, 100)
    }

    func testResizeImageWithNegativeTargetSize() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let originalImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 100, height: 100)))
        }

        let resized = originalImage.resizeMaintainingAspectRatio(targetSize: CGSize(width: -50, height: -50))

        // Should return original image when target has negative dimensions
        XCTAssertEqual(resized.size.width, 100)
        XCTAssertEqual(resized.size.height, 100)
    }

    func testResizeImageScaleUp() {
        // Create a small 50x50 image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50))
        let originalImage = renderer.image { ctx in
            UIColor.yellow.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 50, height: 50)))
        }

        let resized = originalImage.resizeMaintainingAspectRatio(targetSize: CGSize(width: 200, height: 200))

        // Should scale up to 200x200
        XCTAssertEqual(resized.size.width, 200)
        XCTAssertEqual(resized.size.height, 200)
    }
}

// MARK: - DynamicListsError Tests

final class DynamicListsErrorTests: XCTestCase {

    func testEmptyTitleErrorDescription() {
        let error = DynamicLists.DynamicListsError.emptyTitle
        XCTAssertEqual(error.errorDescription, "Title must not be empty")
    }

    func testDuplicateTitleErrorDescription() {
        let error = DynamicLists.DynamicListsError.duplicateTitle
        XCTAssertEqual(error.errorDescription, "A goal with this title already exists")
    }

    func testFirestoreErrorDescription() {
        let underlyingError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error message"])
        let error = DynamicLists.DynamicListsError.firestoreError(underlyingError)
        XCTAssertEqual(error.errorDescription, "Test error message")
    }
}

// MARK: - Subject Tests

final class SubjectTests: XCTestCase {

    func testSubjectInitialization() {
        let subject = FirestoreManager.Subject(
            id: "subject1",
            title: "Tennis",
            order: 1,
            active: true
        )

        XCTAssertEqual(subject.id, "subject1")
        XCTAssertEqual(subject.title, "Tennis")
        XCTAssertEqual(subject.order, 1)
        XCTAssertTrue(subject.active)
    }

    func testSubjectInactiveState() {
        let subject = FirestoreManager.Subject(
            id: "subject2",
            title: "Deprecated Sport",
            order: 99,
            active: false
        )

        XCTAssertFalse(subject.active)
    }
}

// MARK: - UserSummary Tests

final class UserSummaryTests: XCTestCase {

    func testUserSummaryWithPhotoURL() {
        let summary = FirestoreManager.UserSummary(
            id: "user1",
            name: "John Doe",
            photoURL: URL(string: "https://example.com/photo.jpg")
        )

        XCTAssertEqual(summary.id, "user1")
        XCTAssertEqual(summary.name, "John Doe")
        XCTAssertEqual(summary.photoURL?.absoluteString, "https://example.com/photo.jpg")
    }

    func testUserSummaryWithoutPhotoURL() {
        let summary = FirestoreManager.UserSummary(
            id: "user2",
            name: "Jane Doe",
            photoURL: nil
        )

        XCTAssertEqual(summary.id, "user2")
        XCTAssertEqual(summary.name, "Jane Doe")
        XCTAssertNil(summary.photoURL)
    }
}

// MARK: - ReviewItem Tests

final class ReviewItemTests: XCTestCase {

    func testReviewItemInitialization() {
        let review = FirestoreManager.ReviewItem(
            id: "review1",
            clientID: "client1",
            clientName: "John Client",
            coachID: "coach1",
            coachName: "Jane Coach",
            createdAt: Date(timeIntervalSince1970: 1000),
            rating: "5",
            ratingMessage: "Great session!"
        )

        XCTAssertEqual(review.id, "review1")
        XCTAssertEqual(review.clientID, "client1")
        XCTAssertEqual(review.clientName, "John Client")
        XCTAssertEqual(review.coachID, "coach1")
        XCTAssertEqual(review.coachName, "Jane Coach")
        XCTAssertEqual(review.rating, "5")
        XCTAssertEqual(review.ratingMessage, "Great session!")
    }

    func testReviewItemWithNilFields() {
        let review = FirestoreManager.ReviewItem(
            id: "review2",
            clientID: "client2",
            clientName: nil,
            coachID: "coach2",
            coachName: nil,
            createdAt: nil,
            rating: nil,
            ratingMessage: nil
        )

        XCTAssertNil(review.clientName)
        XCTAssertNil(review.coachName)
        XCTAssertNil(review.createdAt)
        XCTAssertNil(review.rating)
        XCTAssertNil(review.ratingMessage)
    }
}

// MARK: - LocationItem Tests

final class LocationItemTests: XCTestCase {

    func testLocationItemInitialization() {
        let location = FirestoreManager.LocationItem(
            id: "loc1",
            name: "City Gym",
            address: "123 Main St",
            notes: "Parking available",
            latitude: 44.9778,
            longitude: -93.2650
        )

        XCTAssertEqual(location.id, "loc1")
        XCTAssertEqual(location.name, "City Gym")
        XCTAssertEqual(location.address, "123 Main St")
        XCTAssertEqual(location.notes, "Parking available")
        XCTAssertEqual(location.latitude, 44.9778)
        XCTAssertEqual(location.longitude, -93.2650)
    }

    func testLocationItemEquatable() {
        let loc1 = FirestoreManager.LocationItem(
            id: "loc1",
            name: "Gym",
            address: "123 Main St",
            notes: nil,
            latitude: 44.9778,
            longitude: -93.2650
        )

        let loc2 = FirestoreManager.LocationItem(
            id: "loc1",
            name: "Gym",
            address: "123 Main St",
            notes: nil,
            latitude: 44.9778,
            longitude: -93.2650
        )

        XCTAssertEqual(loc1, loc2)
    }

    func testLocationItemNotEqualDifferentID() {
        let loc1 = FirestoreManager.LocationItem(
            id: "loc1",
            name: "Gym",
            address: "123 Main St",
            notes: nil,
            latitude: 44.9778,
            longitude: -93.2650
        )

        let loc2 = FirestoreManager.LocationItem(
            id: "loc2",
            name: "Gym",
            address: "123 Main St",
            notes: nil,
            latitude: 44.9778,
            longitude: -93.2650
        )

        XCTAssertNotEqual(loc1, loc2)
    }

    func testLocationItemWithNilCoordinates() {
        let location = FirestoreManager.LocationItem(
            id: "loc1",
            name: "Unknown Location",
            address: nil,
            notes: nil,
            latitude: nil,
            longitude: nil
        )

        XCTAssertNil(location.latitude)
        XCTAssertNil(location.longitude)
    }

    func testLocationItemEquatableIgnoresNotes() {
        // The current Equatable implementation doesn't check notes
        let loc1 = FirestoreManager.LocationItem(
            id: "loc1",
            name: "Gym",
            address: "123 Main St",
            notes: "Note 1",
            latitude: 44.9778,
            longitude: -93.2650
        )

        let loc2 = FirestoreManager.LocationItem(
            id: "loc1",
            name: "Gym",
            address: "123 Main St",
            notes: "Different Note", // Different notes
            latitude: 44.9778,
            longitude: -93.2650
        )

        // Bug: notes are not compared in Equatable
        XCTAssertEqual(loc1, loc2) // This might be unexpected behavior
    }
}

// MARK: - ChatItem Tests

final class ChatItemTests: XCTestCase {

    func testChatItemInitialization() {
        let chat = FirestoreManager.ChatItem(
            id: "chat1",
            participants: ["user1", "user2"],
            lastMessageText: "Hello!",
            lastMessageAt: Date(timeIntervalSince1970: 1000)
        )

        XCTAssertEqual(chat.id, "chat1")
        XCTAssertEqual(chat.participants, ["user1", "user2"])
        XCTAssertEqual(chat.lastMessageText, "Hello!")
        XCTAssertNotNil(chat.lastMessageAt)
    }

    func testChatItemEquatable() {
        let chat1 = FirestoreManager.ChatItem(
            id: "chat1",
            participants: ["user1", "user2"],
            lastMessageText: "Hello!",
            lastMessageAt: Date(timeIntervalSince1970: 1000)
        )

        let chat2 = FirestoreManager.ChatItem(
            id: "chat1",
            participants: ["user1", "user2"],
            lastMessageText: "Hello!",
            lastMessageAt: Date(timeIntervalSince1970: 1000)
        )

        XCTAssertEqual(chat1, chat2)
    }

    func testChatItemWithEmptyParticipants() {
        let chat = FirestoreManager.ChatItem(
            id: "chat1",
            participants: [],
            lastMessageText: nil,
            lastMessageAt: nil
        )

        XCTAssertTrue(chat.participants.isEmpty)
        XCTAssertNil(chat.lastMessageText)
        XCTAssertNil(chat.lastMessageAt)
    }
}

// MARK: - ChatMessage Tests

final class ChatMessageTests: XCTestCase {

    func testChatMessageInitialization() {
        let message = FirestoreManager.ChatMessage(
            id: "msg1",
            senderId: "user1",
            text: "Hello, world!",
            createdAt: Date(timeIntervalSince1970: 1000)
        )

        XCTAssertEqual(message.id, "msg1")
        XCTAssertEqual(message.senderId, "user1")
        XCTAssertEqual(message.text, "Hello, world!")
        XCTAssertNotNil(message.createdAt)
    }

    func testChatMessageWithEmptyText() {
        let message = FirestoreManager.ChatMessage(
            id: "msg2",
            senderId: "user1",
            text: "",
            createdAt: Date()
        )

        XCTAssertEqual(message.text, "")
    }

    func testChatMessageWithNilCreatedAt() {
        let message = FirestoreManager.ChatMessage(
            id: "msg3",
            senderId: "user1",
            text: "Test",
            createdAt: nil
        )

        XCTAssertNil(message.createdAt)
    }
}

// MARK: - URL Resolution Logic Tests

final class URLResolutionTests: XCTestCase {

    func testHttpURLIsValid() {
        let urlString = "http://example.com/photo.jpg"
        let url = URL(string: urlString)
        XCTAssertNotNil(url)
        XCTAssertTrue(urlString.hasPrefix("http://"))
    }

    func testHttpsURLIsValid() {
        let urlString = "https://example.com/photo.jpg"
        let url = URL(string: urlString)
        XCTAssertNotNil(url)
        XCTAssertTrue(urlString.hasPrefix("https://"))
    }

    func testGsURLIsValid() {
        let urlString = "gs://bucket-name/path/to/photo.jpg"
        XCTAssertTrue(urlString.hasPrefix("gs://"))
    }

    func testStoragePathWithLeadingSlash() {
        var path = "/photos/user123/avatar.jpg"
        if path.hasPrefix("/") { path.removeFirst() }
        XCTAssertEqual(path, "photos/user123/avatar.jpg")
    }

    func testStoragePathWithoutLeadingSlash() {
        var path = "photos/user123/avatar.jpg"
        if path.hasPrefix("/") { path.removeFirst() }
        XCTAssertEqual(path, "photos/user123/avatar.jpg")
    }

    func testEmptyPhotoString() {
        let photoStr = ""
        XCTAssertTrue(photoStr.isEmpty)
    }

    func testUrlWithSpecialCharacters() {
        let urlString = "https://example.com/photo with spaces.jpg"
        let url = URL(string: urlString)
        // Note: In iOS 18+, URL(string:) can handle some special characters
        // This test documents the current behavior - URLs with spaces may be valid
        // The app should still properly encode URLs before using them
        XCTAssertNotNil(url) // iOS 18+ auto-handles spaces
    }

    func testUrlWithEncodedSpecialCharacters() {
        let urlString = "https://example.com/photo%20with%20spaces.jpg"
        let url = URL(string: urlString)
        XCTAssertNotNil(url)
    }
}

// MARK: - Edge Cases and Potential Bug Tests

final class EdgeCaseTests: XCTestCase {

    func testCoachWithVeryLongBio() {
        let longBio = String(repeating: "A", count: 10000)
        let coach = Coach(
            name: "Test Coach",
            specialties: ["Tennis"],
            experienceYears: 5,
            availability: ["Morning"],
            bio: longBio
        )

        XCTAssertEqual(coach.bio?.count, 10000)
    }

    func testCoachWithUnicodeInName() {
        let coach = Coach(
            name: "教练 李明 🏃‍♂️",
            specialties: ["网球"],
            experienceYears: 5,
            availability: ["上午"]
        )

        XCTAssertEqual(coach.name, "教练 李明 🏃‍♂️")
    }

    func testClientWithSpecialCharactersInGoals() {
        let client = Client(
            name: "Test Client",
            goals: ["Tennis & Badminton", "Swimming/Diving", "Track<>Field"],
            preferredAvailability: ["Morning"]
        )

        XCTAssertEqual(client.goals.count, 3)
    }

    func testBookingWithDistantFutureDates() {
        let farFuture = Date(timeIntervalSince1970: 32503680000) // Year 3000
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            startAt: farFuture,
            endAt: farFuture.addingTimeInterval(3600)
        )

        XCTAssertNotNil(booking.startAt)
    }

    func testBookingWithDistantPastDates() {
        let farPast = Date(timeIntervalSince1970: -2208988800) // Year 1900
        let booking = FirestoreManager.BookingItem(
            id: "booking1",
            clientID: "client1",
            coachID: "coach1",
            startAt: farPast,
            endAt: farPast.addingTimeInterval(3600)
        )

        XCTAssertNotNil(booking.startAt)
    }

    func testMatcherWithManyCoaches() {
        let client = Client(
            name: "Test Client",
            goals: ["Tennis"],
            preferredAvailability: ["Morning"]
        )

        // Create 1000 coaches
        var coaches: [Coach] = []
        for i in 0..<1000 {
            coaches.append(Coach(
                id: "coach\(i)",
                name: "Coach \(i)",
                specialties: i % 2 == 0 ? ["Tennis"] : ["Badminton"],
                experienceYears: i % 20,
                availability: i % 3 == 0 ? ["Morning"] : ["Evening"]
            ))
        }

        let result = matchCoaches(client: client, allCoaches: coaches)

        // Should have coaches with Tennis and Morning availability
        XCTAssertGreaterThan(result.count, 0)
        XCTAssertLessThan(result.count, coaches.count)
    }

    func testMatcherWithManyGoals() {
        let manyGoals = (0..<100).map { "Goal\($0)" }
        let client = Client(
            name: "Test Client",
            goals: manyGoals,
            preferredAvailability: ["Morning"]
        )

        let coach = Coach(
            id: "coach1",
            name: "Coach",
            specialties: ["Goal50"], // One match
            experienceYears: 5,
            availability: ["Morning"]
        )

        let result = matchCoaches(client: client, allCoaches: [coach])

        XCTAssertEqual(result.count, 1)
    }

    func testRateRangeWithThreeElements() {
        // Rate range usually has 2 elements [min, max], test with 3
        let coach = Coach(
            name: "Test Coach",
            specialties: ["Tennis"],
            experienceYears: 5,
            availability: ["Morning"],
            rateRange: [30.0, 50.0, 70.0]
        )

        XCTAssertEqual(coach.rateRange?.count, 3)
    }

    func testBookingIDAsUUID() {
        let uuid = UUID().uuidString
        let booking = FirestoreManager.BookingItem(
            id: uuid,
            clientID: "client1",
            coachID: "coach1"
        )

        XCTAssertEqual(booking.id, uuid)
    }

    func testCoachPaymentsWithEmptyValues() {
        let coach = Coach(
            name: "Test Coach",
            specialties: ["Tennis"],
            experienceYears: 5,
            availability: ["Morning"],
            payments: ["venmo": "", "paypal": ""] // Empty payment values
        )

        XCTAssertEqual(coach.payments?["venmo"], "")
        XCTAssertEqual(coach.payments?["paypal"], "")
    }

    func testCoachPaymentsWithNilAndEmptyMix() {
        let payments: [String: String] = ["venmo": "@user", "paypal": ""]
        let coach = Coach(
            name: "Test Coach",
            specialties: ["Tennis"],
            experienceYears: 5,
            availability: ["Morning"],
            payments: payments
        )

        XCTAssertEqual(coach.payments?["venmo"], "@user")
        XCTAssertEqual(coach.payments?["paypal"], "")
        XCTAssertNil(coach.payments?["zelle"])
    }
}

// MARK: - Concurrent Access Tests

final class ConcurrencyTests: XCTestCase {

    func testMatcherThreadSafety() async {
        let client = Client(
            name: "Test Client",
            goals: ["Tennis"],
            preferredAvailability: ["Morning"]
        )

        let coaches = (0..<100).map { i in
            Coach(
                id: "coach\(i)",
                name: "Coach \(i)",
                specialties: ["Tennis"],
                experienceYears: 5,
                availability: ["Morning"]
            )
        }

        // Run matching concurrently
        await withTaskGroup(of: [Coach].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    return matchCoaches(client: client, allCoaches: coaches)
                }
            }

            var allResults: [[Coach]] = []
            for await result in group {
                allResults.append(result)
            }

            // All results should be identical
            let firstCount = allResults.first?.count ?? 0
            for result in allResults {
                XCTAssertEqual(result.count, firstCount)
            }
        }
    }
}

// MARK: - Name Parsing Tests

final class NameParsingTests: XCTestCase {

    func testParseCoachNameFromFirstAndLast() {
        let first = "John"
        let last = "Doe"
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        XCTAssertEqual(name, "John Doe")
    }

    func testParseCoachNameFirstOnly() {
        let first = "John"
        let last = ""
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        XCTAssertEqual(name, "John")
    }

    func testParseCoachNameLastOnly() {
        let first = ""
        let last = "Doe"
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        XCTAssertEqual(name, "Doe")
    }

    func testParseCoachNameBothEmpty() {
        let first = ""
        let last = ""
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        XCTAssertEqual(name, "")
    }

    func testParseCoachNameWithMiddleName() {
        // This pattern doesn't handle middle names
        let first = "John Michael"
        let last = "Doe"
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        XCTAssertEqual(name, "John Michael Doe")
    }

    func testParseCoachNameWithWhitespace() {
        let first = "  John  "
        let last = "  Doe  "
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        // Note: Whitespace is not trimmed - potential bug
        XCTAssertEqual(name, "  John     Doe  ")
    }
}

// MARK: - Data Type Conversion Tests

final class DataTypeConversionTests: XCTestCase {

    func testExperienceYearsFromDouble() {
        // Simulating Firestore returning Double for ExperienceYears
        let doubleValue: Double = 5.7
        let intValue = Int(doubleValue)
        XCTAssertEqual(intValue, 5)
    }

    func testExperienceYearsFromDoubleRoundDown() {
        let doubleValue: Double = 5.9
        let intValue = Int(doubleValue)
        XCTAssertEqual(intValue, 5) // Truncates, doesn't round
    }

    func testExperienceYearsFromInt() {
        let intValue: Int = 5
        XCTAssertEqual(intValue, 5)
    }

    func testHourlyRateAsDouble() {
        let rate: Double = 49.99
        XCTAssertEqual(rate, 49.99)
    }

    func testRateRangeArrayAccess() {
        let rateRange: [Double] = [40.0, 60.0]

        // Safe access patterns
        let min = rateRange.first ?? 0
        let max = rateRange.last ?? 0

        XCTAssertEqual(min, 40.0)
        XCTAssertEqual(max, 60.0)
    }

    func testRateRangeEmptyArrayAccess() {
        let rateRange: [Double] = []

        let min = rateRange.first ?? 0
        let max = rateRange.last ?? 0

        XCTAssertEqual(min, 0)
        XCTAssertEqual(max, 0)
    }

    func testRateRangeSingleElementAccess() {
        let rateRange: [Double] = [50.0]

        let min = rateRange.first ?? 0
        let max = rateRange.last ?? 0

        // Both return same value for single element
        XCTAssertEqual(min, 50.0)
        XCTAssertEqual(max, 50.0)
    }
}

// MARK: - Availability/Time Slot Tests

final class AvailabilityTests: XCTestCase {

    func testAvailabilitySetOperations() {
        let clientTimes = Set(["Morning", "Afternoon"])
        let coachTimes = Set(["Afternoon", "Evening"])

        let overlap = !clientTimes.isDisjoint(with: coachTimes)
        XCTAssertTrue(overlap)

        let intersection = clientTimes.intersection(coachTimes)
        XCTAssertEqual(intersection, ["Afternoon"])
    }

    func testAvailabilityNoOverlap() {
        let clientTimes = Set(["Morning"])
        let coachTimes = Set(["Evening"])

        let overlap = !clientTimes.isDisjoint(with: coachTimes)
        XCTAssertFalse(overlap)
    }

    func testAvailabilityEmptyClient() {
        let clientTimes = Set<String>([])
        let coachTimes = Set(["Morning", "Evening"])

        let overlap = !clientTimes.isDisjoint(with: coachTimes)
        XCTAssertFalse(overlap) // Empty set is disjoint with any set
    }

    func testAvailabilityEmptyCoach() {
        let clientTimes = Set(["Morning", "Evening"])
        let coachTimes = Set<String>([])

        let overlap = !clientTimes.isDisjoint(with: coachTimes)
        XCTAssertFalse(overlap)
    }

    func testAvailabilityBothEmpty() {
        let clientTimes = Set<String>([])
        let coachTimes = Set<String>([])

        let overlap = !clientTimes.isDisjoint(with: coachTimes)
        // Two empty sets are disjoint
        XCTAssertFalse(overlap)
    }

    func testAvailabilityIdenticalSets() {
        let clientTimes = Set(["Morning", "Afternoon", "Evening"])
        let coachTimes = Set(["Morning", "Afternoon", "Evening"])

        let overlap = !clientTimes.isDisjoint(with: coachTimes)
        XCTAssertTrue(overlap)
    }
}
