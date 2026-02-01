func matchCoaches(client: Client, allCoaches: [Coach]) -> [Coach] {
    allCoaches.filter { coach in
        // Normalize goals and specialties: lowercase and trim whitespace for case-insensitive matching
        let normalizedClientGoals = Set(client.goals.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let normalizedCoachSpecialties = Set(coach.specialties.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let sharedGoals = !normalizedClientGoals.isDisjoint(with: normalizedCoachSpecialties)

        // Normalize availability times: lowercase and trim whitespace for case-insensitive matching
        let clientTimes = Set(client.preferredAvailability.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let coachTimes = Set(coach.availability.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let timeMatch = !clientTimes.isDisjoint(with: coachTimes)

        return sharedGoals && timeMatch
    }
}
