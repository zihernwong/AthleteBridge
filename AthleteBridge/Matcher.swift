func matchCoaches(client: Client, allCoaches: [Coach]) -> [Coach] {
    allCoaches.filter { coach in
        let sharedGoals = !coach.specialties.filter(client.goals.contains).isEmpty
        let timeMatch = coach.availability.contains(client.preferredAvailability)
        return sharedGoals && timeMatch
    }
}

