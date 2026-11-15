import CacheboxCore
import SwiftUI

/// Mehr › Geocaching-Konto: sign-in state and sign-in/sign-out, in the Cachebox day skin.
struct AccountView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        List {
            switch state.account.status {
            case .signedOut:
                Label("Nicht angemeldet", systemImage: "person.crop.circle.badge.questionmark")
                    .cacheboxListRow(index: 0)
                CacheboxListText("Mit einem Geocaching.com-Konto holst du Caches aufs Gerät und lädst Feldnotizen hoch.")
                SignInButton()
                    .cacheboxListRow(index: 0)
                if !state.account.isConfigured {
                    CacheboxListText("Für iOS gibt es noch keinen API-Schlüssel von Geocaching HQ. "
                        + "Die Anmeldung ist fertig eingebaut und wartet nur auf den Schlüssel.")
                }
            case .signedIn(let username, let premium):
                signedIn(username: username, premium: premium)
            }
        }
        .cacheboxPage()
        .navigationTitle("Geocaching-Konto")
        .refreshable { await state.account.refreshUser() }
    }

    @ViewBuilder
    private func signedIn(username: String, premium: Bool) -> some View {
        let user = state.account.user
        LabeledContent("Benutzer", value: username)
            .cacheboxListRow(index: 0)
        LabeledContent("Mitgliedschaft", value: user?.membership.name ?? (premium ? "Premium" : "Basic"))
            .cacheboxListRow(index: 1)
        if let user {
            LabeledContent("Funde", value: user.findCount.formatted())
                .cacheboxListRow(index: 2)
            LabeledContent("Eigene Caches", value: user.hideCount.formatted())
                .cacheboxListRow(index: 3)
            LabeledContent("Favoritenpunkte", value: user.favoritePoints.formatted())
                .cacheboxListRow(index: 4)
            if let joined = user.joinedDate {
                LabeledContent("Dabei seit", value: joined.formatted(date: .abbreviated, time: .omitted))
                    .cacheboxListRow(index: 5)
            }
        }
        if state.account.isStaging {
            CacheboxListText("Testzugang (Staging): die App sieht nur Testdaten von Geocaching HQ, "
                + "nicht die echten Caches.")
        }
        CacheboxDivider().cacheboxListDivider()
        Button("Abmelden", role: .destructive) { Task { await state.account.signOut() } }
            .cacheboxListRow(index: 0)
        CacheboxListText("Abmelden löscht den Zugang nur auf diesem Gerät. Den Zugriff ganz entziehen kannst "
            + "du in deinem Profil auf geocaching.com.")
    }
}

/// Starts the Geocaching.com sign-in, shows progress and reports failures as an alert.
/// Used on the welcome page and in the account settings.
struct SignInButton: View {
    /// Stretch the label to the full width (for bordered button styles).
    var expands = false
    var onSuccess: () -> Void = {}

    @Environment(AppState.self) private var state
    @State private var error: AccountError?

    private var signingIn: Bool { state.account.isWorking }

    var body: some View {
        Button {
            Task { await signIn() }
        } label: {
            HStack(spacing: 8) {
                if signingIn { ProgressView() }
                Text("Mit Geocaching.com anmelden")
            }
            .frame(maxWidth: expands ? .infinity : nil)
        }
        .disabled(signingIn)
        .alert(isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }), error: error) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.recoverySuggestion ?? "")
        }
    }

    private func signIn() async {
        do {
            try await state.account.signIn()
            onSuccess()
        } catch AccountError.cancelled {
            // the user closed the sign-in window; nothing to report
        } catch let accountError as AccountError {
            error = accountError
        } catch {
            self.error = .failed(error.localizedDescription, recovery: nil)
        }
    }
}

#Preview {
    NavigationStack { AccountView() }
        .environment(AppState())
}
