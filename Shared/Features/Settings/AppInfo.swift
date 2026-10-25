import Foundation

enum AppInfo {
    static let sourceCodeURL = URL(string: "https://github.com/wunax/strimr")!
    static let issuesURL = URL(string: "https://github.com/wunax/strimr/issues")!
    static let testFlightURL = URL(string: "https://testflight.apple.com/join/nayaffkP")!
    static let privacyPolicyURL =
        URL(string: "https://github.com/wunax/strimr/blob/main/Documentation/PRIVACY_POLICY.md")!
    static let reviewURL = URL(string: "https://apps.apple.com/app/id6757491271?action=write-review")!

    static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
