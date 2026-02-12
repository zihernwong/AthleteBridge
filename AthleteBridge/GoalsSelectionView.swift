import SwiftUI

struct GoalsSelectionView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) var dismiss

    @Binding var selection: Set<String>
    let options: [String]

    @State private var query: String = ""
    @State private var showingSuggestSheet: Bool = false
    @State private var suggestedText: String = ""
    @State private var isAdding: Bool = false
    // locally track newly added titles so the UI reflects them immediately
    @State private var newlyAdded: [String] = []

    // Combine server-provided subjects with the static `options` and any newly added entries,
    // remove duplicates while preserving order. This ensures newly submitted goals show up immediately
    // and that server updates still take precedence once fetched.
    private var allOptions: [String] {
        // assume FirestoreManager.subjects is an array of objects with `title` property
        let remote = firestore.subjects.map { $0.title }
        let combined = remote + newlyAdded + options
        var seen = Set<String>()
        var result: [String] = []
        for item in combined {
            if !seen.contains(item) {
                seen.insert(item)
                result.append(item)
            }
        }
        return result
    }

    private var filtered: [String] {
        let list = allOptions
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return list }
        return list.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search goals", text: $query)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemBackground)))
                .padding(.horizontal)
                .padding(.top, 8)

                List {
                    ForEach(filtered, id: \.self) { item in
                        Button(action: { toggle(item) }) {
                            HStack {
                                Text(item)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selection.contains(item) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(UIColor.systemGray))
                                }
                            }
                            .padding(.vertical, 8)
                            // make the hit area span the full row width
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .listRowBackground(Color.clear)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .listStyle(.insetGrouped)
                // add a larger top padding so the insetGrouped rounded background starts lower
                .padding(.top, 22)

                VStack(spacing: 12) {
                    Button(action: { showingSuggestSheet = true }) {
                        HStack {
                            Image(systemName: "lightbulb")
                            Text("Suggest a new goal")
                            Spacer()
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.tertiarySystemBackground)))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Select Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
            .sheet(isPresented: $showingSuggestSheet) {
                NavigationStack {
                    Form {
                        Section(header: Text("Suggest a new goal")) {
                            TextField("Goal name", text: $suggestedText)
                        }
                        Section {
                            Button(action: submitSuggestion) {
                                HStack { Spacer(); if isAdding { ProgressView() } else { Text("Submit") }; Spacer() }
                            }
                            .disabled(suggestedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)
                        }
                    }
                    .navigationTitle("Suggest Goal")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Close") { showingSuggestSheet = false } } }
                }
            }
        }
        .onAppear {
            // ensure we have latest subjects
            firestore.fetchSubjects()
        }
    }

    private func toggle(_ item: String) {
        if selection.contains(item) { selection.remove(item) } else { selection.insert(item) }
    }

    private func submitSuggestion() {
        let title = suggestedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        isAdding = true
        firestore.addSubject(title: title) { err in
            DispatchQueue.main.async {
                isAdding = false
                if let err = err {
                    firestore.showToast("Failed: \(err.localizedDescription)")
                } else {
                    firestore.showToast("Suggestion submitted")
                    // reflect immediately in the UI: add to local cache and select
                    if !newlyAdded.contains(title) {
                        newlyAdded.append(title)
                    }
                    selection.insert(title)
                    // refresh canonical data from server
                    firestore.fetchSubjects()
                    suggestedText = ""
                    showingSuggestSheet = false
                }
            }
        }
    }
}
