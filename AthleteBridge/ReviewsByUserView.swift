import SwiftUI

struct ReviewsByUserView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    @State private var reviews: [FirestoreManager.ReviewItem] = []
    @State private var loading: Bool = false

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if reviews.isEmpty {
                Text("You haven't written any reviews yet").foregroundColor(.secondary)
            } else {
                ForEach(reviews) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.coachName ?? "Coach")
                                .font(.headline)
                            Spacer()
                            Text(r.createdAt ?? Date(), style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 6) {
                            let stars = Int(r.rating ?? "0") ?? 0
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: i <= stars ? "star.fill" : "star")
                                    .foregroundColor(i <= stars ? .yellow : .secondary)
                            }
                        }
                        if let msg = r.ratingMessage {
                            Text(msg).font(.body)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("My Reviews")
        .onAppear {
            loadMyReviews()
        }
    }

    private func loadMyReviews() {
        guard let uid = auth.user?.uid else { return }
        loading = true
        firestore.fetchReviewsByClient(clientId: uid) { items in
            DispatchQueue.main.async {
                self.reviews = items
                self.loading = false
            }
        }
    }
}

struct ReviewsByUserView_Previews: PreviewProvider {
    static var previews: some View {
        ReviewsByUserView()
            .environmentObject(FirestoreManager())
            .environmentObject(AuthViewModel())
    }
}
