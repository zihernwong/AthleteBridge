import SwiftUI
import UIKit

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
    @State private var coachSearchText: String = ""
    @State private var rating: Int = 5
    @State private var message: String = ""
    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    // Focus state for the review message editor so we can dismiss keyboard and prevent it from re-focusing
    @FocusState private var isMessageFocused: Bool

    // State for client-driven "Load My Reviews" flow
    @State private var myReviews: [FirestoreManager.ReviewItem] = []
    @State private var loadingMyReviews: Bool = false
    @State private var myReviewsLoaded: Bool = false

    // Computed lists to split reviews for the current user
    private var reviewsAboutUser: [FirestoreManager.ReviewItem] {
        guard let uid = auth.user?.uid else { return [] }
        return firestore.reviews.filter { $0.coachID == uid }
    }

    private var reviewsByUser: [FirestoreManager.ReviewItem] {
        guard let uid = auth.user?.uid else { return [] }
        return firestore.reviews.filter { $0.clientID == uid }
    }

    // Inline suggestions for coach names (contains match)
    private var coachSuggestions: [Coach] {
        let typed = coachSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard typed.count >= 1 else { return [] }
        return firestore.coaches.filter { $0.name.lowercased().contains(typed) }
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
                    // If the user is a client, provide a navigation link to a dedicated screen
                    Section(header: Text("Your Reviews")) {
                        NavigationLink(destination: ReviewsByUserView().environmentObject(firestore).environmentObject(auth)) {
                            Text("View My Reviews")
                                .padding(.vertical, 8)
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

                    // Reviews written by the current user (fallback view) - link to dedicated screen
                    Section(header: Text("Your Reviews")) {
                        NavigationLink(destination: ReviewsByUserView().environmentObject(firestore).environmentObject(auth)) {
                            Text("View My Reviews")
                                .padding(.vertical, 8)
                        }
                    }
                }

                // Write a review form remains unchanged but is only shown to CLIENT users
                if userType == "CLIENT" {
                    Section(header: Text("Write a Review")) {
                        if firestore.coaches.isEmpty {
                            Text("No coaches available").foregroundColor(.secondary)
                        } else {
                            // Searchable coach picker: type to filter and tap a suggestion to select
                            VStack(alignment: .leading, spacing: 8) {
                                SearchBar(text: $coachSearchText, placeholder: "Search coach by name")

                                if !coachSuggestions.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(coachSuggestions.prefix(8), id: \.id) { coach in
                                                Button(action: {
                                                    selectedCoachId = coach.id
                                                    selectedCoachName = coach.name
                                                    coachSearchText = coach.name
                                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                                }) {
                                                    HStack(spacing: 8) {
                                                        let coachURL = firestore.coachPhotoURLs[coach.id] ?? nil
                                                        AvatarView(url: coachURL ?? nil, size: 32, useCurrentUser: false)
                                                        Text(coach.name)
                                                            .foregroundColor(.primary)
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(Color(UIColor.secondarySystemBackground))
                                                    .cornerRadius(16)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }

                                if !selectedCoachName.isEmpty {
                                    HStack(spacing: 8) {
                                        let selURL = firestore.coachPhotoURLs[selectedCoachId] ?? nil
                                        AvatarView(url: selURL ?? nil, size: 36, useCurrentUser: false)
                                        Text("Selected: \(selectedCoachName)")
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }

                        Picker("Rating", selection: $rating) {
                            ForEach(1...5, id: \.self) { r in
                                Text(String(r)).tag(r)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())

                        TextEditor(text: $message)
                            .focused($isMessageFocused)
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
                // Do not auto-fetch all reviews for clients; let them load via the button.
                // Keep fetchAllReviews for coach scenarios where reviews-about-you are shown.
                if firestore.currentUserType?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "COACH" {
                    firestore.fetchAllReviews()
                }
            }
            .onChange(of: firestore.coaches) { _, newCoaches in
                // If previously selected coach no longer exists, clear selection
                let ids = newCoaches.map { $0.id }
                if !selectedCoachId.isEmpty && !ids.contains(selectedCoachId) {
                    selectedCoachId = ""
                    selectedCoachName = ""
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
        // Dismiss keyboard and ensure the editor is not focused so the cursor doesn't reappear
        DispatchQueue.main.async {
            isMessageFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
                    // Clear the message and keep focus cleared so keyboard stays hidden
                    message = ""
                    isMessageFocused = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
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
