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
