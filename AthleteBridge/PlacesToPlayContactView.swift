import SwiftUI
import FirebaseAuth

struct PlacesToPlayContactView: View {
    @EnvironmentObject var firestore: FirestoreManager

    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }

    var body: some View {
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

            // Managing Registrations (dummy)
            Section {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(.secondary)
                    Text("View Registrations")
                    Spacer()
                    Text("Coming Soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .opacity(0.5)

                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.secondary)
                    Text("Send Announcements")
                    Spacer()
                    Text("Coming Soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .opacity(0.5)

                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.secondary)
                    Text("Attendance Reports")
                    Spacer()
                    Text("Coming Soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .opacity(0.5)
            } header: {
                Text("Managing Registrations")
            } footer: {
                Text("Registration management features are coming soon.")
            }
        }
        .navigationTitle("Places to Play Contact")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            firestore.fetchPlacesToPlay()
        }
    }

    private func toggleContact(place: PlaceToPlay, isMine: Bool) {
        if isMine {
            firestore.removePlaceContact(placeId: place.id) { _ in }
        } else {
            // Only allow claiming if no one else is the contact
            if place.contactUid == nil || place.contactUid?.isEmpty == true {
                firestore.assignPlaceContact(placeId: place.id) { _ in }
            }
        }
    }
}
