import SwiftUI

/// MultiSelectDropdown
/// Expands to a full-width list of rows; tapping a row toggles selection and highlights the row.
struct MultiSelectDropdown: View {
    let title: String
    let items: [String]
    @Binding var selection: Set<String>
    var placeholder: String = "Select"

    @State private var expanded: Bool = false

    private var summaryText: String {
        if selection.isEmpty { return placeholder }
        let s = selection.sorted()
        if s.count <= 3 { return s.joined(separator: ", ") }
        return s.prefix(3).joined(separator: ", ") + " +\(s.count - 3)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(summaryText)
                        .font(.callout)
                        .foregroundColor(selection.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                Button(action: { withAnimation { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .padding(8)
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            if expanded {
                VStack(spacing: 0) {
                    ForEach(items, id: \.self) { item in
                        Button(action: {
                            if selection.contains(item) { selection.remove(item) } else { selection.insert(item) }
                        }) {
                            HStack {
                                Text(item)
                                    .foregroundColor(selection.contains(item) ? .white : .primary)
                                Spacer()
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(selection.contains(item) ? Color.accentColor : Color(UIColor.systemBackground))
                        }
                        .buttonStyle(PlainButtonStyle())

                        if item != items.last { Divider() }
                    }

                    Divider().padding(.top, 6)

                    HStack {
                        Spacer()
                        Button("Done") { withAnimation { expanded = false } }
                            .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(UIColor.separator)))
                .shadow(radius: 2)
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
                MultiSelectDropdown(title: "Goals", items: ["Badminton","Tennis","Coding","Pickleball","Basketball"], selection: $sel)
            }
            .padding()
        }
    }
    static var previews: some View { Wrapper() }
}
