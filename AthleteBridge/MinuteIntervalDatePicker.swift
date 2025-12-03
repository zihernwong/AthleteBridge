import SwiftUI
import UIKit

/// A simple UIViewRepresentable wrapper around UIDatePicker that enforces a minuteInterval.
/// Use this when you need more control than SwiftUI's DatePicker exposes (e.g., 30-minute steps).
struct MinuteIntervalDatePicker: UIViewRepresentable {
    @Binding var date: Date
    var minuteInterval: Int = 30

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = minuteInterval
        picker.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        picker.date = date
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        if uiView.minuteInterval != minuteInterval {
            uiView.minuteInterval = minuteInterval
        }
        if abs(uiView.date.timeIntervalSince(date)) > 1 {
            uiView.setDate(date, animated: true)
        }
    }

    class Coordinator: NSObject {
        var parent: MinuteIntervalDatePicker
        init(_ parent: MinuteIntervalDatePicker) { self.parent = parent }

        @objc func valueChanged(_ sender: UIDatePicker) {
            parent.date = sender.date
        }
    }
}
