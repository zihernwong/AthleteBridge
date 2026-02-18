import SwiftUI
import MapKit

/// Observable wrapper around MKLocalSearchCompleter for address autocomplete.
final class AddressSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = ""
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func search(_ text: String) {
        query = text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            results = []
            return
        }
        completer.queryFragment = text
        isSearching = true
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.results = Array(completer.results.prefix(5))
            self.isSearching = false
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isSearching = false
        }
    }

    /// Resolves a completion to full coordinates + address.
    func resolve(_ completion: MKLocalSearchCompletion, handler: @escaping (StringerLocation?) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let item = response?.mapItems.first,
                  let location = item.placemark.location else {
                handler(nil)
                return
            }
            let name = completion.title
            let address = [
                item.placemark.thoroughfare,
                item.placemark.locality,
                item.placemark.administrativeArea,
                item.placemark.postalCode
            ].compactMap { $0 }.joined(separator: ", ")
            let result = StringerLocation(
                id: UUID().uuidString,
                name: name,
                address: address.isEmpty ? completion.subtitle : address,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            handler(result)
        }
    }
}

/// A search bar that suggests addresses as the user types.
/// Calls `onSelect` with a fully resolved `StringerLocation` when the user picks a suggestion.
struct AddressSearchBar: View {
    let onSelect: (StringerLocation) -> Void
    @StateObject private var completer = AddressSearchCompleter()
    @State private var text = ""
    @State private var showResults = false
    @State private var isResolving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search for an address...", text: $text)
                    .autocorrectionDisabled()
                    .onChange(of: text) { _, newValue in
                        completer.search(newValue)
                        showResults = true
                    }
                if isResolving {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                if !text.isEmpty {
                    Button {
                        text = ""
                        completer.results = []
                        showResults = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showResults && !completer.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(completer.results, id: \.self) { result in
                        Button {
                            isResolving = true
                            completer.resolve(result) { location in
                                DispatchQueue.main.async {
                                    isResolving = false
                                    showResults = false
                                    text = ""
                                    completer.results = []
                                    if let location = location {
                                        onSelect(location)
                                    }
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
