import SwiftUI
import PhotosUI
import UIKit
import CoreLocation
import FirebaseFirestore

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
    // New: coach meeting preference (no "No preference" option - must choose In-Person or Virtual)
    private let meetingOptionsCoach: [String] = ["In-Person", "Virtual"]
    @State private var selectedCoachMeetingPreference: String = "In-Person"
    // Coach availability selection (stored as array of strings)
    @State private var coachAvailabilitySelection: [String] = ["Morning"]

    // Location
    @State private var clientZipCode: String = ""
    @State private var clientCity: String = ""
    @State private var coachZipCode: String = ""
    @State private var coachCity: String = ""

    // Photo + UI state
    @State private var selectedImage: UIImage? = nil
    @State private var showingPhotoPicker = false
    @State private var isSaving = false
    @State private var isUploadingImage = false
    @State private var uploadError: String? = nil
    @State private var saveMessage: String? = nil
    @State private var showSavedConfirmation: Bool = false
    @State private var showCopiedConfirmation: Bool = false
    // Tracks whether we are editing an existing profile (true) or creating a new one (false)
    @State private var isEditMode: Bool = false
    @State private var searchText: String = ""
    @State private var showingGoalsPicker: Bool = false

    // Goals selection sheet
    @State private var showingGoalsSheet: Bool = false

    // Dynamic subject IDs loaded from Firestore (document IDs of `subjects` collection)
    @State private var subjectIDs: [String] = []

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            NavigationView {
                Form {
                    // Show email row as soon as we have an authenticated user (email may load asynchronously)
                    if auth.user != nil {
                        emailSection
                    }
                    nameSection
                    if role == .client { clientSection } else { coachSection }
                    photoSection
                    saveSection
                }
                .navigationTitle((firestore.currentClient != nil || firestore.currentCoach != nil) ? "Edit Profile" : "Create Profile")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Logout") { auth.logout(); presentationMode.wrappedValue.dismiss() }
                    }
                }
                .onAppear {
                    // If auth is already available, fetch the user's profile documents
                    if let uid = auth.user?.uid {
                        firestore.fetchCurrentProfiles(for: uid)
                        firestore.fetchUserType(for: uid)
                    }
                    loadInitial()
                    fetchSubjectIDs()
                    // If profiles were already cached, populate fields
                    populateFromExisting()
                }
                // React to auth user changes (e.g. sign in) and refetch profiles
                .onReceive(auth.$user) { user in
                    if let uid = user?.uid {
                        firestore.fetchCurrentProfiles(for: uid)
                        firestore.fetchUserType(for: uid)
                    }
                }
                // React to userType changes to update role and populate fields
                .onReceive(firestore.$currentUserType) { newType in
                    if let t = newType?.uppercased() {
                        role = (t == "COACH") ? .coach : .client
                        populateFromExisting()
                    }
                }
                // React to Firestore manager updates so UI enters edit mode when profiles arrive
                .onReceive(firestore.$currentClient) { _ in
                    populateFromExisting()
                }
                .onReceive(firestore.$currentCoach) { _ in
                    populateFromExisting()
                }
                .sheet(isPresented: $showingGoalsSheet) {
                    GoalsSelectionView(selection: $selectedGoals, options: subjectIDs)
                        .environmentObject(firestore)
                }
            }

            // Copied confirmation toast (appears above the form)
            if showCopiedConfirmation {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.white)
                            Text("Email copied to clipboard").foregroundColor(.white).font(.subheadline).bold()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(12)
                        .shadow(radius: 8, y: 2)
                        .onTapGesture { withAnimation { showCopiedConfirmation = false } }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    // Position the toast above bottom tab bar by adding the safe-area bottom inset
                    .padding(.bottom, safeAreaBottom + 220)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut, value: showCopiedConfirmation)
                .zIndex(1000)
                .ignoresSafeArea(.container, edges: .bottom)
                .onAppear {
                    // auto-hide after a short delay as a fallback in case the caller didn't schedule dismissal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { showCopiedConfirmation = false }
                    }
                }
            }
        }
    }

    private var nameSection: some View {
        Section("Full Name") {
            TextField("Full Name", text: $name)
        }
    }

    private var clientSection: some View {
        Section("Client Details") {
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
                    .onChange(of: clientZipCode) {
                        // iOS 17+ recommended onChange signature: use the state directly
                        lookupCity(forZip: clientZipCode) { city in
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

    private var emailSection: some View {
        Group {
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .padding(10)
                    .background(Circle().fill(Color.accentColor))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Signed in as").font(.caption).foregroundColor(.secondary)
                    Text(auth.user?.email ?? "No email")
                        .font(.body).bold()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button(action: {
                    copyEmailToClipboard()
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(auth.user?.email == nil ? .gray : .blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(auth.user?.email == nil)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        .padding(.bottom, 8)
    }
    
    private var coachSection: some View {
        Section("Coach Details") {
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
        Section("Profile Photo") {
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
            VStack(alignment: .leading, spacing: 8) {
                if isSaving { ProgressView() }
                Button("Save Profile") { self.saveProfile() }
                    .disabled(isSaving)
                if let msg = saveMessage { Text(msg).foregroundColor(.green) }
            }
        }
    }

    // MARK: - Helpers (cleaned)
    // note: subject document IDs are loaded into `subjectIDs`
    private var defaultSubjects: [String] { [] }

    // Safe getter for the device's bottom safe-area inset using active window scene (avoids deprecated windows API)
    private var safeAreaBottom: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        // Prefer an active foreground scene
        let windowScene = scenes.first { ($0.activationState == .foregroundActive) } as? UIWindowScene ?? scenes.first as? UIWindowScene
        let window = windowScene?.windows.first { $0.isKeyWindow } ?? windowScene?.windows.first
        return window?.safeAreaInsets.bottom ?? 0
    }

    /// Copy authenticated user's email to clipboard and show temporary toast
    private func copyEmailToClipboard() {
        guard let email = auth.user?.email else { return }
        DispatchQueue.main.async {
            UIPasteboard.general.string = email
            let gen = UIImpactFeedbackGenerator(style: .light); gen.impactOccurred()
            UIAccessibility.post(notification: .announcement, argument: "Email copied to clipboard")
            withAnimation { showCopiedConfirmation = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { showCopiedConfirmation = false }
            }
        }
    }

    /// Fetch the document IDs from the `subjects` collection and store in `subjectIDs`.
    private func fetchSubjectIDs() {
        let db = Firestore.firestore()
        db.collection("subjects").getDocuments { snapshot, error in
            if let error = error {
                print("Error fetching subject IDs: \(error)")
                return
            }
            let ids = snapshot?.documents.map { $0.documentID } ?? []
            DispatchQueue.main.async { self.subjectIDs = ids }
        }
    }

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

    private func populateFromExisting() {
        if let client = firestore.currentClient {
            role = .client
            name = client.name
            selectedGoals = Set(client.goals)
            selectedClientAvailability = Set(client.preferredAvailability)
            selectedClientMeetingPreference = client.meetingPreference ?? meetingOptionsClient.first!
            selectedClientSkillLevel = client.skillLevel ?? "Beginner"
            clientZipCode = client.zipCode ?? ""
            clientCity = client.city ?? ""
            isEditMode = true
        } else if let coach = firestore.currentCoach {
            role = .coach
            name = coach.name
            selectedSpecialties = Set(coach.specialties)
            experienceYears = coach.experienceYears
            coachAvailabilitySelection = coach.availability
            bioText = coach.bio ?? ""
            selectedCoachMeetingPreference = coach.meetingPreference ?? meetingOptionsCoach.first!
            if let hr = coach.hourlyRate { hourlyRateText = String(format: "%.2f", hr) } else { hourlyRateText = "" }
            coachZipCode = coach.zipCode ?? ""
            coachCity = coach.city ?? ""
            isEditMode = true
        } else {
            isEditMode = false
        }
    }

    private func updateModeForRole() {
        if role == .client {
            if let client = firestore.currentClient {
                isEditMode = true
                name = client.name
                selectedGoals = Set(client.goals)
                selectedClientAvailability = Set(client.preferredAvailability)
                selectedClientMeetingPreference = client.meetingPreference ?? meetingOptionsClient.first!
                selectedClientSkillLevel = client.skillLevel ?? "Beginner"
                clientZipCode = client.zipCode ?? ""
                clientCity = client.city ?? ""
            } else {
                isEditMode = false
            }
        } else {
            if let coach = firestore.currentCoach {
                isEditMode = true
                name = coach.name
                selectedSpecialties = Set(coach.specialties)
                experienceYears = coach.experienceYears
                coachAvailabilitySelection = coach.availability
                bioText = coach.bio ?? ""
                selectedCoachMeetingPreference = coach.meetingPreference ?? meetingOptionsCoach.first!
                if let hr = coach.hourlyRate { hourlyRateText = String(format: "%.2f", hr) } else { hourlyRateText = "" }
                coachZipCode = coach.zipCode ?? ""
                coachCity = coach.city ?? ""
            } else {
                isEditMode = false
            }
        }
    }

    private func saveProfile() {
        guard let uid = auth.user?.uid else { saveMessage = "No authenticated user"; return }
        
        // Dismiss keyboard
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        isSaving = true
        saveMessage = nil
        let fm = self.firestore

        func finalizeSave(withPhotoURL photoURL: String?) {
            if role == .client {
                let goals = Array(selectedGoals)
                let preferred = Array(selectedClientAvailability)
                let meetingPrefToSave = selectedClientMeetingPreference
                let skillLevelToSave = selectedClientSkillLevel
                fm.saveClient(id: uid,
                              name: name.isEmpty ? "Unnamed" : name,
                              goals: goals,
                              preferredAvailability: preferred,
                              meetingPreference: meetingPrefToSave,
                              meetingPreferenceClear: false,
                              skillLevel: skillLevelToSave,
                              zipCode: clientZipCode.isEmpty ? nil : clientZipCode,
                              city: clientCity.isEmpty ? nil : clientCity,
                              photoURL: photoURL) { err in
                    DispatchQueue.main.async {
                        isSaving = false
                        if let err = err {
                            saveMessage = "Error saving client: \(err.localizedDescription)"
                        } else {
                            fm.fetchCurrentProfiles(for: uid)
                            showSavedConfirmation = true
                            fm.showToast("Client profile saved")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                showSavedConfirmation = false
                                presentationMode.wrappedValue.dismiss()
                            }
                        }
                    }
                }
            } else {
                let specialties = Array(selectedSpecialties)
                let experience = experienceYears
                let hourlyRate = Double(hourlyRateText)
                let parts = name.split(separator: " ").map { String($0) }
                let firstName = parts.first ?? (name.isEmpty ? "Unnamed" : name)
                let lastName = parts.dropFirst().joined(separator: " ")
                let meetingPrefToSave = selectedCoachMeetingPreference
                fm.saveCoachWithSchema(id: uid,
                                       firstName: firstName,
                                       lastName: lastName,
                                       specialties: specialties,
                                       availability: coachAvailabilitySelection,
                                       experienceYears: experience,
                                       hourlyRate: hourlyRate,
                                       meetingPreference: meetingPrefToSave,
                                       photoURL: photoURL,
                                       bio: bioText,
                                       zipCode: coachZipCode.isEmpty ? nil : coachZipCode,
                                       city: coachCity.isEmpty ? nil : coachCity,
                                       active: true,
                                       overwrite: true) { err in
                    DispatchQueue.main.async {
                        isSaving = false
                        if let err = err {
                            saveMessage = "Error saving coach: \(err.localizedDescription)"
                        } else {
                            fm.fetchCurrentProfiles(for: uid)
                            showSavedConfirmation = true
                            fm.showToast("Coach profile saved")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                showSavedConfirmation = false
                                presentationMode.wrappedValue.dismiss()
                            }
                        }
                    }
                }
            }
        }

        // If image selected, upload first
        if let image = selectedImage {
            isUploadingImage = true
            uploadError = nil
            let maxDim: CGFloat = 1024
            guard let resized = resizedImage(image, maxDim), let jpegData = resized.jpegData(compressionQuality: 0.75) else {
                isUploadingImage = false
                isSaving = false
                saveMessage = "Failed processing image"
                return
            }
            fm.uploadProfileImageToStorage(data: jpegData, filename: "\(uid).jpg") { result in
                DispatchQueue.main.async {
                    self.isUploadingImage = false
                    switch result {
                        case .success(let url): finalizeSave(withPhotoURL: url.absoluteString)
                        case .failure(let err): self.isSaving = false; self.uploadError = "Upload failed: \(err.localizedDescription)"; self.saveMessage = "Image upload failed"
                    }
                }
            }
        } else {
            finalizeSave(withPhotoURL: nil)
        }
    }
}

// MARK: - Helper types (file-scope)

// Simple chip multi-select used for availability and specialties
struct ChipMultiSelect: View {
    let items: [String]
    @Binding var selection: Set<String>
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button(action: {
                    if selection.contains(item) { selection.remove(item) } else { selection.insert(item) }
                }) {
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
                item.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let image = obj as? UIImage {
                        DispatchQueue.main.async { self.parent.selectedImage = image }
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

// image resize helper (used instead of UIImage.resized to ensure symbol available in this file scope)
fileprivate func resizedImage(_ image: UIImage, _ maxDimension: CGFloat) -> UIImage? {
    let aspect = image.size.width / image.size.height
    var newSize: CGSize
    if image.size.width > image.size.height {
        newSize = CGSize(width: maxDimension, height: maxDimension / aspect)
    } else {
        newSize = CGSize(width: maxDimension * aspect, height: maxDimension)
    }
    UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let resized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return resized
}
