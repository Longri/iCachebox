import CacheboxCore
import SwiftUI

/// "GCVote-Bewertungen" (Cachebox: the "GCVoteRatings" box of the import dialog): loads the ratings of GCVote
/// into the open cache list, in the Cachebox day skin like the other pages of "Mehr".
///
/// Shown as a page from "Mehr" and as a sheet from the menu of the cache list.
struct GCVoteView: View {
    /// Shown as a sheet (from the cache list); then it gets a "Fertig" button.
    var isSheet = false

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    private var model: GCVoteModel { state.gcVote }
    private var codes: [String] { state.gcVoteCodes() }

    var body: some View {
        @Bindable var model = state.gcVote
        List {
            CacheboxListText("Bewertungen laden", isHeader: true)
            Picker(selection: $model.scope) {
                ForEach(GCVoteModel.Scope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            } label: {
                Label("Caches", systemImage: "line.3.horizontal.decrease.circle")
            }
            .pickerStyle(.menu)
            .disabled(model.isRunning)
            .cacheboxListRow(index: 0)
            Button {
                start()
            } label: {
                Label(buttonTitle, systemImage: "square.and.arrow.down")
            }
            .disabled(model.isRunning || codes.isEmpty)
            .cacheboxListRow(index: 1)
            if model.isRunning {
                running.cacheboxListRow(index: 2)
            }
            if let result = model.result {
                finished(result).cacheboxListRow(index: 2)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .cacheboxListRow(index: 3)
            }
            CacheboxListText(status)

            CacheboxDivider().cacheboxListDivider()
            CacheboxListText("GCVote-Konto", isHeader: true)
            LabeledContent {
                TextField("Benutzername", text: $model.username)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } label: {
                Label("Benutzer", systemImage: "person")
            }
            .cacheboxListRow(index: 0)
            LabeledContent {
                SecureField("Passwort", text: $model.password)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("Passwort", systemImage: "key")
            }
            .cacheboxListRow(index: 1)
            CacheboxListText("Die Durchschnittswerte kommen auch ohne Anmeldung. Benutzername (der von "
                             + "geocaching.com) und GCVote-Passwort braucht nur, wer die eigene Stimme sehen "
                             + "möchte. Das Passwort liegt im Schlüsselbund.")

            if state.featureLevel >= .expert {
                CacheboxDivider().cacheboxListDivider()
                CacheboxListText("Server", isHeader: true)
                TextField("Server", text: $model.server, prompt: Text(GCVoteService.defaultServer))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .cacheboxListRow(index: 0)
                Button {
                    model.resetServer()
                } label: {
                    Label("Standardadresse eintragen", systemImage: "arrow.uturn.backward")
                }
                .disabled(model.server == GCVoteService.defaultServer)
                .cacheboxListRow(index: 1)
                CacheboxListText("iCacheBox fragt \(model.server)/getVotes.php wie Cachebox. Wer eine eigene "
                                 + "oder eine dazu passende Kopie des Dienstes betreibt, trägt sie hier ein.")
            }

            CacheboxDivider().cacheboxListDivider()
            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Label("Bewertungen dieser Liste löschen", systemImage: "trash")
            }
            .disabled(model.isRunning || state.lists.current == nil)
            .cacheboxListRow(index: 0)

            CacheboxListText("Über GCVote", isHeader: true)
            CacheboxListText("GCVote ist ein Dienst außerhalb von geocaching.com, mit dem Cacher die Qualität "
                             + "eines Caches von 1 bis 5 bewerten. Die Bewertung steht danach in der Cacheliste, "
                             + "in der Leiste oben, in der Info-Blase der Karte und in den Details – und der "
                             + "Filter zeigt auf Wunsch nur gut bewertete Caches.")
            CacheboxListText("Achtung: gcvote.com antwortet seit geraumer Zeit auf jede Anfrage mit „410 Gone“, "
                             + "der Dienst ist also abgeschaltet (auch Cachebox kommt dort nicht mehr durch). "
                             + "Als Nachfolger gibt es cachevote.org, eine Browser-Erweiterung für "
                             + "geocaching.com ohne Schnittstelle für Apps. Sobald ein erreichbarer Server da "
                             + "ist, funktioniert das Laden hier ohne weitere Änderung.")
        }
        .cacheboxPage()
        .navigationTitle("GCVote-Bewertungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
        .alert("Bewertungen löschen?", isPresented: $confirmClear) {
            Button("Löschen", role: .destructive) { state.clearGCVotes() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle GCVote-Bewertungen der Liste „\(state.lists.currentName ?? "")“ werden entfernt. "
                 + "Ein neues Laden holt sie zurück.")
        }
        .onAppear { model.readLastUpdated(list: state.currentListURL) }
    }

    // MARK: - Pieces

    private var buttonTitle: String {
        codes.isEmpty ? "Keine Caches in der Liste" : "Bewertungen für \(codes.count) Caches laden"
    }

    @ViewBuilder
    private var running: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = model.progress, progress.total > 0 {
                ProgressView(value: Double(min(progress.done, progress.total)), total: Double(progress.total))
                Text("\(progress.done) von \(progress.total) Caches · "
                     + Format.count(progress.rated, "Bewertung", "Bewertungen"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            Button("Abbrechen", role: .cancel) { model.cancel() }
        }
    }

    private func finished(_ result: GCVoteImportResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Fertig", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(GCVoteModel.summary(result))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// "Zuletzt geladen: 23.11.2026, 10:15" or the hint that nothing was loaded yet.
    private var status: String {
        guard let date = model.lastUpdated else {
            return "Für diese Liste wurden noch keine Bewertungen geladen."
        }
        return "Zuletzt geladen: " + date.formatted(date: .numeric, time: .shortened)
    }

    private func start() {
        model.clearResult()
        state.startGCVoteImport()
    }
}

/// The GCVote rating as stars (Cachebox `CacheInfo` with `SHOW_VOTE`), in the GCVote blue
/// (`CacheInfo.gcVoteColor`).
///
/// Deviations from Cachebox: it multiplies its own star sprite - the dark red one that difficulty and terrain use
/// here as well - with the light blue, which really yields a dark red; these stars are drawn as symbols instead, so
/// a GCVote rating is blue and cannot be mistaken for D/T. The blue is a little darker than Cachebox's, so that it
/// still reads on the white and light grey rows of the list.
struct GCVoteStars: View {
    let vote: GCVote
    /// Smaller, for list rows and the slider.
    var isCompact = false
    /// "3,7" behind the stars.
    var showsValue = true
    /// Turned by 90° like in a Cachebox list row, where the stars stand at the left edge.
    var isVertical = false
    @ScaledMetric(relativeTo: .footnote) private var baseHeight: CGFloat = 13

    /// Cachebox `CacheInfo.gcVoteColor` is (0.5, 0.5, 1); a little darker here for the contrast on white rows.
    static let color = Color(red: 0.28, green: 0.33, blue: 0.9)

    private var height: CGFloat { isCompact ? (baseHeight * 0.85).rounded() : baseHeight }

    var body: some View {
        if vote.isRated {
            content
                .font(isCompact ? .caption.weight(.semibold) : .footnote.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.accessibilityText(vote))
        }
    }

    @ViewBuilder
    private var content: some View {
        if isVertical {
            // the rotation does not change the layout, so the frame is swapped by hand
            stars
                .rotationEffect(.degrees(-90))
                .frame(width: height, height: height * 5 + height * 0.4)
        } else {
            HStack(spacing: isCompact ? 3 : 4) {
                stars
                if showsValue {
                    Text(CacheSummary.rating(vote.value))
                        .foregroundStyle(Self.color)
                }
            }
        }
    }

    /// Five stars for the rating, half steps included (Cachebox `Sprites.Stars.get(rating * 2)`).
    private var stars: some View {
        let halves = min(10, max(0, Int((vote.value * 2).rounded())))
        return HStack(spacing: height * 0.1) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: Self.symbol(index: index, halves: halves))
                    .resizable()
                    .scaledToFit()
                    .frame(width: height, height: height)
            }
        }
        .foregroundStyle(Self.color)
    }

    private static func symbol(index: Int, halves: Int) -> String {
        let filled = halves - index * 2
        if filled >= 2 { return "star.fill" }
        return filled == 1 ? "star.leadinghalf.filled" : "star"
    }

    /// "GCVote 3,7 aus 12 Stimmen, deine Stimme 4".
    static func accessibilityText(_ vote: GCVote) -> String {
        var text = "GCVote \(CacheSummary.rating(vote.value))"
        if vote.count > 0 { text += " aus \(Format.count(vote.count, "Stimme", "Stimmen"))" }
        if let own = vote.ownVote { text += ", deine Stimme \(CacheSummary.rating(own))" }
        return text
    }

    /// "3,7 (12 Stimmen)" for the details.
    static func text(_ vote: GCVote) -> String {
        var text = CacheSummary.rating(vote.value)
        if vote.count > 0 { text += " (\(Format.count(vote.count, "Stimme", "Stimmen")))" }
        return text
    }
}

#Preview {
    NavigationStack { GCVoteView() }
        .environment(AppState())
}
