import Foundation
import FirebaseFirestore

// Extension to add subject documents where the document ID is a slugified version of the title.
// Creates an empty document (no extra fields) so the document key itself represents the goal.
extension FirestoreManager {
    private func slugify(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // remove diacritics
        s = s.folding(options: .diacriticInsensitive, locale: .current)
        // replace any non-alphanumeric character with hyphen
        s = s.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        // collapse multiple hyphens
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
        // trim hyphens
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s.isEmpty ? UUID().uuidString : s
    }

    /// Add a subject to the `subjects` collection using the title's slug as the document ID.
    /// If a document with that ID already exists, the call returns success (no-op).
    func addSubjectWithSlug(title: String, completion: @escaping (Error?) -> Void = { _ in }) {
        let id = slugify(title)
        let coll = Firestore.firestore().collection("subjects")
        let docRef = coll.document(id)
        // Check existence first to avoid overwriting
        docRef.getDocument { snapshot, error in
            if let error = error {
                completion(error); return
            }
            if let snap = snapshot, snap.exists {
                // already present
                completion(nil); return
            }
            // Create an empty document; store title as well if desired
            docRef.setData(["title": title]) { err in
                completion(err)
            }
        }
    }
}
