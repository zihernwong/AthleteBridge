import SwiftUI
import PhotosUI
import UIKit

// Reusable PhotoPicker for picking a single image via PHPicker
public struct PhotoPicker: UIViewControllerRepresentable {
    @Binding public var selectedImage: UIImage?

    public init(selectedImage: Binding<UIImage?>) {
        self._selectedImage = selectedImage
    }

    public class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }
        public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first else { return }
            if item.itemProvider.canLoadObject(ofClass: UIImage.self) {
                item.itemProvider.loadObject(ofClass: UIImage.self) { (obj, _) in
                    if let image = obj as? UIImage {
                        DispatchQueue.main.async { self.parent.selectedImage = image }
                    }
                }
            }
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    public func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
}

// Local UIImage resizing helper accessible across the module
public extension UIImage {
    func resized(to maxDimension: CGFloat) -> UIImage? {
        let aspect = size.width / size.height
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspect)
        } else {
            newSize = CGSize(width: maxDimension * aspect, height: maxDimension)
        }
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
    }
}

// Chip-style multi-select component (used for short lists like availability)
public struct ChipMultiSelect: View {
    public let items: [String]
    @Binding public var selection: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    public init(items: [String], selection: Binding<Set<String>>) {
        self.items = items
        self._selection = selection
    }

    public var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button(action: {
                    if selection.contains(item) { selection.remove(item) } else { selection.insert(item) }
                }) {
                    Text(item)
                        .font(.subheadline)
                        .foregroundColor(selection.contains(item) ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selection.contains(item) ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                        .cornerRadius(20)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
}

// Convenience helper to dismiss keyboard from SwiftUI
public extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
