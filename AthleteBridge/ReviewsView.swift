import SwiftUI

struct Review: Identifiable {
    let id = UUID()
    let coachName: String
    let rating: Int
    let message: String
    let date: Date
}

struct ReviewsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    // form state
    @State private var selectedCoachId: String = ""
    @State private var selectedCoachName: String = ""
    @State private var rating: Int = 5
    @State private var message: String = ""
    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    // Computed lists to split reviews for the current user
    private var reviewsAboutUser: [FirestoreManager.ReviewItem] {
        guard let uid = auth.user?.uid else { return [] }
        return firestore.reviews.filter { $0.coachID == uid }
    }

    private var reviewsByUser: [FirestoreManager.ReviewItem] {
        guard let uid = auth.user?.uid else { return [] }
        return firestore.reviews.filter { $0.clientID == uid }
    }

    var body: some View {
        NavigationStack {
            List {
                let userType = firestore.currentUserType?.uppercased()

                // If the user is a coach, show only reviews about them
                if userType == "COACH" {
                    Section(header: Text("Reviews About You")) {
                        if reviewsAboutUser.isEmpty {
                            Text("No reviews about you yet").foregroundColor(.secondary)
                        } else {
                            ForEach(reviewsAboutUser) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                        .overlay(Text(String((item.clientName ?? "").prefix(1))).font(.headline))

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(item.clientName ?? "Client").font(.headline)
                                            Spacer()
                                            Text(item.createdAt ?? Date(), style: .date).font(.caption).foregroundColor(.secondary)
                                        }

                                        HStack(spacing: 4) {
                                            let stars = Int(item.rating ?? "0") ?? 0
                                            ForEach(1...5, id: \.self) { i in
                                                Image(systemName: i <= stars ? "star.fill" : "star")
                                                    .foregroundColor(i <= stars ? .yellow : .secondary)
                                            }
                                        }
                                        Text(item.ratingMessage ?? "").font(.subheadline).foregroundColor(.primary)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                } else if userType == "CLIENT" {
                    // If the user is a client, show only reviews they've written
                    Section(header: Text("Your Reviews")) {
                        if reviewsByUser.isEmpty {
                            Text("You haven't written any reviews yet").foregroundColor(.secondary)
                        } else {
                            ForEach(reviewsByUser) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                        .overlay(Text(String((item.coachName ?? "").prefix(1))).font(.headline))

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(item.coachName ?? "Coach").font(.headline)
                                            Spacer()
                                            Text(item.createdAt ?? Date(), style: .date).font(.caption).foregroundColor(.secondary)
                                        }

                                        HStack(spacing: 4) {
                                            let stars = Int(item.rating ?? "0") ?? 0
                                            ForEach(1...5, id: \.self) { i in
                                                Image(systemName: i <= stars ? "star.fill" : "star")
                                                    .foregroundColor(i <= stars ? .yellow : .secondary)
                                            }
                                        }
                                        Text(item.ratingMessage ?? "").font(.subheadline).foregroundColor(.primary)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                } else {
                    // Fallback (unknown userType): show both sections as before

                    // Reviews about the current user (if they are a coach)
                    Section(header: Text("Reviews About You")) {
                        if reviewsAboutUser.isEmpty {
                            Text("No reviews about you yet").foregroundColor(.secondary)
                        } else {
                            ForEach(reviewsAboutUser) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                        .overlay(Text(String((item.clientName ?? "").prefix(1))).font(.headline))

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(item.clientName ?? "Client").font(.headline)
                                            Spacer()
                                            Text(item.createdAt ?? Date(), style: .date).font(.caption).foregroundColor(.secondary)
                                        }

                                        HStack(spacing: 4) {
                                            let stars = Int(item.rating ?? "0") ?? 0
                                            ForEach(1...5, id: \.self) { i in
                                                Image(systemName: i <= stars ? "star.fill" : "star")
                                                    .foregroundColor(i <= stars ? .yellow : .secondary)
                                            }
                                        }
                                        Text(item.ratingMessage ?? "").font(.subheadline).foregroundColor(.primary)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }

                    // Reviews written by the current user
                    Section(header: Text("Your Reviews")) {
                        if reviewsByUser.isEmpty {
                            Text("You haven't written any reviews yet").foregroundColor(.secondary)
                        } else {
                            ForEach(reviewsByUser) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                        .overlay(Text(String((item.coachName ?? "").prefix(1))).font(.headline))

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(item.coachName ?? "Coach").font(.headline)
                                            Spacer()
                                            Text(item.createdAt ?? Date(), style: .date).font(.caption).foregroundColor(.secondary)
                                        }

                                        HStack(spacing: 4) {
                                            let stars = Int(item.rating ?? "0") ?? 0
                                            ForEach(1...5, id: \.self) { i in
                                                Image(systemName: i <= stars ? "star.fill" : "star")
                                                    .foregroundColor(i <= stars ? .yellow : .secondary)
                                            }
                                        }
                                        Text(item.ratingMessage ?? "").font(.subheadline).foregroundColor(.primary)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }

                // Write a review form remains unchanged but is only shown to CLIENT users
                if userType == "CLIENT" {
                    Section(header: Text("Write a Review")) {
                        if firestore.coaches.isEmpty {
                            Text("No coaches available").foregroundColor(.secondary)
                        } else {
                            Picker("Coach", selection: $selectedCoachId) {
                                ForEach(firestore.coaches, id: \.id) { coach in
                                    Text(coach.name).tag(coach.id)
                                }
                            }
                            .onChange(of: selectedCoachId) { new in
                                selectedCoachName = firestore.coaches.first(where: { $0.id == new })?.name ?? ""
                            }
                        }

                        Picker("Rating", selection: $rating) {
                            ForEach(1...5, id: \.self) { r in
                                Text(String(r)).tag(r)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())

                        TextEditor(text: $message)
                            .frame(minHeight: 100)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(UIColor.separator)))

                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Button(action: submitReview) {
                                    Text("Submit Review")
                                        .bold()
                                }
                                .disabled(selectedCoachId.isEmpty || auth.user == nil || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            Spacer()
                        }
                    }
                }

                // Debug panel for review fetch status
                if !firestore.reviewsDebug.isEmpty {
                    Section(header: Text("Debug")) {
                        Text(firestore.reviewsDebug).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Reviews")
            .listStyle(InsetGroupedListStyle())
            .toolbar {
                // No edit or refresh buttons needed for Reviews view per request.
            }
            .onAppear {
                firestore.fetchCoaches()
                firestore.fetchAllReviews()
            }
            .onChange(of: firestore.coaches) { _, newCoaches in
                if selectedCoachId.isEmpty, let first = newCoaches.first {
                    selectedCoachId = first.id
                    selectedCoachName = first.name
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Notice"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func submitReview() {
        guard let uid = auth.user?.uid else {
            alertMessage = "You must be signed in to submit a review."
            showAlert = true
            return
        }
        let coachId = selectedCoachId
        guard !coachId.isEmpty else { return }
        isSubmitting = true

        firestore.saveReview(clientID: uid, coachID: coachId, rating: String(rating), ratingMessage: message) { err in
            DispatchQueue.main.async {
                self.isSubmitting = false
                if let err = err {
                    self.alertMessage = "Failed to submit review: \(err.localizedDescription)"
                    self.showAlert = true
                } else {
                    // refresh live reviews from Firestore
                    firestore.fetchAllReviews()
                    message = ""
                    self.alertMessage = "Review submitted"
                    self.showAlert = true
                }
            }
        }
    }
}

struct ReviewsView_Previews: PreviewProvider {
    static var previews: some View {
        ReviewsView()
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
