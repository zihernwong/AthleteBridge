import SwiftUI
import UIKit

/// AvatarView: shows the current user's client or coach photo (prefers client),
/// uses AsyncImage and falls back to a manual URLSession download for signed URLs.
struct AvatarView: View {
    @EnvironmentObject var firestore: FirestoreManager

    @State private var fallbackImage: UIImage? = nil
    @State private var isDownloadingFallback: Bool = false
    @State private var lastURLString: String? = nil

    private let size: CGFloat

    init(size: CGFloat = 44) {
        self.size = size
    }

    var body: some View {
        Group {
            if let clientURL = firestore.currentClientPhotoURL {
                imageFor(url: clientURL)
                    .onAppear { prepare(url: clientURL) }
            } else if let coachURL = firestore.currentCoachPhotoURL {
                imageFor(url: coachURL)
                    .onAppear { prepare(url: coachURL) }
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
