import SwiftUI

struct MultiSelectPicker: View {
    let title: String
    let items: [String]
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss

    @State private var filter: String = ""

    private var filteredItems: [String] {
        if filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return items }
        return items.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filteredItems, id: \.self) { item in
                    Button(action: {
                        if selection.contains(item) { selection.remove(item) } else { selection.insert(item) }
                    }) {
                        HStack {
                            Text(item)
                                .foregroundColor(.primary)
                            Spacer()
                            if selection.contains(item) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct MultiSelectPicker_Previews: PreviewProvider {
    @State static var sel: Set<String> = ["Yoga instruction"]
    static var previews: some View {
        MultiSelectPicker(title: "Select", items: ["Yoga instruction","Meditation coaching","Running coaching"], selection: $sel)
    }
}
