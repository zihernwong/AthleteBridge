import Foundation
import Combine

/// Describes where a push notification should navigate the user.
enum DeepLinkDestination: Equatable {
    case chat(chatId: String)
    case booking(bookingId: String)
    case payments
}

/// Observable bridge between NotificationManager (singleton, outside SwiftUI)
/// and SwiftUI views that control navigation.
final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    /// Set by NotificationManager when a notification is tapped.
    /// Consumed (set to nil) by the SwiftUI view that handles the navigation.
    @Published var pendingDestination: DeepLinkDestination? = nil

    /// Optional notification type (e.g. "booking_confirmed") to help route to the correct screen.
    /// Consumed alongside pendingDestination.
    @Published var pendingBookingType: String? = nil

    private init() {}
}
