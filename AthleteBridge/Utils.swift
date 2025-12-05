import SwiftUI

/// LazyView defers construction of its content until it's actually needed. Useful for
/// NavigationLink destinations that depend on latest @State values at activation time.
struct LazyView<Content: View>: View {
    private let build: () -> Content
    init(@ViewBuilder _ build: @escaping () -> Content) { self.build = build }
    var body: some View { build() }
}
