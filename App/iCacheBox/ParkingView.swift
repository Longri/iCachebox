import CacheboxCore
import SwiftUI

/// "Mein Parkplatz" (Cachebox `ParkingMenu`, a `ButtonDialog` with three image buttons): save the own position as the
/// parking place, make it the navigation target, delete it. The buttons carry the Cachebox icons `my-parking-set`,
/// `my-parking-wp` and `my-parking-delete`; "Ziel" and "Löschen" are disabled while no parking place is set, as in
/// Cachebox.
///
/// Deviations: the dialog also shows where the parking place is and how far away it is (Cachebox only has the three
/// buttons), and it says so when there is no position yet instead of saving 0/0.
struct ParkingView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    /// No fix yet, so nothing was saved.
    @State private var missingPosition = false

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 12) {
                Text("Setze, lösche oder wähle deinen Parkplatz!")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.2))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 8) {
                    button("my-parking-set", "Parkplatz vom GPS setzen", isEnabled: true) {
                        if state.saveParking() {
                            dismiss()
                        } else {
                            withAnimation { missingPosition = true }
                        }
                    }
                    button("my-parking-wp", "Setze Ziel auf Parkplatz", isEnabled: state.parking.isSet) {
                        state.selectParking()
                        dismiss()
                    }
                    button("my-parking-delete", "Parkplatz löschen", isEnabled: state.parking.isSet) {
                        state.deleteParking()
                        dismiss()
                    }
                }

                place
                if missingPosition {
                    Text("Noch keine GPS-Position. Warte auf den Standort und versuche es erneut.")
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0.6, green: 0, blue: 0))
                        .multilineTextAlignment(.center)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Abbruch")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(white: 0.08))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(CacheboxButtonStyle())
            }
            .padding(12)
        }
        .background(Color.cacheboxActivity)
        .environment(\.colorScheme, .light)   // Cachebox day skin
        .onAppear { state.location.start() }
    }

    /// Title bar like a Cachebox dialog (`dialog-title`).
    private var header: some View {
        Text("Verwalte deinen Parkplatz!")
            .font(.headline)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color.cacheboxFrame)
            .accessibilityAddTraits(.isHeader)
    }

    /// Where the parking place is and how far away (not in Cachebox, which only shows the three buttons).
    @ViewBuilder
    private var place: some View {
        VStack(spacing: 2) {
            if let coordinate = state.parking.coordinate {
                HStack(spacing: 8) {
                    CacheboxIcon(name: ParkingPlace.iconName, size: 22)
                    Text(coordinate.formatted)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let here = state.location.coordinate {
                    Text(Format.distance(here.distance(to: coordinate)) + " entfernt")
                        .foregroundStyle(Color(white: 0.3))
                }
                if state.targetsParking {
                    Label("Ziel", systemImage: "scope")
                        .foregroundStyle(Color(red: 0.24, green: 0.48, blue: 0.13))
                }
            } else {
                Text("Kein Parkplatz gesetzt")
                    .foregroundStyle(Color(white: 0.3))
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity)
    }

    /// One of the three Cachebox image buttons: the icon above its wrapped label.
    private func button(_ icon: String, _ title: String, isEnabled: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                Text(title)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color(white: 0.08))
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
        }
        .buttonStyle(CacheboxButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }
}
