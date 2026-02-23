import SwiftUI
import FirebaseAuth

struct PlacesToPlayContactView: View {
    @EnvironmentObject var firestore: FirestoreManager

    /// When set (e.g. from a deep link), the view scrolls to the pending-requests
    /// section for this place ID on appear.
    var scrollToPlaceId: String? = nil

    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }

    private var myPlaces: [PlaceToPlay] {
        firestore.placesToPlay.filter { $0.contactUid == currentUid }
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            // My Places section
            Section {
                if firestore.placesToPlay.isEmpty {
                    Text("No places to play have been added yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(firestore.placesToPlay) { place in
                        let isMine = place.contactUid == currentUid
                        Button(action: { toggleContact(place: place, isMine: isMine) }) {
                            HStack(spacing: 12) {
                                Image(systemName: isMine ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isMine ? Color("LogoGreen") : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    if !place.address.isEmpty {
                                        Text(place.address)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if let contact = place.contactName, let uid = place.contactUid, uid != currentUid {
                                        Text("Contact: \(contact)")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } header: {
                Text("My Places")
            } footer: {
                Text("Select the places you are the contact for. Other users will see your name and be able to message you.")
            }

            // Club Management — pending requests, members, announcements
            if !myPlaces.isEmpty {
                ForEach(myPlaces) { place in
                    // Pending join requests
                    if !place.pendingMembers.isEmpty {
                        Section(header: Text("\(place.name) — Pending Requests").id("pending_\(place.id)")) {
                            ForEach(place.pendingMembers) { pending in
                                VStack(spacing: 10) {
                                    HStack(spacing: 12) {
                                        AvatarView(
                                            url: firestore.participantPhotoURL(pending.id),
                                            name: pending.name,
                                            size: 40,
                                            useCurrentUser: false
                                        )
                                        .environmentObject(firestore)
                                        Text(pending.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        Spacer()
                                    }
                                    HStack(spacing: 12) {
                                        Button {
                                            firestore.approveClubMember(placeId: place.id, userId: pending.id)
                                        } label: {
                                            HStack {
                                                Image(systemName: "checkmark")
                                                    .fontWeight(.semibold)
                                                Text("Accept")
                                                    .fontWeight(.semibold)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .foregroundColor(.white)
                                            .background(Color("LogoGreen"))
                                            .cornerRadius(10)
                                        }
                                        .buttonStyle(.plain)
                                        Button {
                                            firestore.rejectClubMember(placeId: place.id, userId: pending.id)
                                        } label: {
                                            HStack {
                                                Image(systemName: "xmark")
                                                    .fontWeight(.semibold)
                                                Text("Decline")
                                                    .fontWeight(.semibold)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .foregroundColor(.white)
                                            .background(Color.red)
                                            .cornerRadius(10)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    // Members list
                    Section(header: Text("\(place.name) — Members (\(place.members.count))")) {
                        if place.members.isEmpty {
                            Text("No members yet.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(place.members) { member in
                                HStack(spacing: 12) {
                                    AvatarView(
                                        url: firestore.participantPhotoURL(member.id),
                                        name: member.name,
                                        size: 36,
                                        useCurrentUser: false
                                    )
                                    .environmentObject(firestore)
                                    Text(member.name)
                                        .font(.body)
                                    Spacer()
                                    Button(role: .destructive) {
                                        firestore.removeClubMember(placeId: place.id, userId: member.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Send announcement
                    Section(header: Text("\(place.name) — Announcements")) {
                        NavigationLink {
                            SendAnnouncementView(place: place)
                                .environmentObject(firestore)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "megaphone.fill")
                                    .foregroundColor(Color("LogoGreen"))
                                Text("Send Announcement")
                            }
                        }
                        .disabled(place.members.isEmpty)
                    }
                }
            }

            // Managing Registrations — shows events for places the user manages
            Section {
                if myPlaces.isEmpty {
                    Text("Claim a place above to manage your club and registrations.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(myPlaces) { place in
                        NavigationLink {
                            PlaceRegistrationsView(place: place)
                                .environmentObject(firestore)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.3.fill")
                                    .foregroundColor(Color("LogoGreen"))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name)
                                        .font(.body)
                                    let count = upcomingEventCount(for: place)
                                    Text("\(count) upcoming event\(count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Managing Registrations")
            }
        }
        .navigationTitle("Places to Play Contact")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            firestore.fetchPlacesToPlay()
            firestore.fetchSignupEvents()
            // Prefetch profile photos for all members and pending members
            for place in myPlaces {
                for member in place.members { firestore.fetchAndCacheUserPhotoURL(uid: member.id) }
                for pending in place.pendingMembers { firestore.fetchAndCacheUserPhotoURL(uid: pending.id) }
            }
            if let placeId = scrollToPlaceId {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation {
                        proxy.scrollTo("pending_\(placeId)", anchor: .top)
                    }
                }
            }
        }
        .onChange(of: firestore.placesToPlay) { _, _ in
            for place in myPlaces {
                for member in place.members { firestore.fetchAndCacheUserPhotoURL(uid: member.id) }
                for pending in place.pendingMembers { firestore.fetchAndCacheUserPhotoURL(uid: pending.id) }
            }
        }
        } // ScrollViewReader
    }

    private func toggleContact(place: PlaceToPlay, isMine: Bool) {
        if isMine {
            firestore.removePlaceContact(placeId: place.id) { _ in }
        } else {
            if place.contactUid == nil || place.contactUid?.isEmpty == true {
                firestore.assignPlaceContact(placeId: place.id) { _ in }
            }
        }
    }

    private func upcomingEventCount(for place: PlaceToPlay) -> Int {
        let now = Date()
        return firestore.signupEvents.filter { $0.placeId == place.id && $0.eventDate >= now }.count
    }
}

// MARK: - Place Registrations View

struct PlaceRegistrationsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    let place: PlaceToPlay

    @State private var showCreateEvent = false

    private var upcomingEvents: [SignupEvent] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return firestore.signupEvents
            .filter { $0.placeId == place.id && $0.eventDate >= startOfToday }
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        List {
            if upcomingEvents.isEmpty {
                Text("No upcoming events at this venue.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(upcomingEvents) { event in
                    NavigationLink {
                        EventRegistrationManageView(event: event)
                            .environmentObject(firestore)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.title)
                                .font(.headline)
                            Text(Self.dateFormatter.string(from: event.eventDate))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "person.2")
                                    .font(.caption)
                                    .foregroundColor(event.isFull ? .red : Color("LogoGreen"))
                                Text("\(event.signupCount) / \(event.maxSignups) signed up")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(event.isFull ? .red : Color("LogoGreen"))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateEvent = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateEvent) {
            CreateSignupEventView(place: place)
                .environmentObject(firestore)
        }
        .onChange(of: showCreateEvent) { _, isShowing in
            if !isShowing { firestore.fetchSignupEvents() }
        }
        .onAppear {
            firestore.fetchSignupEvents()
        }
    }
}

// MARK: - Event Registration Manage View

struct EventRegistrationManageView: View {
    @EnvironmentObject var firestore: FirestoreManager
    let event: SignupEvent
    @State private var showCapacityEditor = false
    @State private var newCapacity: Int = 0

    private var liveEvent: SignupEvent {
        firestore.signupEvents.first { $0.id == event.id } ?? event
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
            // Event info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ev.title)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(Self.dateFormatter.string(from: ev.eventDate))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "person.2")
                            .foregroundColor(ev.isFull ? .red : Color("LogoGreen"))
                        Text("\(ev.signupCount) / \(ev.maxSignups) signed up")
                            .fontWeight(.semibold)
                            .foregroundColor(ev.isFull ? .red : Color("LogoGreen"))
                    }
                    .font(.subheadline)
                }
            }

            // Change capacity
            Section {
                Button {
                    newCapacity = ev.maxSignups
                    showCapacityEditor = true
                } label: {
                    Label("Change Capacity (\(ev.maxSignups))", systemImage: "slider.horizontal.3")
                }
            }

            // Signups list with paid status and remove
            Section(header: Text("Registrations (\(ev.signups.count))")) {
                if ev.signups.isEmpty {
                    Text("No one has signed up yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(ev.signups) { signup in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(signup.name)
                                    .font(.body)
                                Text(signup.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                firestore.toggleSignupPaid(eventId: ev.id, signupId: signup.id, paid: !signup.paid)
                            } label: {
                                Text(signup.paid ? "Paid" : "Unpaid")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(signup.paid ? Color("LogoGreen").opacity(0.15) : Color.orange.opacity(0.15))
                                    .foregroundColor(signup.paid ? Color("LogoGreen") : .orange)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
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
        .navigationTitle("Manage Event")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Change Capacity", isPresented: $showCapacityEditor) {
            TextField("Max signups", value: $newCapacity, format: .number)
                .keyboardType(.numberPad)
            Button("Save") {
                guard newCapacity >= ev.signupCount else { return }
                firestore.updateSignupEventCapacity(eventId: ev.id, newMax: newCapacity)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Current signups: \(ev.signupCount). New capacity must be at least \(ev.signupCount).")
        }
    }
}

// MARK: - Send Announcement View

struct SendAnnouncementView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss
    let place: PlaceToPlay
    @State private var announcementTitle = ""
    @State private var announcementBody = ""
    @State private var isSending = false

    private var isValid: Bool {
        !announcementTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !announcementBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section(header: Text("Announcement")) {
                TextField("Title", text: $announcementTitle)
                TextField("Message", text: $announcementBody, axis: .vertical)
                    .lineLimit(3...8)
            }
            Section {
                Text("This will send a push notification to all \(place.members.count) member\(place.members.count == 1 ? "" : "s") of \(place.name).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Send Announcement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Send") {
                    isSending = true
                    firestore.sendClubAnnouncement(
                        placeId: place.id,
                        title: announcementTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        body: announcementBody.trimmingCharacters(in: .whitespacesAndNewlines)
                    ) { err in
                        DispatchQueue.main.async {
                            isSending = false
                            if err == nil {
                                firestore.showToast("Announcement sent")
                                dismiss()
                            }
                        }
                    }
                }
                .disabled(!isValid || isSending)
            }
        }
    }
}
