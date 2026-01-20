import SwiftUI

struct ConfirmedBookingsView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel

    private func isConfirmed(_ status: String?) -> Bool {
        let s = (status ?? "").lowercased()
        return s == "confirmed" || s == "accepted" || s == "approved"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Confirmed Bookings").font(.largeTitle).bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                let confirmed = firestore.bookings.filter { isConfirmed($0.status) }
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
            if let uid = auth.user?.uid {
                firestore.fetchBookingsFromClientSubcollection(clientId: uid)
            } else {
                firestore.fetchBookingsForCurrentClientSubcollection()
            }
        }
    }
}

struct ConfirmedBookingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ConfirmedBookingsView()
                .environmentObject(FirestoreManager())
                .environmentObject(AuthViewModel())
        }
    }
}
