import SwiftUI

/// Version of the running build: `1.0.0.<commits>`. `MARKETING_VERSION` gives `1.0.0`; the build phase
/// "Version aus Git" sets `CFBundleVersion` to the number of git commits and adds the build time (`ICBBuildTime`) and
/// whether the build had uncommitted changes (`ICBUncommittedChanges`).
enum AppVersion {
    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    /// "1.0.0.21".
    static var version: String {
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short).\(build)"
    }

    static var buildTime: Date? {
        (info["ICBBuildTime"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
    }

    /// Built from a working copy with changes that are not committed yet, so the number is that of the last commit.
    static var hasUncommittedChanges: Bool {
        info["ICBUncommittedChanges"] as? Bool ?? false
    }
}

/// Mehr › Über (Cachebox `About`): the version and build time, so that it is clear which build is running.
struct AboutView: View {
    var body: some View {
        List {
            VStack(spacing: 4) {
                Text("iCacheBox")
                    .font(.title.weight(.bold))
                Text("Cachebox für das iPhone")
                    .font(.subheadline)
                    .foregroundStyle(Color.black.opacity(0.62))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            .cacheboxPlainRow()
            LabeledContent("Version", value: AppVersion.version)
                .monospacedDigit()
                .cacheboxListRow(index: 1)
            LabeledContent("Erstellt", value: AppVersion.buildTime
                .map { $0.formatted(date: .numeric, time: .shortened) } ?? "unbekannt")
                .monospacedDigit()
                .cacheboxListRow(index: 2)
            if AppVersion.hasUncommittedChanges {
                CacheboxListText("Gebaut mit Änderungen, die noch nicht committet sind; die letzte Stelle der "
                                 + "Version ist die Zahl der Commits bis dahin.")
            }
        }
        .cacheboxPage()
        .navigationTitle("Über")
    }
}

#Preview {
    NavigationStack { AboutView() }
}
