import CacheboxCore
import SwiftUI

/// A projection to start (Cachebox `ProjectionCoordinate` with `ProjectionType.projection`).
struct ProjectionRequest: Identifiable {
    let id = UUID()
    /// Where the projection starts: the chosen waypoint, the cache or the own position.
    let from: Coordinate
    /// Name of that point, written on the coordinate button (Cachebox `fromText`).
    let fromName: String
}

/// Creates a waypoint by direction and distance from a known point (Cachebox `ProjectionCoordinate`): the starting
/// point as a coordinate button that opens the coordinate input, below it direction in degrees and distance in
/// metres, and the resulting coordinate. OK makes a reference point of it.
///
/// Deviations: Cachebox has its own number pad here (`NumPad`), this uses the system keyboard; the result is shown
/// while typing; the types "Kreis" and "Punkt zu Punkt" of `ProjectionType` are not offered, as Cachebox only uses
/// them in the solver; distances are metres (Cachebox can do yards with `ImperialUnits`).
struct ProjectionEditor: View {
    let request: ProjectionRequest
    let onDone: (Coordinate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var from: Coordinate
    @State private var bearing = ""
    @State private var distance = ""
    @State private var editsCoordinate = false
    @State private var showsInvalid = false
    @FocusState private var focus: Field?

    private enum Field { case bearing, distance }

    init(request: ProjectionRequest, onDone: @escaping (Coordinate) -> Void) {
        self.request = request
        self.onDone = onDone
        _from = State(initialValue: request.from)
    }

    var body: some View {
        ZStack {
            form
            if editsCoordinate {
                CoordinateEditor(coordinate: from) { new in
                    from = new
                    withAnimation(.easeOut(duration: 0.2)) { editsCoordinate = false }
                } onCancel: {
                    withAnimation(.easeOut(duration: 0.2)) { editsCoordinate = false }
                }
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }
        }
        .environment(\.colorScheme, .light)   // Cachebox day skin
        .interactiveDismissDisabled()
        .onAppear { focus = .bearing }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                label("Projektion von")
                Button {
                    focus = nil
                    withAnimation(.easeOut(duration: 0.2)) { editsCoordinate = true }
                } label: {
                    VStack(spacing: 2) {
                        Text(request.fromName)
                            .font(.footnote)
                            .lineLimit(1)
                        Text(from.formatted)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(Color(white: 0.08))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(ProjectionCoordinateStyle())
                .accessibilityLabel("Startpunkt \(request.fromName)")
                .accessibilityValue(from.formatted)

                field("Richtung", unit: "°", text: $bearing, field: .bearing)
                field("Entfernung", unit: "m", text: $distance, field: .distance)

                label("Ergebnis").padding(.top, 10)
                Text(projected?.formatted ?? "—")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Color(white: 0.08))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityLabel("Ergebnis")
                    .accessibilityValue(projected?.formatted ?? "noch keines")
                if showsInvalid {
                    Text("Richtung (0–360) und Entfernung in Metern eingeben.")
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0.6, green: 0, blue: 0))
                        .padding(.top, 4)
                }
            }
            .padding(8)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 6) {
                Button { done() } label: { Text("OK").frame(maxWidth: .infinity, maxHeight: .infinity) }
                Button { dismiss() } label: { Text("Abbruch").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color(white: 0.08))
            .buttonStyle(CacheboxButtonStyle())
            .frame(height: 56)
            .padding(8)
            .background(Color.cacheboxActivity)
        }
        .background(Color.cacheboxActivity.ignoresSafeArea())
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color(white: 0.15))
            .padding(.leading, 4)
    }

    private func field(_ title: String, unit: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 8) {
            label(title).frame(width: 110, alignment: .leading)
            CacheboxTextField(text: text, keyboard: .decimalPad, accessibilityLabel: title)
                .focused($focus, equals: field)
            Text(unit)
                .font(.headline)
                .foregroundStyle(Color(white: 0.15))
                .frame(width: 22, alignment: .leading)
        }
        .padding(.top, 6)
    }

    /// Cachebox `parseInput`: direction and distance as numbers, then `Coordinate.project`.
    private var projected: Coordinate? {
        guard let bearing = Double(bearing.replacingOccurrences(of: ",", with: ".")),
              let distance = Double(distance.replacingOccurrences(of: ",", with: ".")),
              distance > 0, bearing >= -360, bearing <= 360 else { return nil }
        let result = from.projected(bearing: bearing, distance: distance)
        return result.isValid ? result : nil
    }

    private func done() {
        guard let projected else {
            withAnimation { showsInvalid = true }
            return
        }
        onDone(projected)
        dismiss()
    }
}

/// The starting point like a Cachebox `CoordinateButton`: drawn pressed (yellow), green while pressed.
private struct ProjectionCoordinateStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { CacheboxButtonFace(isPressed: !configuration.isPressed) }
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
    }
}
