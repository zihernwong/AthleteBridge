import SwiftUI

private let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
private let weekdayAbbrev: [String: String] = [
    "Monday": "Mon", "Tuesday": "Tue", "Wednesday": "Wed",
    "Thursday": "Thu", "Friday": "Fri", "Saturday": "Sat", "Sunday": "Sun"
]

struct PlacesToPlayView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @EnvironmentObject var auth: AuthViewModel
    @State private var showAddSheet = false

    private var currentUid: String { auth.user?.uid ?? "" }

    var body: some View {
        List {
            if firestore.placesToPlay.isEmpty {
                Text("No places added yet. Be the first!")
                    .foregroundColor(.secondary)
            } else {
                ForEach(firestore.placesToPlay) { place in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(place.name)
                            .font(.headline)

                        if !place.address.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(.secondary)
                                Text(place.address)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if !place.pricePerSession.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "dollarsign.circle")
                                    .foregroundColor(.secondary)
                                Text(place.pricePerSession)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if !place.playingTimes.isEmpty {
                            WeeklyScheduleDisplay(schedule: place.playingTimes)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let place = firestore.placesToPlay[index]
                        if place.createdBy == currentUid {
                            firestore.deletePlaceToPlay(id: place.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Places to Play")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddPlaceToPlayView()
                .environmentObject(firestore)
        }
        .onAppear {
            firestore.fetchPlacesToPlay()
        }
    }
}

// MARK: - Weekly Schedule Display

private struct WeeklyScheduleDisplay: View {
    let schedule: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text("Playing Times")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ForEach(weekdays, id: \.self) { day in
                if let times = schedule[day], !times.isEmpty {
                    HStack {
                        Text(weekdayAbbrev[day] ?? day)
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(width: 36, alignment: .leading)
                        Text(times)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Add Place Form

struct AddPlaceToPlayView: View {
    @EnvironmentObject var firestore: FirestoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var pricePerSession = ""
    @State private var isSaving = false

    // Weekly schedule state
    @State private var selectedDays: Set<String> = []
    @State private var dayOpenTimes: [String: Date] = [:]
    @State private var dayCloseTimes: [String: Date] = [:]

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var playingTimesMap: [String: String] {
        var result: [String: String] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        for day in selectedDays {
            let open = dayOpenTimes[day] ?? defaultOpen
            let close = dayCloseTimes[day] ?? defaultClose
            result[day] = "\(formatter.string(from: open)) - \(formatter.string(from: close))"
        }
        return result
    }

    private var defaultOpen: Date {
        Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    }

    private var defaultClose: Date {
        Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Venue Details")) {
                    TextField("Location Name", text: $name)
                    TextField("Address", text: $address)
                    TextField("Price per Session (e.g. $25/hr)", text: $pricePerSession)
                }

                Section(header: Text("Weekly Schedule")) {
                    Text("Select days this venue is available")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Day chips
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 8) {
                        ForEach(weekdays, id: \.self) { day in
                            let isSelected = selectedDays.contains(day)
                            Button(action: {
                                if isSelected {
                                    selectedDays.remove(day)
                                    dayOpenTimes.removeValue(forKey: day)
                                    dayCloseTimes.removeValue(forKey: day)
                                } else {
                                    selectedDays.insert(day)
                                    dayOpenTimes[day] = defaultOpen
                                    dayCloseTimes[day] = defaultClose
                                }
                            }) {
                                Text(weekdayAbbrev[day] ?? day)
                                    .font(.callout)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color("LogoGreen") : Color(UIColor.secondarySystemBackground))
                                    )
                                    .foregroundColor(isSelected ? .white : .primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    // Time pickers for selected days
                    ForEach(weekdays, id: \.self) { day in
                        if selectedDays.contains(day) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                HStack {
                                    DatePicker("Open", selection: binding(for: day, in: $dayOpenTimes, default: defaultOpen), displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                    Text("to")
                                        .foregroundColor(.secondary)
                                    DatePicker("Close", selection: binding(for: day, in: $dayCloseTimes, default: defaultClose), displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        firestore.addPlaceToPlay(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                            playingTimes: playingTimesMap,
                            pricePerSession: pricePerSession.trimmingCharacters(in: .whitespacesAndNewlines)
                        ) { err in
                            DispatchQueue.main.async {
                                isSaving = false
                                if err == nil { dismiss() }
                            }
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
    }

    private func binding(for day: String, in dict: Binding<[String: Date]>, default defaultDate: Date) -> Binding<Date> {
        Binding<Date>(
            get: { dict.wrappedValue[day] ?? defaultDate },
            set: { dict.wrappedValue[day] = $0 }
        )
    }
}
