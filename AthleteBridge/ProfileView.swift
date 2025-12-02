import SwiftUI
import PhotosUI
import UIKit

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

    // Coach fields: fixed multi-select specialties
    @State private var selectedSpecialties: Set<String> = []
    private let availableSpecialties: [String] = ["Badminton", "Pickleball", "Career Consulting", "Tennis", "Basketball", "Coding", "Financial Planning"]
    @State private var experienceYears: Int = 0
    @State private var coachAvailabilitySelection: [String] = ["Morning"]
    @State private var hourlyRateText: String = ""
    @State private var bioText: String = ""

    // Photo + UI state
    @State private var selectedImage: UIImage? = nil
    @State private var showingPhotoPicker = false
    @State private var isSaving = false
    @State private var isUploadingImage = false
    @State private var uploadError: String? = nil
    @State private var saveMessage: String? = nil
    @State private var showSavedConfirmation: Bool = false
    // Tracks whether we are editing an existing profile (true) or creating a new one (false)
    @State private var isEditMode: Bool = false

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            NavigationView {
                Form {
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
                            // Sign the user out and dismiss the profile screen
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
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoPicker(selectedImage: $selectedImage)
        }
    }

    // MARK: - View pieces
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
        } else if let coach = firestore.currentCoach {
             role = .coach
             name = coach.name
             selectedSpecialties = Set(coach.specialties)
             experienceYears = coach.experienceYears
             coachAvailabilitySelection = coach.availability
             bioText = coach.bio ?? ""
        }
    }

    private func saveProfile() {
        guard let uid = auth.user?.uid else { saveMessage = "No authenticated user"; return }

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
                fm.saveClient(id: uid, name: name.isEmpty ? "Unnamed" : name, goals: goals, preferredAvailability: preferred, photoURL: photoURL) { err in
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
                fm.saveCoachWithSchema(id: uid, firstName: firstName, lastName: lastName, specialties: specialties, availability: coachAvailabilitySelection, experienceYears: experience, hourlyRate: hourlyRate, photoURL: photoURL, bio: bioText, active: true, overwrite: true) { err in
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
