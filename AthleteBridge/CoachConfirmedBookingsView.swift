import SwiftUI

struct CoachConfirmedBookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    private func isConfirmed(_ status: String?) -> Bool {
        return (status ?? "").lowercased() == "confirmed"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Confirmed Bookings").font(.largeTitle).bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                let confirmed = firestore.coachBookings.filter { isConfirmed($0.status) }
                if confirmed.isEmpty {
                    Text("No confirmed bookings")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(confirmed, id: \ .id) { b in
                        BookingRowView(item: b)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("Confirmed Bookings")
        .onAppear {
            firestore.fetchBookingsForCurrentCoachSubcollection()
        }
    }
}

struct CoachConfirmedBookingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CoachConfirmedBookingsView()
                .environmentObject(FirestoreManager())
                .environmentObject(AuthViewModel())
        }
    }
}
