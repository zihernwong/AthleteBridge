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

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Recent Reviews")) {
                    if firestore.reviews.isEmpty {
                        Text("No reviews yet").foregroundColor(.secondary)
                    } else {
                        ForEach(firestore.reviews) { item in
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
                        .onDelete(perform: delete)
                    }
                }

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
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    EditButton()
                    Button(action: { firestore.fetchAllReviews() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
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

    private func delete(at offsets: IndexSet) {
        // local deletion only for now; real deletion from Firestore requires document id and security rules
        // Remove the selected item from the reviews array shown
        let ids = offsets.map { firestore.reviews[$0].id }
        firestore.reviews.removeAll { ids.contains($0.id) }
    }
}

struct ReviewsView_Previews: PreviewProvider {
    static var previews: some View {
        ReviewsView()
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
