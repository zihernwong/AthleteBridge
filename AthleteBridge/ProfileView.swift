import SwiftUI
import PhotosUI
import UIKit
import CoreLocation

struct ProfileView: View {
    enum Role: String, CaseIterable, Identifiable {
        case client = "Client"
        case coach = "Coach"
        var id: String { rawValue }
    }

    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var firestore: FirestoreManager
    @State private var role: Role = .client

    // Common
    @State private var name: String = ""

    // Goals / specialties
    @State private var selectedGoals: Set<String> = []
    @State private var selectedSpecialties: Set<String> = []
    private let availableSpecialties: [String] = ["Badminton", "Pickleball", "Career Consulting", "Tennis", "Basketball", "Coding", "Financial Planning"]

    // Client UI: meeting preference, skill level
    private let meetingOptionsClient: [String] = ["In-Person", "Virtual"]
    private let skillLevels: [String] = ["Beginner", "Intermediate", "Advanced"]
    @State private var selectedClientMeetingPreference: String = "In-Person"
    @State private var selectedClientSkillLevel: String = "Beginner"

    // Availability
    @State private var selectedClientAvailability: Set<String> = []
    private let availableAvailability: [String] = ["Morning", "Afternoon", "Evening"]

    // Coach fields
    @State private var experienceYears: Int = 0
    @State private var hourlyRateText: String = ""
    @State private var bioText: String = ""

    // Location
    @State private var clientZipCode: String = ""
    @State private var clientCity: String = ""
    @State private var coachZipCode: String = ""
    @State private var coachCity: String = ""

    // Photo + UI state
    @State private var selectedImage: UIImage? = nil
    @State private var showingPhotoPicker = false
    @State private var isSaving = false
    @State private var saveMessage: String? = nil
    @State private var showSavedConfirmation: Bool = false

    // Goals selection sheet
    @State private var showingGoalsSheet: Bool = false

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            Form {
                nameSection
                if role == .client { clientSection } else { coachSection }
                photoSection
                saveSection
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Logout") { auth.logout(); presentationMode.wrappedValue.dismiss() }
                }
            }
            .onAppear { loadInitial() }
            .sheet(isPresented: $showingGoalsSheet) {
                GoalsSelectionView(selection: $selectedGoals, options: firestore.subjects.isEmpty ? defaultSubjects : firestore.subjects.map { $0.title })
                    .environmentObject(firestore)
            }
        }
    }

    private var nameSection: some View {
        Section(header: Text("Full Name")) {
            TextField("Full Name", text: $name)
        }
    }

    private var clientSection: some View {
        Section(header: Text("Client Details")) {
            VStack(alignment: .leading) {
                Text("Goals").font(.subheadline).foregroundColor(.secondary)
                Button(action: { showingGoalsSheet = true }) {
                    HStack {
                        Text(selectedGoals.isEmpty ? "Select goals" : selectedGoals.sorted().joined(separator: ", "))
                            .foregroundColor(selectedGoals.isEmpty ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.right") .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemBackground)))
                }
            }

            VStack(alignment: .leading) {
                Text("Preferred Availability").font(.subheadline).foregroundColor(.secondary)
                ChipMultiSelect(items: availableAvailability, selection: $selectedClientAvailability)
            }

            VStack(alignment: .leading) {
                Text("Meeting Preference").font(.subheadline).foregroundColor(.secondary)
                Picker("Meeting Preference", selection: $selectedClientMeetingPreference) {
                    ForEach(meetingOptionsClient, id: \.self) { option in
                        Text(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            VStack(alignment: .leading) {
                Text("Skill Level").font(.subheadline).foregroundColor(.secondary)
                Picker("Skill Level", selection: $selectedClientSkillLevel) {
                    ForEach(skillLevels, id: \.self) { level in
                        Text(level)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            // Zip code + city lookup
            VStack(alignment: .leading) {
                Text("Zip Code").font(.subheadline).foregroundColor(.secondary)
                TextField("e.g. 55401", text: $clientZipCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: clientZipCode) { newVal in
                        // small debounce not necessary here; perform a lookup when user finishes typing
                        lookupCity(forZip: newVal) { city in
                            if let city = city { self.clientCity = city }
                        }
                    }

                Text("City: \(clientCity.isEmpty ? "" : clientCity)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
            }
        }
    }

    private var coachSection: some View {
        Section(header: Text("Coach Details")) {
            VStack(alignment: .leading) {
                Text("Specialties").font(.subheadline).foregroundColor(.secondary)
                ChipMultiSelect(items: availableSpecialties, selection: $selectedSpecialties)
            }

            VStack(alignment: .leading) {
                Text("Experience (years)").font(.subheadline).foregroundColor(.secondary)
                Picker("Experience", selection: $experienceYears) {
                    ForEach(0...50, id: \.self) { yr in Text("\(yr)") }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(maxHeight: 120)
            }

            VStack(alignment: .leading) {
                Text("Hourly Rate (USD)").font(.subheadline).foregroundColor(.secondary)
                TextField("e.g. 50.00", text: $hourlyRateText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            VStack(alignment: .leading) {
                Text("Biography").font(.subheadline).foregroundColor(.secondary)
                TextEditor(text: $bioText).frame(minHeight: 120)
            }
        }
    }

    private var photoSection: some View {
        Section(header: Text("Profile Photo")) {
            HStack {
                if let img = selectedImage {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 90, height: 90).clipShape(Circle())
                } else if let url = firestore.currentClientPhotoURL, role == .client {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill().frame(width: 90, height: 90).clipShape(Circle()) }
                        else { Image(systemName: "person.crop.circle").resizable().frame(width: 90, height: 90).foregroundColor(.secondary) }
                    }
                } else if let url = firestore.currentCoachPhotoURL, role == .coach {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill().frame(width: 90, height: 90).clipShape(Circle()) }
                        else { Image(systemName: "person.crop.circle").resizable().frame(width: 90, height: 90).foregroundColor(.secondary) }
                    }
                } else {
                    Image(systemName: "person.crop.circle").resizable().frame(width: 90, height: 90).foregroundColor(.secondary)
                }

                VStack(alignment: .leading) {
                    Button(selectedImage == nil ? "Choose Photo" : "Change Photo") { showingPhotoPicker = true }
                    if selectedImage != nil { Text("Will be uploaded on save").font(.caption).foregroundColor(.secondary) }
                }
            }
            .sheet(isPresented: $showingPhotoPicker) { PhotoPicker(selectedImage: $selectedImage) }
        }
    }

    private var saveSection: some View {
        Section {
            if isSaving { ProgressView() }
            Button("Save Profile") { saveProfile() }.disabled(isSaving)
            if let msg = saveMessage { Text(msg).foregroundColor(.green) }
        }
    }

    // MARK: - Helpers
    private var defaultSubjects: [String] { ["Badminton", "Pickleball", "Career Consulting", "Tennis", "Basketball", "Coding", "Financial Planning"] }

    private func loadInitial() {
        if let t = firestore.currentUserType?.uppercased() { role = (t == "COACH") ? .coach : .client }
        firestore.fetchSubjects()
        if let client = firestore.currentClient {
            name = client.name
            selectedGoals = Set(client.goals)
            selectedClientAvailability = Set(client.preferredAvailability)
        }
        if let coach = firestore.currentCoach {
            name = coach.name
            selectedSpecialties = Set(coach.specialties)
            experienceYears = coach.experienceYears
            bioText = coach.bio ?? ""
        }
    }

    private func saveProfile() {
        guard let uid = auth.user?.uid else { saveMessage = "No authenticated user"; return }
        isSaving = true
        saveMessage = nil

        if role == .client {
            firestore.saveClient(id: uid, name: name.isEmpty ? "Unnamed" : name, goals: Array(selectedGoals), preferredAvailability: Array(selectedClientAvailability), meetingPreference: selectedClientMeetingPreference, meetingPreferenceClear: false, skillLevel: selectedClientSkillLevel, zipCode: clientZipCode.isEmpty ? nil : clientZipCode, city: clientCity.isEmpty ? nil : clientCity, photoURL: nil) { err in
                DispatchQueue.main.async {
                    isSaving = false
                    if let err = err { saveMessage = "Error: \(err.localizedDescription)" } else { saveMessage = "Saved"; firestore.fetchCurrentProfiles(for: uid) }
                }
            }
        } else {
            let parts = name.split(separator: " ").map(String.init)
            let first = parts.first ?? ""
            let last = parts.dropFirst().joined(separator: " ")
            firestore.saveCoachWithSchema(id: uid, firstName: first.isEmpty ? name : first, lastName: last, specialties: Array(selectedSpecialties), availability: Array(selectedClientAvailability), experienceYears: experienceYears, hourlyRate: Double(hourlyRateText), meetingPreference: nil, photoURL: nil, bio: bioText, zipCode: coachZipCode.isEmpty ? nil : coachZipCode, city: coachCity.isEmpty ? nil : coachCity, active: true, overwrite: true) { err in
                DispatchQueue.main.async {
                    isSaving = false
                    if let err = err { saveMessage = "Error: \(err.localizedDescription)" } else { saveMessage = "Saved"; firestore.fetchCurrentProfiles(for: uid) }
                }
            }
        }
    }

    // MARK: - Location helpers
    /// Lookup a city/locality for the provided ZIP code and return it via completion on the main thread.
    private func lookupCity(forZip zip: String, completion: ((String?) -> Void)? = nil) {
        let trimmed = zip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { DispatchQueue.main.async { completion?(nil) }; return }
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(trimmed) { placemarks, error in
            if let _ = error { DispatchQueue.main.async { completion?(nil) }; return }
            let city = placemarks?.first?.locality ?? placemarks?.first?.subLocality ?? placemarks?.first?.administrativeArea
            DispatchQueue.main.async { completion?(city) }
        }
    }
}

// Simple chip multi-select used for availability and specialties
struct ChipMultiSelect: View {
    let items: [String]
    @Binding var selection: Set<String>
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button(action: { if selection.contains(item) { selection.remove(item) } else { selection.insert(item) } }) {
                    Text(item)
                        .font(.subheadline)
                        .foregroundColor(selection.contains(item) ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selection.contains(item) ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                        .cornerRadius(20)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
}

// Photo picker
struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first else { return }
            if item.itemProvider.canLoadObject(ofClass: UIImage.self) {
                item.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                    if let image = obj as? UIImage {
                        DispatchQueue.main.async {
                            self?.parent.selectedImage = image
                        }
                    }
                }
            }
        }
    }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
}

extension UIImage {
    func resized(to maxDimension: CGFloat) -> UIImage? {
        let aspect = size.width / size.height
        var newSize: CGSize
        if size.width > size.height { newSize = CGSize(width: maxDimension, height: maxDimension / aspect) }
        else { newSize = CGSize(width: maxDimension * aspect, height: maxDimension) }
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
    }
}
