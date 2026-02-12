import SwiftUI
import UIKit

private let presetStrings = [
    "BG65", "BG65T", "BG66F", "BG66UM", "BG80", "BG80P",
    "EX63", "AB", "ABBT", "EX65", "EX68", "SKYARC"
]

struct StringerDetailView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    let stringer: BadmintonStringer

    @State private var showReviewSheet = false
    @State private var showOrderSheet = false
    @State private var linkedCoach: Coach? = nil

    private var currentUid: String { auth.user?.uid ?? "" }

    private var averageRating: Double {
        let reviews = firestore.stringerReviews
        guard !reviews.isEmpty else { return 0 }
        return Double(reviews.reduce(0) { $0 + $1.rating }) / Double(reviews.count)
    }

    var body: some View {
        List {
            // Stringer info with profile link
            Section {
                HStack(alignment: .top, spacing: 12) {
                    let photoURL = firestore.coachPhotoURLs[stringer.createdBy] ?? firestore.clientPhotoURLs[stringer.createdBy] ?? nil
                    AvatarView(url: photoURL, size: 56, useCurrentUser: false)

                    VStack(alignment: .leading, spacing: 4) {
                        if let coach = linkedCoach {
                            NavigationLink(destination: CoachDetailView(coach: coach).environmentObject(firestore)) {
                                Text(stringer.name)
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                        } else {
                            Text(stringer.name)
                                .font(.title2)
                                .fontWeight(.bold)
                        }

                        if !stringer.meetupLocationNames.isEmpty {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(.secondary)
                                Text(stringer.meetupLocationNames.joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Stringing info images
            Section(header: Text("Yonex Badminton Strings")) {
                VStack(spacing: 12) {
                    if let img1 = UIImage(named: "StringingInfo") ?? UIImage(contentsOfFile: Bundle.main.path(forResource: "StringingInfo", ofType: "png") ?? "") {
                        Image(uiImage: img1)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                    }
                    if let img2 = UIImage(named: "StringingInfoP2") ?? UIImage(contentsOfFile: Bundle.main.path(forResource: "StringingInfoP2", ofType: "png") ?? "") {
                        Image(uiImage: img2)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                    }
                }
            }

            // Strings offered
            if !stringer.stringsOffered.isEmpty {
                Section(header: Text("Strings Offered")) {
                    ForEach(sortedStringKeys(stringer.stringsOffered), id: \.self) { name in
                        HStack {
                            Text(name)
                                .font(.body)
                            Spacer()
                            if let cost = stringer.stringsOffered[name], !cost.isEmpty {
                                Text(cost)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // Stringer Reviews section
            Section(header: HStack {
                Text("Stringer Reviews")
                Spacer()
                if !firestore.stringerReviews.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text(String(format: "%.1f", averageRating))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("(\(firestore.stringerReviews.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }) {
                if firestore.stringerReviews.isEmpty {
                    Text("No stringer reviews yet. Be the first!")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(firestore.stringerReviews) { review in
                        StringerReviewRow(review: review, firestore: firestore)
                    }
                }

                Button(action: { showReviewSheet = true }) {
                    Label("Write a Stringer Review", systemImage: "square.and.pencil")
                }
            }

            // Manage Orders (only visible to stringer owner)
            if stringer.createdBy == currentUid {
                Section {
                    NavigationLink {
                        StringerIncomingOrdersView(stringer: stringer)
                            .environmentObject(firestore)
                    } label: {
                        HStack {
                            Image(systemName: "tray.full")
                                .foregroundColor(Color("LogoBlue"))
                            Text("Manage Orders")
                                .font(.body)
                            Spacer()
                        }
                    }
                }
            }

            // Order form button
            Section {
                Button(action: { showOrderSheet = true }) {
                    HStack {
                        Spacer()
                        Label("Place Stringing Order", systemImage: "cart")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color("LogoGreen"))
                    .cornerRadius(10)
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(stringer.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            firestore.fetchStringerReviews(stringerId: stringer.id)
            if firestore.coaches.isEmpty { firestore.fetchCoaches() }
            linkedCoach = firestore.coaches.first(where: { $0.id == stringer.createdBy })
        }
        .onChange(of: firestore.coaches) { _, newCoaches in
            linkedCoach = newCoaches.first(where: { $0.id == stringer.createdBy })
        }
        .sheet(isPresented: $showReviewSheet) {
            AddStringerReviewView(stringer: stringer)
                .environmentObject(firestore)
        }
        .sheet(isPresented: $showOrderSheet) {
            StringerOrderFormView(stringer: stringer)
                .environmentObject(firestore)
        }
    }

    private func sortedStringKeys(_ strings: [String: String]) -> [String] {
        let order = presetStrings
        return strings.keys.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? Int.max
            let ib = order.firstIndex(of: b) ?? Int.max
            return ia < ib
        }
    }
}

// MARK: - Stringer Review Row

private struct StringerReviewRow: View {
    let review: StringerReview
    let firestore: FirestoreManager

    private var reviewerPhotoURL: URL? {
        if let url = firestore.coachPhotoURLs[review.createdBy] { return url }
        if let url = firestore.clientPhotoURLs[review.createdBy] { return url }
        return nil
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").map { String($0) }
        if parts.isEmpty { return "?" }
        if parts.count == 1 { return String(parts[0].prefix(1)).uppercased() }
        return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Reviewer avatar
            if let url = reviewerPhotoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: 36, height: 36).clipShape(Circle())
                    default:
                        Text(initials(from: review.reviewerName))
                            .font(.caption).foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.gray))
                    }
                }
            } else {
                Text(initials(from: review.reviewerName))
                    .font(.caption).foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.gray))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(review.reviewerName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= review.rating ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                                .font(.caption2)
                        }
                    }
                }
                if !review.comment.isEmpty {
                    Text(review.comment)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text(review.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Stringer Review Sheet

struct AddStringerReviewView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss
    let stringer: BadmintonStringer

    @State private var rating = 5
    @State private var comment = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Rating")) {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Button(action: { rating = star }) {
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .foregroundColor(.yellow)
                                    .font(.title2)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Comment")) {
                    TextEditor(text: $comment)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Stringer Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        isSaving = true
                        firestore.addStringerReview(
                            stringerId: stringer.id,
                            rating: rating,
                            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines)
                        ) { err in
                            DispatchQueue.main.async {
                                isSaving = false
                                if err == nil { dismiss() }
                            }
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}

// MARK: - Order Form Sheet

struct StringerOrderFormView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss
    let stringer: BadmintonStringer

    @State private var racketName = ""
    @State private var hasOwnString = false
    @State private var selectedString: String?
    @State private var tension = 24
    @State private var timelinePreference = "No rush"
    @State private var isSaving = false
    @State private var showSuccess = false

    private let timelineOptions = ["ASAP", "Within 1 day", "Within 3 days", "No rush"]

    private var sortedStringKeys: [String] {
        let order = presetStrings
        return stringer.stringsOffered.keys.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? Int.max
            let ib = order.firstIndex(of: b) ?? Int.max
            return ia < ib
        }
    }

    private var isValid: Bool {
        !racketName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (hasOwnString || selectedString != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Racket")) {
                    TextField("Racket Name (e.g. Yonex Astrox 88D)", text: $racketName)
                }

                Section(header: Text("String")) {
                    Toggle("I have my own string", isOn: $hasOwnString)
                        .tint(Color("LogoGreen"))

                    if !hasOwnString && !stringer.stringsOffered.isEmpty {
                        Text("Select a string from this stringer:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(sortedStringKeys, id: \.self) { name in
                            Button(action: { selectedString = name }) {
                                HStack {
                                    Image(systemName: selectedString == name ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedString == name ? Color("LogoGreen") : .secondary)
                                    Text(name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if let cost = stringer.stringsOffered[name], !cost.isEmpty {
                                        Text(cost)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                Section(header: Text("Tension (lbs)")) {
                    Stepper("\(tension) lbs", value: $tension, in: 16...35)
                }

                Section(header: Text("Timeline Preference")) {
                    ForEach(timelineOptions, id: \.self) { option in
                        Button(action: { timelinePreference = option }) {
                            HStack {
                                Image(systemName: timelinePreference == option ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(timelinePreference == option ? Color("LogoGreen") : .secondary)
                                Text(option)
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle("Stringing Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        isSaving = true
                        let chosenString = hasOwnString ? nil : selectedString
                        let cost = chosenString.flatMap { stringer.stringsOffered[$0] }
                        firestore.submitStringerOrder(
                            stringerId: stringer.id,
                            racketName: racketName.trimmingCharacters(in: .whitespacesAndNewlines),
                            hasOwnString: hasOwnString,
                            selectedString: chosenString,
                            stringCost: cost,
                            tension: tension,
                            timelinePreference: timelinePreference,
                            stringerCreatedBy: stringer.createdBy
                        ) { err in
                            DispatchQueue.main.async {
                                isSaving = false
                                if err == nil {
                                    showSuccess = true
                                }
                            }
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .alert("Order Submitted", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your stringing order has been submitted to \(stringer.name).")
            }
            .onChange(of: hasOwnString) { _ in
                if hasOwnString { selectedString = nil }
            }
        }
    }
}
