import SwiftUI

/// A simple disclosure-style multi-select dropdown. Shows a header that expands to a list of pill-style selectable items.
struct MultiSelectDropdown: View {
    let title: String
    let items: [String]
    @Binding var selection: Set<String>
    var placeholder: String = "Select"

    @State private var expanded: Bool = false

    private var summaryText: String {
        if selection.isEmpty { return placeholder }
        return selection.sorted().joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { withAnimation { expanded.toggle() } }) {
                    HStack(spacing: 8) {
                        Text(selection.isEmpty ? placeholder : "\(selection.count) selected")
                            .foregroundColor(selection.isEmpty ? .secondary : .primary)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            if expanded {
                // Use flow of pill buttons
                let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(items, id: \ .self) { item in
                        Button(action: {
                            if selection.contains(item) { selection.remove(item) } else { selection.insert(item) }
                        }) {
                            Text(item)
                                .font(.subheadline)
                                .foregroundColor(selection.contains(item) ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selection.contains(item) ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                                .cornerRadius(18)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 6)
    }
}

struct MultiSelectDropdown_Previews: PreviewProvider {
    struct Wrapper: View {
        @State var sel: Set<String> = ["Badminton"]
        var body: some View {
            Form {
                MultiSelectDropdown(title: "Goals", items: ["Badminton","Tennis","Coding"], selection: $sel)
            }
        }
    }
    static var previews: some View { Wrapper() }
}
