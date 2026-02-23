import SwiftUI
import MapKit
import CoreLocation

// MARK: - Completer

private final class LocationCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Bias to the user's last known location if permission is already granted
        if let coord = CLLocationManager().location?.coordinate {
            let region = MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
            completer.region = region
        }
    }

    func search(_ text: String, resultTypes: MKLocalSearchCompleter.ResultType) {
        guard text.count >= 2 else { results = []; return }
        completer.resultTypes = resultTypes
        completer.queryFragment = text
    }

    func clear() { results = [] }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.results = Array(completer.results.prefix(5))
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

// MARK: - Field

/// A TextField with inline MKLocalSearchCompleter suggestions.
/// Works inside Form sections (suggestions expand the cell) and standalone layouts.
///
/// - `.place` mode  — POI + address results; fills text with `result.title`
/// - `.address` mode — address-only results; fills text with the formatted address (subtitle, or title as fallback)
struct LocationAutocompleteField: View {
    enum Mode {
        case place   // venues, cities, named locations → fills result.title
        case address // street-level addresses → fills subtitle (address) or title
    }

    let placeholder: String
    @Binding var text: String
    var mode: Mode = .place
    /// Set true when used outside a Form (e.g. custom HStack layouts) to draw a rounded border on the field.
    var rounded: Bool = false

    @StateObject private var completer = LocationCompleter()
    @State private var showSuggestions = false

    private var resultTypes: MKLocalSearchCompleter.ResultType {
        switch mode {
        case .place:   return [.pointOfInterest, .address]
        case .address: return .address
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // --- Text field row ---
            HStack {
                Group {
                    if rounded {
                        TextField(placeholder, text: $text)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .autocorrectionDisabled()
                .onChange(of: text) { _, newValue in
                    if newValue.count >= 2 {
                        completer.search(newValue, resultTypes: resultTypes)
                        showSuggestions = true
                    } else {
                        completer.clear()
                        showSuggestions = false
                    }
                }

                if showSuggestions && !completer.results.isEmpty {
                    Button {
                        text = ""
                        completer.clear()
                        showSuggestions = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // --- Inline suggestions — push subsequent rows down dynamically ---
            if showSuggestions && !completer.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(completer.results, id: \.self) { result in
                        Button {
                            text = selectedText(for: result)
                            completer.clear()
                            showSuggestions = false
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
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        if result != completer.results.last {
                            Divider()
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func selectedText(for result: MKLocalSearchCompletion) -> String {
        switch mode {
        case .place:
            return result.title
        case .address:
            return result.subtitle.isEmpty ? result.title : result.subtitle
        }
    }
}
