func matchCoaches(client: Client, allCoaches: [Coach]) -> [Coach] {
    allCoaches.filter { coach in
        let sharedGoals = !coach.specialties.filter(client.goals.contains).isEmpty
        // preferredAvailability is an array now — match if any preferred time intersects coach availability
        let clientTimes = Set(client.preferredAvailability)
        let coachTimes = Set(coach.availability)
        let timeMatch = !clientTimes.isDisjoint(with: coachTimes)
        return sharedGoals && timeMatch
    }
}
