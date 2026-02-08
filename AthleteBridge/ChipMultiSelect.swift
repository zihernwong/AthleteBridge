import SwiftUI

/// AvailabilityChipSelect
/// Renders a small set of chips horizontally. For three items, centers each chip in an equal-width column
/// so gaps look perfectly even regardless of text length.
struct AvailabilityChipSelect: View {
    let items: [String]
    @Binding var selection: Set<String>

    // Chip style
    private func chip(for item: String) -> some View {
        let isSelected = selection.contains(item)
        return Button(action: {
            if isSelected { selection.remove(item) } else { selection.insert(item) }
        }) {
            Text(item)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? Color("LogoGreen") : Color(UIColor.secondarySystemBackground))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }

    var body: some View {
        // If exactly 3 items, place each chip in an equal-width column and center it.
        if items.count == 3 {
            HStack(alignment: .center, spacing: 0) {
                // Column 1
                VStack { chip(for: items[0]) }
                    .frame(maxWidth: .infinity)
                // Column 2
                VStack { chip(for: items[1]) }
                    .frame(maxWidth: .infinity)
                // Column 3
                VStack { chip(for: items[2]) }
                    .frame(maxWidth: .infinity)
            }
        } else {
            // Fallback: wrap in a flexible flow layout for other counts
            FlexibleChipWrap(items: items, selection: $selection)
        }
    }
}

/// A simple flexible wrap layout for chips when count != 3
/// Uses lazy grid with adaptive columns to wrap chips nicely.
fileprivate struct FlexibleChipWrap: View {
    let items: [String]
    @Binding var selection: Set<String>

    private func chip(for item: String) -> some View {
        let isSelected = selection.contains(item)
        return Button(action: {
            if isSelected { selection.remove(item) } else { selection.insert(item) }
        }) {
            Text(item)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? Color("LogoGreen") : Color(UIColor.secondarySystemBackground))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }

    var body: some View {
        // Adaptive columns ensure chips wrap; spacing handled by grid
        let columns = [GridItem(.adaptive(minimum: 120), spacing: 10)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                chip(for: item)
            }
        }
    }
}

struct AvailabilityChipSelect_Previews: PreviewProvider {
    struct Wrapper: View {
        @State var selection: Set<String> = []
        var body: some View {
            VStack(spacing: 20) {
                Text("Exactly 3 items (even gaps)")
                AvailabilityChipSelect(items: ["Morning","Afternoon","Evening"], selection: $selection)
                Divider()
                Text("Many items (wrap)")
                AvailabilityChipSelect(items: ["One","Two","Three","Four","Five","Six"], selection: $selection)
            }
            .padding()
        }
    }
    static var previews: some View { Wrapper() }
}
