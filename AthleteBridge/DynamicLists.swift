import Foundation
import Combine
import SwiftUI
import FirebaseFirestore

/// Provides dynamic lists for UI options (goals, specialties, availability, meeting options).
/// This implementation listens to Firestore collection `goals` and updates `goals`.
@MainActor
final class DynamicLists: ObservableObject {
    @Published var goals: [String] = []
    @Published var specialties: [String] = []
    @Published var availability: [String] = []
    @Published var meetingOptionsClient: [String] = []
    @Published var meetingOptionsCoach: [String] = []

    private let db = Firestore.firestore()
    private var goalsListener: ListenerRegistration?

    init() {
        // Sensible defaults while Firestore loads
        self.goals = ["Badminton", "Pickleball", "Career Consulting", "Tennis", "Basketball", "Coding", "Financial Planning"]
        self.specialties = self.goals
        self.availability = ["Morning", "Afternoon", "Evening"]
        self.meetingOptionsClient = ["In-Person", "Virtual"]
        self.meetingOptionsCoach = ["In-Person", "Virtual"]
    }

    deinit {
        goalsListener?.remove()
    }

    /// Start listening / fetch all dynamic lists. Currently listens to `goals` collection and updates `goals` and `specialties`.
    /// Firestore document shape (recommended): { title: String, order: Int (optional), active: Bool (optional) }
    func fetchAll() {
        // Remove any existing listener
        goalsListener?.remove()

        // Listen to the `goals` collection; expects documents with `title` field
        goalsListener = db.collection("goals")
            .order(by: "order", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    // Keep defaults on error but log for debugging
                    print("DynamicLists: failed to listen to goals: \(error.localizedDescription)")
                    return
                }

                guard let docs = snapshot?.documents else {
                    // no docs -> keep defaults
                    return
                }

                // Map to (order, title) tuples and filter by active flag when present
                let mapped: [(Int, String)] = docs.compactMap { doc in
                    let data = doc.data()
                    let title = (data["title"] as? String) ?? doc.documentID
                    let order = (data["order"] as? Int) ?? Int.max
                    let active = (data["active"] as? Bool) ?? true
                    return active ? (order, title) : nil
                }
                .sorted(by: { $0.0 < $1.0 })

                let titles = mapped.map { $0.1 }

                DispatchQueue.main.async {
                    if !titles.isEmpty {
                        self.goals = titles
                        // By default keep specialties same as goals unless a dedicated collection is added
                        self.specialties = titles
                    }
                }
            }
    }

    // MARK: - Mutations
    enum DynamicListsError: LocalizedError {
        case emptyTitle
        case duplicateTitle
        case firestoreError(Error)

        var errorDescription: String? {
            switch self {
            case .emptyTitle: return "Title must not be empty"
            case .duplicateTitle: return "A goal with this title already exists"
            case .firestoreError(let err): return err.localizedDescription
            }
        }
    }

    /// Add a new goal to the `goals` collection.
    /// - Parameters:
    ///   - title: the visible label for the goal
    ///   - order: optional order index. If nil, the method will append using current count.
    ///   - completion: result completion on the main queue
    func addGoal(title: String, order: Int? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { DispatchQueue.main.async { completion(.failure(DynamicListsError.emptyTitle)) }; return }

        // Check for duplicates (case-insensitive). Use local cache for quick check, then confirm with Firestore.
        if goals.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            DispatchQueue.main.async { completion(.failure(DynamicListsError.duplicateTitle)) }
            return
        }

        // Confirm no duplicate exists server-side
        db.collection("goals").whereField("title", isEqualTo: trimmed).getDocuments { [weak self] snapshot, error in
            guard let self = self else { DispatchQueue.main.async { completion(.failure(DynamicListsError.firestoreError(NSError(domain: "DynamicLists", code: -1, userInfo: [NSLocalizedDescriptionKey: "Deinitialized"])) )) } ; return }
            if let error = error {
                DispatchQueue.main.async { completion(.failure(DynamicListsError.firestoreError(error))) }
                return
            }

            if let docs = snapshot?.documents, !docs.isEmpty {
                DispatchQueue.main.async { completion(.failure(DynamicListsError.duplicateTitle)) }
                return
            }

            // Compute order: prefer provided order, otherwise append at end using current highest order or count
            let writeOrder: Int
            if let provided = order { writeOrder = provided } else {
                // Try to derive from existing ordered values; fallback to count
                if let maxOrder = self.goals.indices.max() { writeOrder = maxOrder + 1 } else { writeOrder = self.goals.count }
            }

            let data: [String: Any] = [
                "title": trimmed,
                "order": writeOrder,
                "active": true,
                "createdAt": FieldValue.serverTimestamp()
            ]

            var ref: DocumentReference? = nil
            ref = self.db.collection("goals").addDocument(data: data) { err in
                if let err = err {
                    DispatchQueue.main.async { completion(.failure(DynamicListsError.firestoreError(err))) }
                    return
                }

                // Optimistically update local cache: append in-memory list if it doesn't already contain the title
                DispatchQueue.main.async {
                    if !self.goals.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                        self.goals.append(trimmed)
                        // Keep specialties in sync for now
                        self.specialties = self.goals
                    }
                    completion(.success(()))
                }
            }
        }
    }
}
