import CacheboxCore
import SwiftUI

/// Filter of the cache list: presets, status, types, difficulty and terrain (Cachebox: filter settings).
struct CacheFilterView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    private var lists: CacheListModel { state.lists }
    private var filter: Binding<CacheFilter> {
        Binding(get: { lists.filter }, set: { lists.filter = $0 })
    }

    var body: some View {
        Form {
            Section("Vorlagen") {
                Button("Alle Caches") { lists.filter = .all }
                Button("Noch zu finden") { lists.filter = .toFind }
            }
            Section {
                tristate("Gefunden", filter.found)
                tristate("Deaktiviert", filter.unavailable)
                tristate("Archiviert", filter.archived)
                tristate("Favoriten", filter.favorites)
            } header: {
                Text("Status")
            } footer: {
                Text("„Nur“ zeigt nur solche Caches, „Ohne“ blendet sie aus.")
            }
            Section("Schwierigkeit und Gelände") {
                range("Schwierigkeit", filter.difficulty)
                range("Gelände", filter.terrain)
            }
            Section {
                ForEach(CacheType.filterChoices, id: \.self) { type in
                    Toggle(isOn: typeBinding(type)) {
                        Label {
                            Text(type.title)
                        } icon: {
                            CacheboxIcon(name: type.iconName)
                        }
                    }
                }
            } header: {
                Text("Typen")
            } footer: {
                Text("Ohne Auswahl werden alle Typen gezeigt.")
            }
        }
        .navigationTitle("Filter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            ToolbarItem(placement: .cancellationAction) {
                Button("Zurücksetzen") { lists.filter = .all }.disabled(!lists.filter.isActive)
            }
        }
    }

    private func tristate(_ title: String, _ value: Binding<CacheFilter.Tristate>) -> some View {
        Picker(title, selection: value) {
            Text("Alle").tag(CacheFilter.Tristate.all)
            Text("Nur").tag(CacheFilter.Tristate.only)
            Text("Ohne").tag(CacheFilter.Tristate.hide)
        }
    }

    private func range(_ title: String, _ value: Binding<ClosedRange<Double>>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(CacheSummary.rating(value.wrappedValue.lowerBound)) bis "
                 + CacheSummary.rating(value.wrappedValue.upperBound))
            Stepper("von \(CacheSummary.rating(value.wrappedValue.lowerBound))",
                    value: Binding(get: { value.wrappedValue.lowerBound },
                                   set: { value.wrappedValue = $0...max($0, value.wrappedValue.upperBound) }),
                    in: 1...5, step: 0.5)
            Stepper("bis \(CacheSummary.rating(value.wrappedValue.upperBound))",
                    value: Binding(get: { value.wrappedValue.upperBound },
                                   set: { value.wrappedValue = min($0, value.wrappedValue.lowerBound)...$0 }),
                    in: 1...5, step: 0.5)
        }
    }

    private func typeBinding(_ type: CacheType) -> Binding<Bool> {
        Binding(get: { lists.filter.types.contains(type) }, set: { on in
            if on { lists.filter.types.insert(type) } else { lists.filter.types.remove(type) }
        })
    }
}
