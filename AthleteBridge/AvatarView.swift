import SwiftUI
import UIKit

/// AvatarView: shows a profile image using an explicit URL, or optionally falls back to
/// the currently-signed-in client/coach photo stored in FirestoreManager.
struct AvatarView: View {
    @EnvironmentObject var firestore: FirestoreManager

    // Optional explicit URL to show (when listing many coaches we pass their URL)
    private let explicitURL: URL?
    // Whether to fall back to the currently-signed-in user's client/coach photo when explicitURL is nil
    private let useCurrentUser: Bool

    @State private var fallbackImage: UIImage? = nil
    @State private var isDownloadingFallback: Bool = false
    @State private var lastURLString: String? = nil

    private let size: CGFloat

    init(url: URL? = nil, size: CGFloat = 44, useCurrentUser: Bool = true) {
        self.explicitURL = url
        self.size = size
        self.useCurrentUser = useCurrentUser
    }

    var body: some View {
        Group {
            if let url = explicitURL {
                imageFor(url: url).onAppear { prepare(url: url) }
            } else if useCurrentUser, let clientURL = firestore.currentClientPhotoURL {
                imageFor(url: clientURL).onAppear { prepare(url: clientURL) }
            } else if useCurrentUser, let coachURL = firestore.currentCoachPhotoURL {
                imageFor(url: coachURL).onAppear { prepare(url: coachURL) }
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: size, height: size)
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func imageFor(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView().frame(width: size, height: size)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            case .failure(_):
                if let ui = fallbackImage {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                } else {
                    ZStack {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: size, height: size)
                            .foregroundColor(.secondary)
                        ProgressView()
                    }
                    .onAppear { tryFallbackDownload(url: url) }
                }
            @unknown default:
                placeholder
            }
        }
    }

    private func prepare(url: URL) {
        lastURLString = url.absoluteString
        tryFallbackDownload(url: url)
    }

    private func tryFallbackDownload(url: URL) {
        guard !isDownloadingFallback && fallbackImage == nil else { return }
        isDownloadingFallback = true

        Task.detached { @MainActor in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse {
                    print("AvatarView: manual download response: \(http.statusCode) for \(url.absoluteString)")
                }
                if let ui = UIImage(data: data) {
                    self.fallbackImage = ui
                }
            } catch {
                print("AvatarView fallback download failed: \(error) for \(url.absoluteString)")
            }
            self.isDownloadingFallback = false
        }
    }
}

// Preview
struct AvatarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            AvatarView().environmentObject(FirestoreManager())
            AvatarView(size: 100).environmentObject(FirestoreManager())
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
