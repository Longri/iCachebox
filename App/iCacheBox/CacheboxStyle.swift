import SwiftUI

// Colors and shapes of the Cachebox day skin (`skins/default/day`: `skin.json` and the sprites `listrec-*`,
// `activity-back`, `dialog-*`, `menu-divider`). The views drawn with them stay light in dark mode, as Cachebox shows
// its day skin until night mode is switched on (not built yet).

extension Color {
    /// Skin color `background` (`ListBack`): behind lists and views.
    static let cacheboxBackground = Color(red: 0.7921, green: 0.8313, blue: 0.6980)
    /// `activity-back`: light green of boxes and menus.
    static let cacheboxActivity = Color(red: 212 / 255, green: 219 / 255, blue: 191 / 255)
    /// Green frame of dialogs and menus and of the line between menu groups (`dialog-*`, `menu-divider`).
    static let cacheboxFrame = Color(red: 166 / 255, green: 193 / 255, blue: 129 / 255)
    /// List rows (`ListViewItemBackground`): `listrec-first` (odd rows), `listrec-secend` (even rows) and
    /// `listrec-selected`.
    static let cacheboxRowFirst = Color.white
    static let cacheboxRowSecond = Color(white: 241 / 255)
    static let cacheboxRowSelected = Color(red: 1, green: 217 / 255, blue: 80 / 255)
}

/// Background of a list or menu row (Cachebox `ListViewItemBackground`): a rounded box with a dark rim, white and
/// light grey in turn, yellow for the selected row.
struct CacheboxRowBox: View {
    /// Position in the list; Cachebox draws odd rows white and even rows grey.
    var index: Int
    var isSelected = false

    static let cornerRadius: CGFloat = 7

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        shape.fill(fill)
            .overlay { shape.strokeBorder(Color.black.opacity(0.85), lineWidth: 1) }
    }

    private var fill: Color {
        if isSelected { return .cacheboxRowSelected }
        return index % 2 == 1 ? .cacheboxRowFirst : .cacheboxRowSecond
    }
}

/// Green line between groups of rows (Cachebox `menu-divider`).
struct CacheboxDivider: View {
    var isThick = false

    var body: some View {
        Capsule()
            .fill(Color.cacheboxFrame)
            .frame(height: isThick ? 5 : 3)
            .padding(.vertical, 2)
            .accessibilityHidden(true)
    }
}

extension View {
    /// A row of a plain `List` on its Cachebox box, with a little green between the boxes; at least 44 pt high, also
    /// in a list with a lower `defaultMinListRowHeight` (for `cacheboxListDivider`).
    func cacheboxListRow(index: Int, isSelected: Bool = false) -> some View {
        frame(minHeight: 32)
            .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(
                CacheboxRowBox(index: index, isSelected: isSelected)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
            )
    }

    /// A `CacheboxDivider` as a row of a plain `List`; needs a low `defaultMinListRowHeight` to stay thin.
    func cacheboxListDivider() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// Text on the green between the boxes of a plain `List`: the title of a group (`isHeader`) or a note below it.
/// Used instead of section headers and footers, which a plain list pins to the edges while scrolling.
struct CacheboxListText: View {
    let text: String
    var isHeader = false

    init(_ text: String, isHeader: Bool = false) {
        self.text = text
        self.isHeader = isHeader
    }

    var body: some View {
        Text(text)
            .font(isHeader ? .subheadline.weight(.semibold) : .footnote)
            .foregroundStyle(Color.black.opacity(isHeader ? 0.75 : 0.62))
            .accessibilityAddTraits(isHeader ? .isHeader : [])
            .listRowInsets(EdgeInsets(top: isHeader ? 14 : 4, leading: 18, bottom: isHeader ? 4 : 10, trailing: 18))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

extension View {
    /// A plain `List` as a page in the Cachebox day skin: green background, light also in dark mode, thin rows
    /// allowed for `CacheboxListText` and `cacheboxListDivider` (the boxes keep 44 pt).
    func cacheboxPage() -> some View {
        listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 8)
            .scrollContentBackground(.hidden)
            .background(Color.cacheboxBackground)
            .environment(\.colorScheme, .light)
    }

    /// Clear row background without a separator, for content that is not a box (progress, empty state).
    func cacheboxPlainRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
