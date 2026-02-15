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
    @State private var selectedAdditionalTypes: Set<AdditionalUserType> = []
    @State private var showingAdditionalTypesSheet: Bool = false

    // Common
    @State private var name: String = ""

    // Goals / specialties
    @State private var selectedGoals: Set<String> = []
    @State private var selectedSpecialties: Set<String> = []
    @State private var showingSpecialtiesSheet: Bool = false
    // derive available specialties dynamically from Firestore subjects
    private var availableSpecialties: [String] { firestore.subjects.map { $0.title } }

    // Client UI: meeting preference, skill level
    private let meetingOptionsClient: [String] = ["In-Person", "Virtual"]
    private let skillLevels: [String] = ["Beginner", "Intermediate", "Advanced"]
    @State private var selectedClientMeetingPreference: String = "In-Person"
    @State private var selectedClientSkillLevel: String = "Beginner"

    // Availability
    @State private var selectedClientAvailability: Set<String> = []
    private let availableAvailability: [String] = ["Morning", "Afternoon", "Evening"]
    // New: client biography text
    @State private var clientBioText: String = ""
    @State private var clientTournamentSoftwareLink: String = ""

    // Coach fields
    @State private var experienceYears: Int = 0
    @State private var hourlyRateText: String = ""
    @State private var bioText: String = ""
    // New: coach meeting preference (no "No preference" option - must choose In-Person or Virtual)
    private let meetingOptionsCoach: [String] = ["In-Person", "Virtual"]
    @State private var selectedCoachMeetingPreference: String = "In-Person"
    // Coach availability selection (stored as array of strings)
    @State private var selectedCoachAvailability: Set<String> = []
    // New: coach rate range (lower, upper)
    @State private var coachRateLowerText: String = ""
    @State private var coachRateUpperText: String = ""
    @State private var coachTournamentSoftwareLink: String = ""

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
    // Tracks whether the form has been populated from existing data (prevents overwriting user input)
    @State private var hasPopulatedFromExisting: Bool = false
    @State private var showTournamentLinkInfo: Bool = false
    @State private var searchText: String = ""
    @State private var showingGoalsPicker: Bool = false

    // Goals selection sheet
    @State private var showingGoalsSheet: Bool = false

    // Dynamic subject IDs loaded from Firestore (document IDs of `subjects` collection)
    @State private var subjectIDs: [String] = []

    // Manage subscription sheet
    @State private var showingManageSubscription: Bool = false

    // Phone verification
    @State private var selectedCountryCode: CountryCode = .us
    @State private var localPhoneNumber: String = ""
    @State private var phoneCode: String = ""
    @FocusState private var phoneCodeFocused: Bool
    @State private var phoneSent: Bool = false
    @State private var phoneVerifySuccess: Bool = false

    /// Full E.164 phone number combining country code + local number
    private var phoneNumber: String {
        let digits = localPhoneNumber.filter { $0.isNumber }
        return selectedCountryCode.dialCode + digits
    }

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
                    photoSection
                    phoneVerificationSection
                    additionalTypesSection
                    if role == .client { clientSection } else { coachSection }
                    subscriptionSection
                    saveSection
                }
                .navigationTitle((firestore.currentClient != nil || firestore.currentCoach != nil) ? "Edit Profile" : "Create Profile")
                .navigationBarTitleDisplayMode(.inline)
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
                        // Sync subscription tier for coaches
                        firestore.syncSubscriptionTierFromStripe(for: uid)
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
                .sheet(isPresented: $showingSpecialtiesSheet) {
                    GoalsSelectionView(selection: $selectedSpecialties, options: subjectIDs)
                        .environmentObject(firestore)
                }
                .sheet(isPresented: $showingManageSubscription) {
                    ManageSubscriptionView()
                }
                .sheet(isPresented: $showingAdditionalTypesSheet) {
                    AdditionalTypesEditorView(
                        selectedTypes: $selectedAdditionalTypes,
                        onSave: { newTypes in
                            saveAdditionalTypes(newTypes)
                        }
                    )
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

    private var isPhoneVerified: Bool {
        // Check user-level flag first (persists in userType/{uid}), then fall back to profile-level
        if firestore.currentUserPhoneVerified { return true }
        if role == .coach { return firestore.currentCoach?.phoneVerified ?? false }
        return firestore.currentClient?.phoneVerified ?? false
    }

    private var nameSection: some View {
        Section("Full Name") {
            HStack {
                TextField("Full Name", text: $name)
                if isPhoneVerified {
                    VerifiedBadge()
                }
            }
        }
    }

    private var phoneVerificationSection: some View {
        Section("Phone Verification") {
            if isPhoneVerified {
                HStack {
                    VerifiedBadge()
                    Text("Phone Verified")
                        .foregroundColor(Color("LogoGreen"))
                }
            } else if phoneVerifySuccess {
                HStack {
                    VerifiedBadge()
                    Text("Phone Verified!")
                        .foregroundColor(Color("LogoGreen"))
                }
            } else if phoneSent {
                // Code entry step
                TextField("6-digit code", text: $phoneCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($phoneCodeFocused)
                Button(action: {
                    phoneCodeFocused = false
                    auth.errorMessage = nil
                    auth.confirmPhoneCode(phoneCode, firestore: firestore) { success in
                        if success { phoneVerifySuccess = true }
                    }
                }) {
                    if auth.phoneVerificationInProgress {
                        ProgressView()
                    } else {
                        Text("Verify Code")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(phoneCode.count < 6 || auth.phoneVerificationInProgress)
                if let err = auth.errorMessage {
                    Text(err).font(.caption).foregroundColor(.red)
                }
                Button("Resend Code") {
                    auth.sendPhoneVerification(phoneNumber: phoneNumber) { success in
                        if !success { phoneSent = false }
                    }
                }
                .font(.caption)
            } else {
                // Phone number entry step with country code picker
                HStack(spacing: 8) {
                    // Country code dropdown with flag
                    Menu {
                        ForEach(CountryCode.allCases) { country in
                            Button(action: { selectedCountryCode = country }) {
                                Text("\(country.flag) \(country.name) (\(country.dialCode))")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedCountryCode.flag)
                                .font(.title3)
                            Text(selectedCountryCode.dialCode)
                                .font(.body)
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }

                    TextField("Phone number", text: $localPhoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                Button(action: {
                    auth.errorMessage = nil
                    auth.sendPhoneVerification(phoneNumber: phoneNumber) { success in
                        if success { phoneSent = true }
                    }
                }) {
                    if auth.phoneVerificationInProgress {
                        ProgressView()
                    } else {
                        Text("Send Verification Code")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(localPhoneNumber.filter { $0.isNumber }.count < 4 || auth.phoneVerificationInProgress)
                if let err = auth.errorMessage {
                    Text(err).font(.caption).foregroundColor(.red)
                }
            }
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
                AvailabilityChipSelect(items: availableAvailability, selection: $selectedClientAvailability)
            }

            // Auto-add confirmed bookings to device calendar (opt-in)
            VStack(alignment: .leading) {
                Text("Calendar") .font(.subheadline).foregroundColor(.secondary)
                Toggle(isOn: Binding(get: { firestore.autoAddToCalendar }, set: { newVal in
                    firestore.setAutoAddToCalendar(newVal) { err in
                        if let err = err { print("setAutoAddToCalendar error: \(err)") }
                    }
                })) {
                    Text("Automatically add confirmed bookings to my Calendar")
                        .font(.subheadline)
                }
                .tint(Color("LogoGreen"))
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

            // Client Biography
            VStack(alignment: .leading) {
                Text("Biography").font(.subheadline).foregroundColor(.secondary)
                TextEditor(text: $clientBioText)
                    .frame(minHeight: 120)
            }

            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text("Tournamentsoftware Profile Link").font(.subheadline).foregroundColor(.secondary)
                    Button(action: { showTournamentLinkInfo.toggle() }) {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .popover(isPresented: $showTournamentLinkInfo) {
                        Text("e.g. https://www.tournamentsoftware.com/sport/player.aspx?id=...")
                            .font(.caption)
                            .padding()
                            .presentationCompactAdaptation(.popover)
                    }
                }
                TextField("Paste your profile link", text: $clientTournamentSoftwareLink)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
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
                    .background(Circle().fill(Color("LogoGreen")))

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
                        .foregroundColor(auth.user?.email == nil ? .gray : Color("LogoGreen"))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(auth.user?.email == nil)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            // Use the same background as the list to avoid a double-toned card overlap
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemBackground)))
            // Make the row flush with the list’s horizontal margins to fix edge overlap
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color(UIColor.systemGroupedBackground))
            .listRowSeparator(.hidden)
        }
        // Remove the extra bottom padding that caused visual misalignment
        .padding(.bottom, 0)
    }
    
    private var coachSection: some View {
        Section("Coach Details") {
            VStack(alignment: .leading) {
                Text("Specialties").font(.subheadline).foregroundColor(.secondary)
                Button(action: { showingSpecialtiesSheet = true }) {
                    HStack {
                        Text(selectedSpecialties.isEmpty ? "Select specialties" : selectedSpecialties.sorted().joined(separator: ", "))
                            .foregroundColor(selectedSpecialties.isEmpty ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.right") .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemBackground)))
                }
            }

            VStack(alignment: .leading) {
                Text("Availability").font(.subheadline).foregroundColor(.secondary)
                AvailabilityChipSelect(items: availableAvailability, selection: $selectedCoachAvailability)
            }

            // Auto-add confirmed bookings to device calendar (opt-in) for coaches
            VStack(alignment: .leading) {
                Text("Calendar") .font(.subheadline).foregroundColor(.secondary)
                Toggle(isOn: Binding(get: { firestore.autoAddToCalendar }, set: { newVal in
                    firestore.setAutoAddToCalendar(newVal) { err in
                        if let err = err { print("setAutoAddToCalendar error: \(err)") }
                    }
                })) {
                    Text("Automatically add confirmed bookings to my Calendar")
                        .font(.subheadline)
                }
                .tint(Color("LogoGreen"))
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

            // New Rate Range inputs
            VStack(alignment: .leading, spacing: 6) {
                Text("Rate Range (USD)").font(.subheadline).foregroundColor(.secondary)
                HStack {
                    TextField("Lower", text: $coachRateLowerText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Upper", text: $coachRateUpperText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }

            VStack(alignment: .leading) {
                Text("Biography").font(.subheadline).foregroundColor(.secondary)
                TextEditor(text: $bioText).frame(minHeight: 120)
            }

            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text("Tournamentsoftware Profile Link").font(.subheadline).foregroundColor(.secondary)
                    Button(action: { showTournamentLinkInfo.toggle() }) {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .popover(isPresented: $showTournamentLinkInfo) {
                        Text("e.g. https://www.tournamentsoftware.com/sport/player.aspx?id=...")
                            .font(.caption)
                            .padding()
                            .presentationCompactAdaptation(.popover)
                    }
                }
                TextField("Paste your profile link", text: $coachTournamentSoftwareLink)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
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

    private var additionalTypesSection: some View {
        Section("Additional Roles") {
            if selectedAdditionalTypes.isEmpty {
                Text("No additional roles selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                WrappingHStack(spacing: 8) {
                    ForEach(Array(selectedAdditionalTypes).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { type in
                        AdditionalTypeBadge(type: type)
                    }
                }
            }
            Button(action: { showingAdditionalTypesSheet = true }) {
                HStack {
                    Text("Manage Additional Roles")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func saveAdditionalTypes(_ newTypes: Set<AdditionalUserType>) {
        let newTypesArray = Set(newTypes.map { $0.rawValue })
        let currentTypesArray = Set(firestore.currentAdditionalTypes)
        let toAdd = Array(newTypesArray.subtracting(currentTypesArray))
        let toRemove = Array(currentTypesArray.subtracting(newTypesArray))
        guard !toAdd.isEmpty || !toRemove.isEmpty else { return }

        firestore.updateAdditionalTypes(add: toAdd, remove: toRemove) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.saveMessage = "Failed to update roles: \(error.localizedDescription)"
                } else {
                    self.selectedAdditionalTypes = newTypes
                    firestore.showToast("Additional roles updated")
                }
            }
        }
    }

    private var subscriptionSection: some View {
        Section("Subscription") {
            HStack {
                let tier = firestore.currentCoach?.subscriptionTier ?? .free
                Text(tier.displayName)
                    .font(.subheadline)
                    .bold()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(tierColor(tier).opacity(0.15)))
                    .foregroundColor(tierColor(tier))
                Spacer()
            }
            Button(action: { showingManageSubscription = true }) {
                HStack {
                    Text("Manage My Subscription")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemBackground)))
            }
        }
    }

    private func tierColor(_ tier: CoachTier) -> Color {
        switch tier {
        case .free: return .gray
        case .plus: return .blue
        case .pro: return .purple
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
            clientBioText = client.bio ?? ""
            clientTournamentSoftwareLink = client.tournamentSoftwareLink ?? ""
        }
        if let coach = firestore.currentCoach {
            name = coach.name
            selectedSpecialties = Set(coach.specialties)
            experienceYears = coach.experienceYears
            bioText = coach.bio ?? ""
            coachTournamentSoftwareLink = coach.tournamentSoftwareLink ?? ""
        }
    }

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
        // Only populate once to avoid overwriting user input
        guard !hasPopulatedFromExisting else { return }

        // Populate additional types from Firestore
        selectedAdditionalTypes = Set(
            firestore.currentAdditionalTypes.compactMap { AdditionalUserType(rawValue: $0) }
        )

        if let client = firestore.currentClient {
            role = .client
            name = client.name
            selectedGoals = Set(client.goals)
            selectedClientAvailability = Set(client.preferredAvailability)
            selectedClientMeetingPreference = client.meetingPreference ?? meetingOptionsClient.first!
            selectedClientSkillLevel = client.skillLevel ?? "Beginner"
            clientZipCode = client.zipCode ?? ""
            clientCity = client.city ?? ""
            clientBioText = client.bio ?? ""
            clientTournamentSoftwareLink = client.tournamentSoftwareLink ?? ""
            isEditMode = true
            hasPopulatedFromExisting = true
        } else if let coach = firestore.currentCoach {
            role = .coach
            name = coach.name
            selectedSpecialties = Set(coach.specialties)
            experienceYears = coach.experienceYears
            selectedCoachAvailability = Set(coach.availability)
            bioText = coach.bio ?? ""
            selectedCoachMeetingPreference = coach.meetingPreference ?? meetingOptionsCoach.first!
            if let hr = coach.hourlyRate { hourlyRateText = String(format: "%.2f", hr) } else { hourlyRateText = "" }
            coachZipCode = coach.zipCode ?? ""
            coachCity = coach.city ?? ""
            if let rr = coach.rateRange, rr.count == 2 {
                coachRateLowerText = rr.first.map { String(format: "%.2f", $0) } ?? ""
                coachRateUpperText = rr.last.map { String(format: "%.2f", $0) } ?? ""
            } else {
                coachRateLowerText = ""
                coachRateUpperText = ""
            }
            coachTournamentSoftwareLink = coach.tournamentSoftwareLink ?? ""
            isEditMode = true
            hasPopulatedFromExisting = true
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
                clientBioText = client.bio ?? ""
                clientTournamentSoftwareLink = client.tournamentSoftwareLink ?? ""
            } else {
                isEditMode = false
            }
        } else {
            if let coach = firestore.currentCoach {
                isEditMode = true
                name = coach.name
                selectedSpecialties = Set(coach.specialties)
                experienceYears = coach.experienceYears
                selectedCoachAvailability = Set(coach.availability)
                bioText = coach.bio ?? ""
                selectedCoachMeetingPreference = coach.meetingPreference ?? meetingOptionsCoach.first!
                if let hr = coach.hourlyRate { hourlyRateText = String(format: "%.2f", hr) } else { hourlyRateText = "" }
                coachZipCode = coach.zipCode ?? ""
                coachCity = coach.city ?? ""
                if let rr = coach.rateRange, rr.count == 2 {
                    coachRateLowerText = rr.first.map { String(format: "%.2f", $0) } ?? ""
                    coachRateUpperText = rr.last.map { String(format: "%.2f", $0) } ?? ""
                } else {
                    coachRateLowerText = ""
                    coachRateUpperText = ""
                }
                coachTournamentSoftwareLink = coach.tournamentSoftwareLink ?? ""
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
                                          bio: clientBioText.isEmpty ? nil : clientBioText,
                                          tournamentSoftwareLink: clientTournamentSoftwareLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : clientTournamentSoftwareLink.trimmingCharacters(in: .whitespacesAndNewlines),
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
                // Build rateRange from text fields
                let lower = Double(coachRateLowerText)
                let upper = Double(coachRateUpperText)
                let rateRangeToSave: [Double]? = {
                    if let l = lower, let u = upper { return [l, u] }
                    else if let l = lower { return [l] }
                    else if let u = upper { return [u] }
                    else { return nil }
                }()
                fm.saveCoachWithSchema(id: uid,
                                       firstName: firstName,
                                       lastName: lastName,
                                       specialties: specialties,
                                       availability: Array(selectedCoachAvailability),
                                       experienceYears: experience,
                                       hourlyRate: hourlyRate,
                                       meetingPreference: meetingPrefToSave,
                                       photoURL: photoURL,
                                       bio: bioText,
                                       zipCode: coachZipCode.isEmpty ? nil : coachZipCode,
                                       city: coachCity.isEmpty ? nil : coachCity,
                                       rateRange: rateRangeToSave,
                                       tournamentSoftwareLink: coachTournamentSoftwareLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : coachTournamentSoftwareLink.trimmingCharacters(in: .whitespacesAndNewlines)) { err in
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
                        .background(selection.contains(item) ? Color("LogoGreen") : Color(UIColor.secondarySystemBackground))
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

// MARK: - Additional Types Editor Sheet

struct AdditionalTypesEditorView: View {
    @Binding var selectedTypes: Set<AdditionalUserType>
    let onSave: (Set<AdditionalUserType>) -> Void

    @State private var localSelection: Set<AdditionalUserType>
    @Environment(\.dismiss) private var dismiss

    init(selectedTypes: Binding<Set<AdditionalUserType>>, onSave: @escaping (Set<AdditionalUserType>) -> Void) {
        self._selectedTypes = selectedTypes
        self.onSave = onSave
        self._localSelection = State(initialValue: selectedTypes.wrappedValue)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Select Additional Roles")) {
                    ForEach(AdditionalUserType.allCases) { type in
                        Button(action: {
                            if localSelection.contains(type) {
                                localSelection.remove(type)
                            } else {
                                localSelection.insert(type)
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: localSelection.contains(type) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(localSelection.contains(type) ? Color("LogoGreen") : .secondary)
                                    .font(.title3)
                                AdditionalTypeBadge(type: type)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Section {
                    Text("These roles appear as badges on your profile and help others identify your capabilities.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Additional Roles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(localSelection)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Wrapping HStack Layout

/// Simple wrapping layout for badges that flow to the next line when space runs out.
struct WrappingHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let width = proposal.replacingUnspecifiedDimensions().width
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for view in row.views {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let width = proposal.replacingUnspecifiedDimensions().width
        var rows: [Row] = []
        var currentRow: [LayoutSubview] = []
        var currentWidth: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentWidth + size.width > width && !currentRow.isEmpty {
                rows.append(Row(views: currentRow, height: currentRow.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0))
                currentRow = []
                currentWidth = 0
            }
            currentRow.append(view)
            currentWidth += size.width + spacing
        }

        if !currentRow.isEmpty {
            rows.append(Row(views: currentRow, height: currentRow.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0))
        }

        return rows
    }

    struct Row {
        let views: [LayoutSubview]
        let height: CGFloat
    }
}
