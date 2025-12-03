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

    // Common fields
    @State private var name: String = ""

    // Client fields: fixed multi-select goals
    @State private var selectedGoals: Set<String> = []
    private let availableGoals: [String] = ["Badminton", "Pickleball", "Career Consulting", "Tennis", "Basketball", "Coding", "Financial Planning"]
    // client preferred availability now supports multiple selections
    @State private var selectedClientAvailability: Set<String> = []
    private let availableAvailability: [String] = ["Morning", "Afternoon", "Evening"]
    // Client skill level selection — removed 'No Preference' option per request
    private let skillLevels: [String] = ["Beginner", "Intermediate", "Advanced"]
    @State private var selectedClientSkillLevel: String = "Beginner"
    // Meeting preference options: client does not get a 'No preference' choice
    private let meetingOptionsClient: [String] = ["In-Person", "Virtual"]
    private let meetingOptionsCoach: [String] = ["In-Person", "Virtual"]
    @State private var selectedClientMeetingPreference: String = "In-Person"

    // Coach fields: fixed multi-select specialties
    @State private var selectedSpecialties: Set<String> = []
    private let availableSpecialties: [String] = ["Badminton", "Pickleball", "Career Consulting", "Tennis", "Basketball", "Coding", "Financial Planning"]
    @State private var experienceYears: Int = 0
    @State private var coachAvailabilitySelection: [String] = ["Morning"]
    @State private var hourlyRateText: String = ""
    @State private var bioText: String = ""
    // New: coach meeting preference (no "No preference" option - must choose In-Person or Virtual)
    @State private var selectedCoachMeetingPreference: String = "In-Person"

    // Location fields (zip -> city auto-populated)
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

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            NavigationView {
                Form {
                    if isEditMode {
                        emailSection
                    }
                    // Role selection removed: the app determines role from Firestore (userType) or existing profiles.
                    // The form will automatically show either clientSection or coachSection based on the user's role.
                    
                    nameSection
                    if role == .client {
                        clientSection
                    } else {
                        coachSection
                    }
                    photoSection
                    saveSection
                }
                .navigationTitle(isEditMode ? "Edit Profile" : "Create Profile")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Logout") {
                            // Always sign the user out from this screen (both Create and Edit flows)
                            auth.logout()
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
                .onAppear {
                    // Ensure Firestore attempts to load the current user's client/coach documents
                    if let uid = auth.user?.uid {
                        firestore.fetchCurrentProfiles(for: uid)
                        // Ensure we have userType (may already be loaded elsewhere)
                        firestore.fetchUserType(for: uid)
                    }

                    // If userType is already known, set role accordingly; otherwise fall back to any loaded profile
                    if let t = firestore.currentUserType?.uppercased() {
                        role = (t == "COACH") ? .coach : .client
                    } else if firestore.currentCoach != nil {
                        role = .coach
                    } else if firestore.currentClient != nil {
                        role = .client
                    }

                    // Populate fields if any profile is already loaded
                    populateFromExisting()
                    updateModeForRole()
                }
                // React to changes in user auth
                .onReceive(auth.$user) { user in
                    if let uid = user?.uid {
                        firestore.fetchCurrentProfiles(for: uid)
                        firestore.fetchUserType(for: uid)
                    }
                }
                // React to changes in userType (e.g. fetched from Firestore) and update role appropriately
                .onReceive(firestore.$currentUserType) { newType in
                    if let t = newType?.uppercased() {
                        role = (t == "COACH") ? .coach : .client
                        if let uid = auth.user?.uid { firestore.fetchCurrentProfiles(for: uid) }
                        populateFromExisting()
                        updateModeForRole()
                    }
                }
                // If auth.user becomes available after this view appears, trigger profile fetch
                .onReceive(auth.$user) { user in
                    if let uid = user?.uid {
                        firestore.fetchCurrentProfiles(for: uid)
                    }
                }
                // React to asynchronous updates from Firestore so the UI updates into Edit mode
                .onReceive(firestore.$currentClient) { _ in
                    updateModeForRole()
                }
                .onReceive(firestore.$currentCoach) { _ in
                    updateModeForRole()
                }
            }

            if showSavedConfirmation {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Profile saved")
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .cornerRadius(12)
                        Spacer()
                    }
                    .padding(.bottom, 60)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut, value: showSavedConfirmation)
            }

            // Improved global copied confirmation toast (centered rounded card with icon + blur)
            if showCopiedConfirmation {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                            Text("Email copied to clipboard")
                                .foregroundColor(.white)
                                .font(.subheadline)
                                .bold()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(12)
                        .shadow(radius: 8, y: 2)
                        .onTapGesture { withAnimation { showCopiedConfirmation = false } }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 60)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut, value: showCopiedConfirmation)
            }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoPicker(selectedImage: $selectedImage)
        }
    }

    // MARK: - View pieces
    private var emailSection: some View {
        Group {
            if let email = auth.user?.email {
                HStack(spacing: 12) {
                    // Fixed-size circular icon to keep vertical centering stable
                    Image(systemName: "envelope.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .padding(10)
                        .background(Circle().fill(Color.accentColor))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in as")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(email)
                            .font(.body).bold()
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button(action: {
                        UIPasteboard.general.string = email
                        // Haptic feedback
                        let gen = UIImpactFeedbackGenerator(style: .light)
                        gen.impactOccurred()
                        // Accessibility announcement
                        UIAccessibility.post(notification: .announcement, argument: "Email copied to clipboard")
                        withAnimation { showCopiedConfirmation = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { showCopiedConfirmation = false }
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(14)
                // Give the container a stable height so content is vertically centered
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
                // Use default form insets instead of negative padding for alignment
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
        .padding(.bottom, 8)
    }

    private var nameSection: some View {
        Section(header: Text("Full Name")) {
            TextField("Full Name", text: $name)
        }
    }

    private var clientSection: some View {
        Section(header: Text("Client Details")) {
            Text("Goals")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // chip-style multi-select list
            ChipMultiSelect(items: availableGoals, selection: $selectedGoals)

            Text("Preferred Availability")
                .font(.subheadline)
                .foregroundColor(.secondary)
            ChipMultiSelect(items: availableAvailability, selection: $selectedClientAvailability)

            Text("Meeting Preference")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Picker("Meeting Preference", selection: $selectedClientMeetingPreference) {
                ForEach(meetingOptionsClient, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.vertical, 8)

            Text("Skill Level")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Picker("Skill Level", selection: $selectedClientSkillLevel) {
                ForEach(skillLevels, id: \.self) { level in
                    Text(level).tag(level)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.vertical, 8)

            // Location: Zip code input and auto-filled city
            VStack(alignment: .leading) {
                Text("Zip Code")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("e.g. 55401", text: $clientZipCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.top, 4)
                    .onChange(of: clientZipCode) { _, newZip in
                        // Lookup city as user types; debounce trivial here
                        lookupCity(forZip: newZip) { city in
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
            Text("Specialties")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ChipMultiSelect(items: availableSpecialties, selection: $selectedSpecialties)

            // Experience as a wheel picker (scrollable)
            VStack(alignment: .leading) {
                HStack {
                    Text("Experience (years)")
                    Spacer()
                    Text("\(experienceYears) yrs")
                        .foregroundColor(.secondary)
                }
                Picker(selection: $experienceYears, label: Text("Experience")) {
                    ForEach(0...70, id: \.self) { yr in
                        Text("\(yr)").tag(yr)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(maxHeight: 120)
            }

            Text("Availability")
                .font(.subheadline)
                .foregroundColor(.secondary)
            ChipMultiSelect(items: availableAvailability, selection: Binding(get: {
                Set(coachAvailabilitySelection)
            }, set: { newSet in
                coachAvailabilitySelection = Array(newSet)
            }))

            Text("Meeting Preference")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Picker("Meeting Preference", selection: $selectedCoachMeetingPreference) {
                ForEach(meetingOptionsCoach, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.vertical, 8)

            // Hourly rate input for coaches
            VStack(alignment: .leading) {
                Text("Hourly Rate (USD)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("e.g. 50.00", text: $hourlyRateText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.top, 4)
            }

            // Location: Zip code input and auto-filled city for coach
            VStack(alignment: .leading) {
                Text("Zip Code")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("e.g. 55401", text: $coachZipCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.top, 4)
                    .onChange(of: coachZipCode) { _, newZip in
                        lookupCity(forZip: newZip) { city in
                            if let city = city { self.coachCity = city }
                        }
                    }

                Text("City: \(coachCity.isEmpty ? "" : coachCity)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
            }

            // Bio: multiline text editor for coach biography
            VStack(alignment: .leading) {
                Text("Biography")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $bioText)
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(UIColor.separator)))
                    .padding(.top, 4)
            }
        }
    }

    private var photoSection: some View {
        Section(header: Text("Profile Photo")) {
            HStack {
                if let img = selectedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                } else if role == .client, let url = firestore.currentClientPhotoURL {
                    // show stored client photo
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 100, height: 100)
                        case .success(let image):
                            image.resizable().scaledToFill().frame(width: 100, height: 100).clipShape(Circle()).shadow(radius: 4)
                        case .failure(_):
                            Image(systemName: "person.crop.circle").resizable().frame(width: 80, height: 80).foregroundColor(.secondary)
                        @unknown default:
                            Image(systemName: "person.crop.circle").resizable().frame(width: 80, height: 80).foregroundColor(.secondary)
                        }
                    }
                } else if role == .coach, let url = firestore.currentCoachPhotoURL {
                    // show stored coach photo
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().frame(width: 100, height: 100)
                        case .success(let image):
                            image.resizable().scaledToFill().frame(width: 100, height: 100).clipShape(Circle()).shadow(radius: 4)
                        case .failure(_):
                            Image(systemName: "person.crop.circle").resizable().frame(width: 80, height: 80).foregroundColor(.secondary)
                        @unknown default:
                            Image(systemName: "person.crop.circle").resizable().frame(width: 80, height: 80).foregroundColor(.secondary)
                        }
                    }
                } else {
                    // Use AvatarView which handles AsyncImage + fallback download
                    AvatarView().environmentObject(firestore)
                }

                VStack(alignment: .leading) {
                    Button(selectedImage == nil ? "Choose Photo" : "Change Photo") { showingPhotoPicker = true }
                    if selectedImage != nil {
                        Text("Will be uploaded when saving profile")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let uploadError = uploadError {
                        Text(uploadError).foregroundColor(.red).font(.caption)
                    }
                }
            }
        }
    }

    private var saveSection: some View {
        Section {
            if isSaving || isUploadingImage {
                ProgressView()
            } else {
                Button(isEditMode ? "Save Changes" : "Save Profile") { saveProfile() }
                    .disabled((role == .client && selectedGoals.isEmpty) || (role == .coach && selectedSpecialties.isEmpty))
            }

            if let msg = saveMessage { Text(msg).foregroundColor(.green) }

            // Validation message when no selection
            if role == .client && selectedGoals.isEmpty {
                Text("Please select at least one goal").foregroundColor(.red).font(.caption)
            } else if role == .coach && selectedSpecialties.isEmpty {
                Text("Please select at least one specialty").foregroundColor(.red).font(.caption)
            }
        }
    }

    // MARK: - Mode helpers
    /// Sets isEditMode and populates fields for the active role when existing profile data is present.
    private func updateModeForRole() {
        if role == .client {
            if let client = firestore.currentClient {
                isEditMode = true
                name = client.name
                selectedGoals = Set(client.goals)
                selectedClientAvailability = Set(client.preferredAvailability)
                // If stored meetingPreference exists, use it; otherwise default to first client option
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
                coachZipCode = coach.zipCode ?? ""
                coachCity = coach.city ?? ""
                // Default to first available meeting option if none stored
                selectedCoachMeetingPreference = coach.meetingPreference ?? meetingOptionsCoach.first!
                // Populate hourly rate text if available
                if let hr = coach.hourlyRate { hourlyRateText = String(format: "%.2f", hr) } else { hourlyRateText = "" }
            } else {
                isEditMode = false
            }
        }
    }

    // MARK: - Helpers
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
        } else if let coach = firestore.currentCoach {
             role = .coach
             name = coach.name
             selectedSpecialties = Set(coach.specialties)
             experienceYears = coach.experienceYears
             coachAvailabilitySelection = coach.availability
             bioText = coach.bio ?? ""
             // Default to first available meeting option if none stored
             selectedCoachMeetingPreference = coach.meetingPreference ?? meetingOptionsCoach.first!
             // Populate hourly rate if present
             if let hr = coach.hourlyRate { hourlyRateText = String(format: "%.2f", hr) } else { hourlyRateText = "" }
             coachZipCode = coach.zipCode ?? ""
             coachCity = coach.city ?? ""
         } else {
             isEditMode = false
         }
     }

    private func saveProfile() {
        guard let uid = auth.user?.uid else { saveMessage = "No authenticated user"; return }
        
        // Dismiss keyboard immediately when saving profile
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

         isSaving = true
         saveMessage = nil

        // Capture the environment object into a local strong reference to avoid
        // property-wrapper dynamic-member lookup issues when used inside nested
        // functions and asynchronous closures.
        let fm = self.firestore

        func finalizeSave(withPhotoURL photoURL: String?) {
            if role == .client {
                let goals = Array(selectedGoals)
                let preferred = Array(selectedClientAvailability)
                // save preferredAvailability as array for multi-select support
                // call existing API which accepts array after update
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
                        self.isSaving = false
                        if let err = err {
                            self.saveMessage = "Error saving client: \(err.localizedDescription)"
                        } else {
                            // Refresh cached profile so the stored photo URL is available immediately
                            fm.fetchCurrentProfiles(for: uid)
                             self.showSavedConfirmation = true
                             fm.showToast("Client profile saved")
                             DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                 self.showSavedConfirmation = false
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
                // No "No preference" option for coaches anymore; always save the selected preference
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
                        self.isSaving = false
                        if let err = err {
                            self.saveMessage = "Error saving coach: \(err.localizedDescription)"
                        } else {
                            // Refresh cached profile so the stored photo URL is available immediately
                            fm.fetchCurrentProfiles(for: uid)
                             self.showSavedConfirmation = true
                             fm.showToast("Coach profile saved")
                             DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                 self.showSavedConfirmation = false
                                 presentationMode.wrappedValue.dismiss()
                             }
                        }
                    }
                }
            }
        }

        // If there is a selected image, upload it first
        if let image = selectedImage {
            isUploadingImage = true
            uploadError = nil
            let maxDim: CGFloat = 1024
            guard let resized = image.resized(to: maxDim), let jpegData = resized.jpegData(compressionQuality: 0.75) else {
                isUploadingImage = false
                isSaving = false
                saveMessage = "Failed processing image"
                return
            }
            // Use Firebase Storage upload helper instead of Cloudinary
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

    // MARK: - Location helpers
    private func lookupCity(forZip zip: String, completion: ((String?) -> Void)? = nil) {
        let trimmed = zip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion?(nil); return }
        // Use CLGeocoder to attempt to resolve ZIP to a locality
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(trimmed) { placemarks, error in
            if let _ = error {
                DispatchQueue.main.async { completion?(nil) }
                return
            }
            let city = placemarks?.first?.locality ?? placemarks?.first?.subLocality ?? placemarks?.first?.administrativeArea
            DispatchQueue.main.async { completion?(city) }
        }
    }
}

// MARK: - Preview
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .environmentObject(AuthViewModel())
            .environmentObject(FirestoreManager())
    }
}

// Simple SwiftUI wrapper for PHPicker to pick a single image
struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first else { return }
            if item.itemProvider.canLoadObject(ofClass: UIImage.self) {
                item.itemProvider.loadObject(ofClass: UIImage.self) { (obj, _) in
                    if let image = obj as? UIImage {
                        DispatchQueue.main.async { self.parent.selectedImage = image }
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

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

// Local UIImage resizing helper accessible within the module
extension UIImage {
    func resized(to maxDimension: CGFloat) -> UIImage? {
        let aspect = size.width / size.height
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspect)
        } else {
            newSize = CGSize(width: maxDimension * aspect, height: maxDimension)
        }
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
    }
}

// Chip-style multi-select component
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

// Convenience helper to dismiss keyboard from SwiftUI
extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
