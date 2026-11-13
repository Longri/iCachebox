import CacheboxCore
import SwiftUI

/// Input of a coordinate digit by digit (Cachebox `EditCoord`): four toggle buttons for the format at the top
/// (Dec, Min, Sec, UTM), below them the coordinate as a row of buttons per line, a number pad above OK/Abbruch at the
/// bottom. The focused digit is drawn in the highlight colour; a key writes into it and the focus jumps on (the
/// rules are in `CoordinateEntry`). A tap on a digit moves the focus there, a tap on N/S or E/W switches it. For UTM
/// a blank key empties a digit and the band letter comes from the keyboard, which then replaces the number pad.
///
/// Deviations: the focused digit also gets a light frame, because the green text of the Cachebox skin is hard to
/// read on the green buttons; Cachebox's double tap on "Dec" (writes a file for Nissan Connect) is left out; the
/// zone digits are as wide as the other UTM digits.
struct CoordinateEditor: View {
    @State private var entry: CoordinateEntry
    let onDone: (Coordinate) -> Void
    let onCancel: () -> Void

    @State private var showsInvalid = false
    @State private var letterInput = ""
    @FocusState private var typesLetter: Bool

    private static let spacing: CGFloat = 3
    private static let cellHeight: CGFloat = 50
    private static let keyHeight: CGFloat = 56

    init(coordinate: Coordinate, onDone: @escaping (Coordinate) -> Void, onCancel: @escaping () -> Void) {
        _entry = State(initialValue: CoordinateEntry(coordinate: coordinate))
        self.onDone = onDone
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 10) {
            formatButtons
            if entry.format == .utm { utmCells } else { lineCells }
            Spacer(minLength: 0)
            if entry.expectsLetter {
                Text("Buchstaben der Zone eingeben (C … X)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                numberPad
            }
            HStack(spacing: 6) {
                Button { done() } label: { Text("OK").frame(maxWidth: .infinity, maxHeight: .infinity) }
                Button { onCancel() } label: { Text("Abbruch").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color(white: 0.08))
            .buttonStyle(CacheboxButtonStyle())
            .frame(height: Self.keyHeight)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cacheboxActivity.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .background { letterField }
        .overlay(alignment: .center) {
            if showsInvalid {
                Text("Ungültige Koordinate")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity)
            }
        }
        .task(id: showsInvalid) {
            guard showsInvalid else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showsInvalid = false }
        }
        .onChange(of: entry.expectsLetter) { typesLetter = entry.expectsLetter }
    }

    // MARK: - Format buttons

    private var formatButtons: some View {
        HStack(spacing: 6) {
            ForEach(CoordinateEntry.Format.allCases, id: \.self) { format in
                Button {
                    entry.select(format)
                } label: {
                    CacheboxToggleLabel(title: format.title, isOn: entry.format == format)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CacheboxButtonStyle())
                .accessibilityLabel(format.accessibilityName)
                .accessibilityAddTraits(entry.format == format ? .isSelected : [])
            }
        }
        .frame(height: Self.keyHeight)
    }

    // MARK: - Cells

    /// Latitude and longitude as one line of buttons each; separators are half a button wide (Cachebox
    /// `addNext(label, 0.5f)`).
    private var lineCells: some View {
        VStack(spacing: 8) {
            ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                WeightedRow(spacing: Self.spacing) {
                    ForEach(line, id: \.self) { item in
                        switch item {
                        case .cell(let cell):
                            cellButton(cell)
                        case .separator(let text):
                            Text(text)
                                .font(.title.weight(.bold))
                                .foregroundStyle(Color(white: 0.08))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .layoutValue(key: RowWeight.self, value: 0.5)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .frame(height: Self.cellHeight)
            }
        }
    }

    /// UTM: a label of 20 % width (Cachebox `addNext(label, -0.2f)`) and eight digits per row; the zone row has
    /// its three cells as wide as the others.
    private var utmCells: some View {
        let rows: [(String, [Int])] = [
            ("OstW", Array(CoordinateEntry.eastingCells)),
            ("NordW", Array(CoordinateEntry.northingCells)),
            ("Zone", Array(CoordinateEntry.zoneCells) + [CoordinateEntry.bandCell]),
        ]
        return VStack(spacing: 8) {
            ForEach(rows, id: \.0) { title, cells in
                WeightedRow(spacing: Self.spacing) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(white: 0.08))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .layoutValue(key: RowWeight.self, value: 2)
                    ForEach(cells, id: \.self) { cell in
                        cellButton(cell)
                    }
                    if cells.count < 8 {
                        Color.clear.layoutValue(key: RowWeight.self, value: CGFloat(8 - cells.count))
                    }
                }
                .frame(height: Self.cellHeight)
            }
        }
    }

    @ViewBuilder
    private func cellButton(_ cell: Int) -> some View {
        if entry.isVisible(cell) {
            let focused = entry.focus == cell && !entry.isHemisphere(cell)
            Button {
                entry.tap(cell)
                if entry.expectsLetter { typesLetter = true }   // again after the keyboard was closed
            } label: {
                Text(entry.cells[cell])
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(focused ? Self.highlight : Color(white: 0.08))
                    .shadow(color: focused ? .black.opacity(0.6) : .clear, radius: 0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if focused {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 2)
                        }
                    }
            }
            .buttonStyle(CacheboxButtonStyle(cornerRadius: 6))
            .accessibilityLabel(accessibilityName(cell))
            .accessibilityValue(entry.cells[cell].isEmpty ? "leer" : entry.cells[cell])
            .accessibilityAddTraits(focused ? .isSelected : [])
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }

    /// Cachebox skin `font-color-highlight` (0, 1, 0).
    private static let highlight = Color(red: 0, green: 1, blue: 0)

    private func accessibilityName(_ cell: Int) -> String {
        if entry.format == .utm {
            if CoordinateEntry.eastingCells.contains(cell) { return "Ostwert, Stelle \(cell + 1)" }
            if CoordinateEntry.northingCells.contains(cell) { return "Nordwert, Stelle \(cell - 5)" }
            if CoordinateEntry.zoneCells.contains(cell) { return "Zone, Stelle \(cell - 13)" }
            return "Zonenbuchstabe"
        }
        let n = entry.cells.count / 2
        let line = cell < n ? "Breite" : "Länge"
        let index = cell % n
        return index == 0 ? "\(line), Halbkugel" : "\(line), Stelle \(index)"
    }

    // MARK: - Keys

    /// Cachebox number pad: 1 2 3 / 4 5 6 / 7 8 9 / – 0 blank, the blank key only for UTM.
    private var numberPad: some View {
        VStack(spacing: 6) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { digitKey($0) }
                }
            }
            HStack(spacing: 6) {
                Color.clear.frame(maxWidth: .infinity)
                digitKey(0)
                if entry.format == .utm {
                    Button { entry.enterBlank() } label: {
                        Image(systemName: "space").frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(CacheboxButtonStyle())
                    .accessibilityLabel("Leer")
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
        .font(.title.weight(.semibold))
        .foregroundStyle(Color(white: 0.08))
        .frame(height: 4 * Self.keyHeight + 3 * 6)
    }

    private func digitKey(_ digit: Int) -> some View {
        Button { entry.enter(digit: digit) } label: {
            Text("\(digit)").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(CacheboxButtonStyle())
    }

    /// Takes the band letter from the keyboard (Cachebox `invisibleTextField`).
    private var letterField: some View {
        TextField("", text: $letterInput)
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .focused($typesLetter)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityHidden(true)
            .onChange(of: letterInput) {
                guard let letter = letterInput.last else { return }
                letterInput = ""
                entry.enter(letter: letter)
            }
    }

    private func done() {
        if let coordinate = entry.parse() {
            typesLetter = false
            onDone(coordinate)
        } else {
            withAnimation { showsInvalid = true }   // Cachebox: toast "Invalid COORD"
        }
    }
}

private extension CoordinateEntry.Format {
    var accessibilityName: String {
        switch self {
        case .degrees: "Grad"
        case .minutes: "Grad und Minuten"
        case .seconds: "Grad, Minuten und Sekunden"
        case .utm: "UTM"
        }
    }
}

/// Width share of a view in a `WeightedRow` (Cachebox `addNext(view, weight)`), 1 by default.
private struct RowWeight: LayoutValueKey {
    static let defaultValue: CGFloat = 1
}

/// A row that divides its width by the weights of its views, like the rows of a Cachebox `CB_View_Base`
/// (`addNext`/`addLast`): every view gets `weight / sum of weights` of the width left after the spacing.
private struct WeightedRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 320, height: 44))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let total = subviews.reduce(0) { $0 + $1[RowWeight.self] }
        guard total > 0 else { return }
        let available = max(0, bounds.width - spacing * CGFloat(subviews.count - 1))
        var x = bounds.minX
        for subview in subviews {
            let width = available * subview[RowWeight.self] / total
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}
