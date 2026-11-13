import SwiftUI
import UIKit

/// Mehr › Einstellungen, in the Cachebox day skin: the range of functions (Cachebox `SettingsShowExpert`,
/// `SettingsShowAll`, which are hidden switches there) and the approach notification (Cachebox settings
/// `SoundApproachDistance` and `switchViewApproach` under Misc).
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = state
        @Bindable var options = state.approach.options
        List {
            CacheboxListText("Funktionsumfang", isHeader: true)
            Picker(selection: $app.featureLevel) {
                ForEach(FeatureLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            } label: {
                Label("Menüs zeigen", systemImage: "square.3.layers.3d")
            }
            .pickerStyle(.menu)
            .cacheboxListRow(index: 0)
            CacheboxListText("Je höher der Funktionsumfang, desto mehr steht in den Menüs. "
                             + state.featureLevel.summary)
            CacheboxDivider().cacheboxListDivider()
            CacheboxListText("Annäherung", isHeader: true)
            Picker(selection: $options.distance) {
                ForEach(ApproachOptions.distances, id: \.self) { metres in
                    Text(metres == 0 ? "Aus" : "\(metres) m").tag(metres)
                }
            } label: {
                Label("Benachrichtigung bei", systemImage: "bell.badge")
            }
            .pickerStyle(.menu)
            .cacheboxListRow(index: 1)
            CacheboxListText("Nähert man sich dem Ziel – dem gewählten Cache oder seinem gewählten Wegpunkt – auf "
                             + "diese Entfernung, meldet sich iCacheBox einmal mit Ton und Vibration. Entfernt man "
                             + "sich wieder, kommt beim nächsten Mal eine neue Benachrichtigung.")
            if options.isOn {
                Toggle(isOn: $options.worksInBackground) {
                    Label("Auch bei gesperrtem Bildschirm", systemImage: "lock.iphone")
                }
                .cacheboxListRow(index: 2)
                CacheboxListText("Dafür verfolgt iCacheBox die Position weiter, solange die App läuft; iOS zeigt "
                                 + "dann oben die blaue Standortanzeige. Das kostet Akku.")
                Toggle(isOn: $options.switchesToCompass) {
                    Label("Auf Kompass umschalten", systemImage: "location.north.circle")
                }
                .cacheboxListRow(index: 3)
                if state.approach.isDenied {
                    CacheboxDivider().cacheboxListDivider()
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Benachrichtigungen sind nicht erlaubt", systemImage: "exclamationmark.triangle")
                    }
                    .cacheboxListRow(index: 4)
                    CacheboxListText("Ohne Erlaubnis vibriert nur das Gerät, solange die App im Vordergrund ist. "
                                     + "In den Systemeinstellungen lässt sie sich erteilen.")
                }
            }
        }
        .cacheboxPage()
        .navigationTitle("Einstellungen")
        .onChange(of: options.distance) { settingsChanged() }
        .onChange(of: options.worksInBackground) { settingsChanged() }
        .task(id: scenePhase) {
            // the permission may have been given in the system settings meanwhile
            if scenePhase == .active { await state.approach.refreshAuthorization() }
        }
    }

    private func settingsChanged() {
        state.approach.reset()
        state.updateApproachWatching()
        if state.approach.options.isOn {
            Task { await state.approach.requestAuthorization() }
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AppState())
}
