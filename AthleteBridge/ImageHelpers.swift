import SwiftUI

// Helper utilities to load the app logo from either the Assets catalog or an image file
// placed in the app bundle (e.g. AthleteBridgeLogo.png). Returns UIImage for easy use in SwiftUI.

func appLogoUIImage() -> UIImage? {
    // Try common asset name first
    if let img = UIImage(named: "logo") { return img }
    // Try the explicit filename without extension
    if let img = UIImage(named: "AthleteBridgeLogo") { return img }
    // Try loading from main bundle by filename
    if let path = Bundle.main.path(forResource: "AthleteBridgeLogo", ofType: "png"), let ui = UIImage(contentsOfFile: path) {
        return ui
    }
    // Try other common names
    if let img = UIImage(named: "AthletesBridgeLogo") { return img }
    if let path = Bundle.main.path(forResource: "AthletesBridgeLogo", ofType: "png"), let ui = UIImage(contentsOfFile: path) {
        return ui
    }
    return nil
}

func appLogoImageSwiftUI() -> Image? {
    if let ui = appLogoUIImage() { return Image(uiImage: ui) }
    return nil
}


// Add UIImage resizing helper used by MainAppView's avatar loader
#if canImport(UIKit)
import UIKit
extension UIImage {
    /// Resize the image to fit within targetSize while preserving aspect ratio.
    /// Returns a new UIImage scaled to fit within the target size.
    func resizeMaintainingAspectRatio(targetSize: CGSize) -> UIImage {
        guard targetSize.width > 0 && targetSize.height > 0 else { return self }
        let widthRatio = targetSize.width / self.size.width
        let heightRatio = targetSize.height / self.size.height
        let scale = min(widthRatio, heightRatio)
        let newSize = CGSize(width: self.size.width * scale, height: self.size.height * scale)
        // Use UIGraphicsImageRenderer for better fidelity
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let rendered = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return rendered
    }
}
#endif
