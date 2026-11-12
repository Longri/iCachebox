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
            case .signedIn(let username, let premium):
                LabeledContent("Benutzer", value: username)
                    .cacheboxListRow(index: 0)
                LabeledContent("Mitgliedschaft", value: premium ? "Premium" : "Basic")
                    .cacheboxListRow(index: 1)
                CacheboxDivider().cacheboxListDivider()
                Button("Abmelden", role: .destructive) { state.account.signOut() }
                    .cacheboxListRow(index: 0)
            }
        }
        .cacheboxPage()
        .navigationTitle("Geocaching-Konto")
    }
}

/// Starts the Geocaching.com sign-in, shows progress and reports failures as an alert.
/// Used on the welcome page and in the account settings.
struct SignInButton: View {
    /// Stretch the label to the full width (for bordered button styles).
    var expands = false
    var onSuccess: () -> Void = {}

    @Environment(AppState.self) private var state
    @State private var signingIn = false
    @State private var error: AccountError?

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
        signingIn = true
        defer { signingIn = false }
        do {
            try await state.account.signIn()
            onSuccess()
        } catch let accountError as AccountError {
            error = accountError
        } catch {
            // ASWebAuthenticationSession cancellation etc. arrives here later; nothing to report yet.
        }
    }
}

#Preview {
    NavigationStack { AccountView() }
        .environment(AppState())
}
