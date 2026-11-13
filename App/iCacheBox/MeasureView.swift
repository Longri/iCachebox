import CacheboxCore
import SwiftUI

/// An open measurement (Cachebox `MeasureCoordinate`).
struct MeasureRequest: Identifiable {
    let id = UUID()
}

/// Averages the measured positions, as Cachebox's `MeasureCoordinate.MeasuredCoordList` does: every fix is added,
/// after every tenth one the outliers — more than three metres from the average — are dropped until none is left,
/// and the average of the rest is the result. Cachebox's accuracy weighting is only announced there, not built
/// (`getAccuWeightedAverageCoord` returns the plain average), so this does the same.
struct MeasuredPositions {
    private(set) var measurements: [Coordinate] = []
    /// How many fixes came in, including the ones dropped again (Cachebox `MeasureCount`).
    private(set) var count = 0

    /// Cachebox drops everything further than this from the average (`clearDiscordantValue`).
    private static let outlierDistance = 3.0

    var average: Coordinate? {
        guard !measurements.isEmpty else { return nil }
        let latitude = measurements.reduce(0) { $0 + $1.latitude } / Double(measurements.count)
        let longitude = measurements.reduce(0) { $0 + $1.longitude } / Double(measurements.count)
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    mutating func add(_ coordinate: Coordinate) {
        count += 1
        measurements.append(coordinate)
        if count.isMultiple(of: 10) { clearOutliers() }
    }

    /// Cachebox `clearDiscordantValue`: drop one outlier at a time, recomputing the average, until all are near it.
    private mutating func clearOutliers() {
        while measurements.count > 1 {
            guard let average else { return }
            guard let worst = measurements.enumerated()
                .max(by: { average.distance(to: $0.element) < average.distance(to: $1.element) }),
                average.distance(to: worst.element) > Self.outlierDistance else { return }
            measurements.remove(at: worst.offset)
        }
    }
}

/// Measures the own position over several fixes and makes a waypoint of the average (Cachebox `MeasureCoordinate`,
/// menu "Vom GPS"): the number of fixes, the average coordinate and its spread, drawn as the track of the
/// measurements with circles at 2 m and 4 m like Cachebox.
///
/// Deviations: Cachebox shows the satellite bars beside it (iOS reports no satellites) and switches the GPS to
/// its measuring mode (`Platform.switchToGpsMeasure`), which iOS does not have; here the accuracy of the fixes is
/// shown instead.
struct MeasureView: View {
    let location: LocationModel
    let onDone: (Coordinate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var measured = MeasuredPositions()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            label("Position messen")
            Text("Lege das Gerät an die Stelle und warte, bis sich die Koordinate beruhigt hat.")
                .font(.footnote)
                .foregroundStyle(Color(white: 0.25))
                .padding(.leading, 4)
                .padding(.bottom, 4)
            row("Messungen", "\(measured.count)/\(measured.measurements.count)")
            row("Genauigkeit", location.accuracy.map { "± " + MapFormat.distance($0) } ?? "---")
            label("Gemessene Koordinate").padding(.top, 6)
            Text(measured.average?.formatted ?? "Warte auf den Standort …")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Color(white: 0.08))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityLabel("Gemessene Koordinate")
                .accessibilityValue(measured.average?.formatted ?? "noch keine")
            MeasureChart(measured: measured)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 8)
            HStack(spacing: 6) {
                Button { done() } label: { Text("OK").frame(maxWidth: .infinity, maxHeight: .infinity) }
                    .disabled(measured.average == nil)
                Button { dismiss() } label: { Text("Abbruch").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color(white: 0.08))
            .buttonStyle(CacheboxButtonStyle())
            .frame(height: 56)
            .padding(.top, 8)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.cacheboxActivity.ignoresSafeArea())
        .environment(\.colorScheme, .light)   // Cachebox day skin
        .interactiveDismissDisabled()
        .onAppear {
            location.start()
            if let here = location.coordinate { measured.add(here) }
        }
        .onChange(of: location.fixCount) {
            if let here = location.coordinate { measured.add(here) }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color(white: 0.15))
            .padding(.leading, 4)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            label(title)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color(white: 0.08))
                .padding(.trailing, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private func done() {
        guard let average = measured.average else { return }
        onDone(average)
        dismiss()
    }
}

/// Cachebox `repaintPreview`: the measurements as a line around their average, with circles at 2 m and 4 m.
private struct MeasureChart: View {
    let measured: MeasuredPositions

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // the drawing holds at least 5 m around the average, more when the measurements scatter further
            let average = measured.average
            let spread = average.map { average in
                measured.measurements.map { average.distance(to: $0) }.max() ?? 0
            } ?? 0
            let metres = max(5, spread * 1.1)
            let scale = (side / 2 - 6) / metres

            context.stroke(Path { path in
                path.move(to: CGPoint(x: center.x, y: 0))
                path.addLine(to: CGPoint(x: center.x, y: size.height))
                path.move(to: CGPoint(x: 0, y: center.y))
                path.addLine(to: CGPoint(x: size.width, y: center.y))
            }, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
            for radius in [2.0, 4.0] where radius * scale < side / 2 {
                let r = radius * scale
                context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(.black.opacity(0.35)), lineWidth: 0.5)
            }
            guard let average else { return }
            let points = measured.measurements.map { point(of: $0, from: average, center: center, scale: scale) }
            if points.count > 1 {
                var path = Path()
                path.addLines(points)
                context.stroke(path, with: .color(.red), lineWidth: 1)
            }
            if let last = points.last {
                context.stroke(Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)),
                               with: .color(.blue), lineWidth: 2)
            }
        }
        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel("Streuung der Messungen")
        .accessibilityValue(spreadText)
    }

    /// A measurement in metres east/north of the average, drawn with y upwards.
    private func point(of coordinate: Coordinate, from average: Coordinate, center: CGPoint,
                       scale: CGFloat) -> CGPoint {
        let distance = average.distance(to: coordinate)
        let angle = average.bearing(to: coordinate) * .pi / 180
        return CGPoint(x: center.x + distance * sin(angle) * scale, y: center.y - distance * cos(angle) * scale)
    }

    private var spreadText: String {
        guard let average = measured.average,
              let worst = measured.measurements.map({ average.distance(to: $0) }).max() else { return "keine" }
        return "bis " + MapFormat.distance(worst)
    }
}
