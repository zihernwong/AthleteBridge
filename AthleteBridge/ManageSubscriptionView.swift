import SwiftUI

struct ManageSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "creditcard")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .foregroundColor(.accentColor)

                Text("Manage My Subscription")
                    .font(.title2)
                    .bold()

                Text("This is a placeholder screen. Subscription management UI will be implemented here later.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 20)
            }
            .padding()
            .navigationTitle("Subscription")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ManageSubscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        ManageSubscriptionView()
    }
}
