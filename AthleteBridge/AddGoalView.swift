import SwiftUI

struct AddGoalView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var dynamicLists: DynamicLists

    @State private var title: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("New Goal")) {
                    TextField("Goal title", text: $title)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                    if let err = errorMessage {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }
                Section {
                    Button(action: save) {
                        HStack {
                            Spacer()
                            if isSaving { ProgressView() }
                            else { Text("Add Goal") }
                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle("Add Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "Please enter a title"; return }
        isSaving = true
        dynamicLists.addGoal(title: trimmed) { result in
            DispatchQueue.main.async {
                self.isSaving = false
                switch result {
                case .success():
                    presentationMode.wrappedValue.dismiss()
                case .failure(let err):
                    self.errorMessage = err.localizedDescription
                }
            }
        }
    }
}

struct AddGoalView_Previews: PreviewProvider {
    static var previews: some View {
        AddGoalView(dynamicLists: DynamicLists())
    }
}
