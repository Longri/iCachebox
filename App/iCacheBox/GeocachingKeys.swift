import CacheboxCore
import Foundation

/// Where the consumer key and secret of the Geocaching API come from.
///
/// They never belong into the repository, so the app reads them at runtime - in this order:
///
/// 1. `GeocachingKeys.plist` in the app bundle. Copy `GeocachingKeys-Beispiel.plist` next to it under that
///    name and fill it in; the file is in `.gitignore`.
/// 2. The keys `ICBGeocachingClientID`, `ICBGeocachingClientSecret`, `ICBGeocachingRedirectURI` and
///    `ICBGeocachingEnvironment` of the Info.plist, which a build server can fill from build settings.
///
/// Without either, `credentials()` returns nil and the sign-in says so instead of running into an error at
/// geocaching.com. Geocaching HQ has not handed out a key for iOS yet (the Android key of Cachebox covers
/// Android only, licence §4.3), so this is the normal state for now.
enum GeocachingKeys {
    /// The redirect used when the key file names none. Has to be registered with HQ exactly like this, and
    /// the scheme has to be in the Info.plist (`CFBundleURLTypes`).
    static let defaultRedirectURI = "icachebox://oauth"

    static func credentials(bundle: Bundle = .main) -> GeocachingCredentials? {
        guard let values = fileValues(in: bundle) ?? infoValues(in: bundle) else { return nil }
        let clientID = string(values["ClientID"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, !clientID.hasPrefix("HIER") else { return nil }
        let redirect = string(values["RedirectURI"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let environment = self.environment(from: values)
        let callbackScheme = string(values["CallbackScheme"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return GeocachingCredentials(
            clientID: clientID,
            clientSecret: string(values["ClientSecret"]).trimmingCharacters(in: .whitespacesAndNewlines),
            redirectURI: redirect.isEmpty ? defaultRedirectURI : redirect,
            environment: environment,
            callbackSchemeOverride: callbackScheme.isEmpty ? nil : callbackScheme)
    }

    /// `production`/`staging`, or the three URLs written out - the latter only to test the sign-in against
    /// a server of one's own, before Geocaching HQ has handed out a key.
    private static func environment(from values: [String: Any]) -> GeocachingEnvironment {
        let named = GeocachingEnvironment.named(string(values["Environment"])) ?? .production
        guard let authorization = URL(string: string(values["AuthorizationURL"])),
              let token = URL(string: string(values["TokenURL"])),
              let api = URL(string: string(values["APIBaseURL"])),
              authorization.host != nil, token.host != nil, api.host != nil else { return named }
        return GeocachingEnvironment(authorizationURL: authorization, tokenURL: token, apiBaseURL: api)
    }

    /// `GeocachingKeys.plist` from the bundle.
    private static func fileValues(in bundle: Bundle) -> [String: Any]? {
        guard let url = bundle.url(forResource: "GeocachingKeys", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = plist as? [String: Any] else { return nil }
        return values
    }

    /// The `ICBGeocaching…` keys of the Info.plist, without the prefix.
    private static func infoValues(in bundle: Bundle) -> [String: Any]? {
        let names = ["ClientID", "ClientSecret", "RedirectURI", "Environment", "CallbackScheme"]
        var values: [String: Any] = [:]
        for name in names {
            if let value = bundle.object(forInfoDictionaryKey: "ICBGeocaching" + name) {
                values[name] = value
            }
        }
        return values.isEmpty ? nil : values
    }

    private static func string(_ value: Any?) -> String {
        (value as? String) ?? ""
    }
}
