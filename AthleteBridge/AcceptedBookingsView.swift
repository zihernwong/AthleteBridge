import SwiftUI

struct AcceptedBookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Accepted Bookings").font(.largeTitle).bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                if firestore.coachBookings.isEmpty {
                    Text("No accepted bookings found")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(firestore.coachBookings, id: \ .id) { b in
                        BookingRowView(item: b)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("Accepted Bookings")
        .onAppear {
            firestore.fetchBookingsForCurrentCoachSubcollection()
        }
    }
}

struct AcceptedBookingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AcceptedBookingsView()
                .environmentObject(FirestoreManager())
                .environmentObject(AuthViewModel())
        }
    }
}
