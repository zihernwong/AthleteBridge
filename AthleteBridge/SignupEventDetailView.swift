import SwiftUI

struct SignupEventDetailView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let event: SignupEvent
    @State private var isSigningUp = false
    @State private var showDeleteConfirmation = false
    @State private var signupError: String?

    private var currentUid: String? { auth.user?.uid }

    // Use liveEvent for all checks so UI updates after fetch
    private var liveEvent: SignupEvent {
        firestore.signupEvents.first { $0.id == event.id } ?? event
    }

    private var isCreator: Bool { currentUid == liveEvent.createdBy }
    private var isAlreadySignedUp: Bool {
        guard let uid = currentUid else { return false }
        return liveEvent.signups.contains { $0.userId == uid }
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        let ev = liveEvent
        List {
            // Event Info
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(ev.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    if !ev.description.isEmpty {
                        Text(ev.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundColor(Color("LogoGreen"))
                        Text(Self.dateFormatter.string(from: ev.eventDate))
                    }
                    .font(.subheadline)
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(Color("LogoGreen"))
                        Text(ev.location)
                    }
                    .font(.subheadline)
                    HStack(spacing: 6) {
                        Image(systemName: "person.2")
                            .foregroundColor(ev.isFull ? .red : Color("LogoGreen"))
                        Text(ev.isFull ? "Event is full" : "\(ev.spotsRemaining) of \(ev.maxSignups) spots remaining")
                            .fontWeight(.semibold)
                            .foregroundColor(ev.isFull ? .red : Color("LogoGreen"))
                    }
                    .font(.subheadline)
                }
                .padding(.vertical, 4)
            }

            // Share Link
            if let url = ev.shareURL {
                Section {
                    Button {
                        UIPasteboard.general.url = url
                        firestore.showToast("Copied to clipboard")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Share Signup Link", systemImage: "square.and.arrow.up")
                    }
                }
            }

            // Sign Up Button (anyone can sign up, including the creator)
            if !isAlreadySignedUp && !ev.isFull {
                Section {
                    Button {
                        isSigningUp = true
                        signupError = nil
                        firestore.signupForEvent(eventId: ev.id) { err in
                            DispatchQueue.main.async {
                                isSigningUp = false
                                if let err = err {
                                    signupError = err.localizedDescription
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSigningUp {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Sign Up")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isSigningUp)
                    if let error = signupError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            if isAlreadySignedUp {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color("LogoGreen"))
                        Text("You're signed up!")
                            .fontWeight(.semibold)
                            .foregroundColor(Color("LogoGreen"))
                    }
                }
            }

            // Attendees
            if !ev.signups.isEmpty {
                Section(header: Text("Signed Up (\(ev.signups.count))")) {
                    ForEach(ev.signups) { signup in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(signup.name)
                                    .font(.body)
                                if isCreator {
                                    Text(signup.email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if isCreator {
                                Button(role: .destructive) {
                                    firestore.removeSignupFromEvent(eventId: ev.id, signupId: signup.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Delete Event (creator only)
            if isCreator {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Event")
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                firestore.fetchSignupEvents()
            }
        }
        .confirmationDialog("Delete this event?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                firestore.deleteSignupEvent(id: ev.id) { _ in
                    DispatchQueue.main.async { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the event and all signups.")
        }
    }
}
