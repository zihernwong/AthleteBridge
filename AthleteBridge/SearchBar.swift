import SwiftUI

/// A small reusable search bar with a magnifying icon, clear button, and rounded background.
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var onCommit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            // Use the TextField with commit
            TextField(placeholder, text: $text, onCommit: {
                onCommit?()
            })
            .autocapitalization(.none)
            .disableAutocorrection(true)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(10)
        // Draw a rounded grey background explicitly so the SearchBar appears the same inside Forms
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.separator).opacity(0.08), lineWidth: 1)
        )
    }
}

struct SearchBar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SearchBar(text: .constant(""), placeholder: "Search coaches")
                .padding()
                .previewLayout(.sizeThatFits)

            SearchBar(text: .constant("Alex"), placeholder: "Search")
                .padding()
                .previewLayout(.sizeThatFits)
        }
    }
}
