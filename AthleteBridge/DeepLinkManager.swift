import Foundation
import Combine

/// Describes where a push notification should navigate the user.
enum DeepLinkDestination: Equatable {
    case chat(chatId: String)
    case booking(bookingId: String)
}

/// Observable bridge between NotificationManager (singleton, outside SwiftUI)
/// and SwiftUI views that control navigation.
final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    /// Set by NotificationManager when a notification is tapped.
    /// Consumed (set to nil) by the SwiftUI view that handles the navigation.
    @Published var pendingDestination: DeepLinkDestination? = nil

    private init() {}
}
