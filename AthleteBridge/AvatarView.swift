import SwiftUI
import UIKit

/// In-memory image cache shared across all AvatarView instances to avoid re-downloading.
final class AvatarImageCache {
    static let shared = AvatarImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: Set<URL> = []
    private let lock = NSLock()

    private init() {
        cache.countLimit = 150
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }

    /// Returns true if this call claimed the in-flight slot (caller should fetch).
    func claimFetch(for url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if inFlight.contains(url) { return false }
        inFlight.insert(url)
        return true
    }

    func releaseFetch(for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        inFlight.remove(url)
    }
}

/// AvatarView: shows a profile image using an explicit URL, or optionally falls back to
/// the currently-signed-in client/coach photo stored in FirestoreManager.
struct AvatarView: View {
    @EnvironmentObject var firestore: FirestoreManager

    private let explicitURL: URL?
    private let displayName: String?
    private let useCurrentUser: Bool
    private let size: CGFloat

    @State private var loadedImage: UIImage? = nil

    init(url: URL? = nil, name: String? = nil, size: CGFloat = 44, useCurrentUser: Bool = true) {
        self.explicitURL = url
        self.displayName = name
        self.size = size
        self.useCurrentUser = useCurrentUser
    }

    private var resolvedURL: URL? {
        if let url = explicitURL { return url }
        if useCurrentUser, let clientURL = firestore.currentClientPhotoURL { return clientURL }
        if useCurrentUser, let coachURL = firestore.currentCoachPhotoURL { return coachURL }
        return nil
    }

    var body: some View {
        Group {
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            } else if resolvedURL != nil {
                ProgressView().frame(width: size, height: size)
            } else {
                initialsView
            }
        }
        .onAppear { loadImageIfNeeded() }
        .onChange(of: resolvedURL) { _, _ in loadImageIfNeeded() }
    }

    private var initialsView: some View {
        let nameToUse = displayName ?? (useCurrentUser ? (firestore.currentClient?.name ?? firestore.currentCoach?.name ?? "") : "")
        let initials = initialsFrom(name: nameToUse)
        return ZStack {
            Circle().fill(Color.gray.opacity(0.25))
            Text(initials)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }

    private func loadImageIfNeeded() {
        guard let url = resolvedURL else { loadedImage = nil; return }
        // Check cache first
        if let cached = AvatarImageCache.shared.image(for: url) {
            if loadedImage !== cached { loadedImage = cached }
            return
        }
        // Fetch if not already in-flight
        guard AvatarImageCache.shared.claimFetch(for: url) else { return }
        Task.detached {
            defer { AvatarImageCache.shared.releaseFetch(for: url) }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let ui = UIImage(data: data) {
                    AvatarImageCache.shared.set(ui, for: url)
                    await MainActor.run { self.loadedImage = ui }
                }
            } catch {
                // silently fail; initials view will show
            }
        }
    }

    private func initialsFrom(name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        let parts = trimmed.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        if parts.count == 1 {
            let p = parts[0]
            return String(p.prefix(2)).uppercased()
        } else {
            let first = parts.first?.prefix(1) ?? ""
            let last = parts.last?.prefix(1) ?? ""
            return (String(first) + String(last)).uppercased()
        }
    }
}

// Preview
struct AvatarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            AvatarView(name: "John Appleseed").environmentObject(FirestoreManager())
            AvatarView(size: 100).environmentObject(FirestoreManager())
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
