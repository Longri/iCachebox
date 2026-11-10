import SwiftUI

/// First-launch welcome page. Replaces a dialog at start-up (HIG: no alert at launch, keep onboarding to
/// one short screen). Both choices lead into the app; the account can be linked later under
/// Mehr › Geocaching-Konto.
struct WelcomeView: View {
    var onFinish: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var scaledLogoSize: CGFloat = 72
    /// Decorative, so it stops growing at large text sizes.
    private var logoSize: CGFloat { min(scaledLogoSize, 96) }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    intro
                    Spacer(minLength: 24)
                    actions
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 16)
                // Buttons sit at the bottom when everything fits; with large text the page scrolls.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var intro: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: logoSize * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: logoSize, height: logoSize)
                    .background(Color.cachebox.gradient, in: RoundedRectangle(cornerRadius: logoSize * 0.225,
                                                                               style: .continuous))
                    .accessibilityHidden(true)
                Text("Willkommen bei iCacheBox")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Geocaching mit Offline-Karten")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 18) {
                FeatureRow(symbol: "map", title: "Offline-Karten",
                           detail: "Mapsforge-Karten mit Themes und Stilen, auch ohne Netz.")
                FeatureRow(symbol: "shippingbox", title: "Caches immer dabei",
                           detail: "Beschreibung, Hinweis, Wegpunkte und Logs offline lesen.")
                FeatureRow(symbol: "location.north.line", title: "Zum Ziel finden",
                           detail: "Karte und Kompass führen zum Cache oder Wegpunkt.")
                FeatureRow(symbol: "square.and.pencil", title: "Funde notieren",
                           detail: "Feldnotizen unterwegs anlegen und später hochladen.")
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            SignInButton(expands: true, onSuccess: onFinish)
                .buttonStyle(.borderedProminent)
            // Plain text button: tinted text on a tinted fill misses 4.5:1 in dark mode.
            Button(action: onFinish) {
                Text("Ohne Konto starten")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            Text("Ohne Konto nutzt du Offline-Karten und importierte Caches. Anmelden kannst du dich jederzeit unter Mehr › Geocaching-Konto.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .controlSize(.large)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    @ScaledMetric(relativeTo: .title) private var iconWidth: CGFloat = 40
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Icon above the text at accessibility sizes, so the text keeps the full width.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView {}
        .tint(.cachebox)
        .environment(AppState())
}
