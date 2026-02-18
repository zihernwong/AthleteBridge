import SwiftUI

struct ClubAnnouncementsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    let place: PlaceToPlay
    var highlightAnnouncementId: String? = nil

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private var announcements: [ClubAnnouncement] {
        firestore.clubAnnouncements[place.id] ?? []
    }

    var body: some View {
        List {
            if announcements.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "megaphone")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No announcements yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                ForEach(announcements) { announcement in
                    announcementRow(announcement)
                }
            }
        }
        .navigationTitle("Announcements")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            firestore.fetchClubAnnouncements(placeId: place.id)
        }
    }

    private func announcementRow(_ announcement: ClubAnnouncement) -> some View {
        let isHighlighted = announcement.id == highlightAnnouncementId
        return VStack(alignment: .leading, spacing: 8) {
            Text(announcement.title)
                .font(.headline)

            Text(announcement.body)
                .font(.subheadline)
                .foregroundColor(.primary)

            HStack {
                Image(systemName: "person.circle")
                    .foregroundColor(.secondary)
                Text(announcement.senderName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(Self.dateFormatter.string(from: announcement.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isHighlighted ? Color("LogoGreen").opacity(0.1) : nil)
    }
}
