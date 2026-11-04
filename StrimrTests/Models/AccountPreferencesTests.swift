import Foundation
@testable import Strimr
import Testing

struct AccountPreferencesTests {
    @Test(arguments: [
        ("fre", "fr"), ("fra", "fr"), ("fr", "fr"), ("FR-fr", "fr"), ("ger", "de"), ("deu", "de"),
        ("eng", "en"), ("en_US", "en"), ("chi", "zh"), ("zxx", "zxx"),
    ])
    func `stored languages are normalized`(stored: String, expected: String) {
        #expect(AccountLanguageCode.normalized(stored) == expected)
    }

    @Test(arguments: ["", "  ", nil] as [String?])
    func `an empty language means no preference`(stored: String?) {
        #expect(AccountLanguageCode.normalized(stored) == nil)
    }

    @Test(arguments: [("fr", "fre"), ("de", "ger"), ("en", "eng"), ("zh", "chi"), ("ja", "jpn")])
    func `Jellyfin receives its own language codes`(code: String, expected: String) {
        #expect(AccountLanguageCode.jellyfinCode(code) == expected)
    }

    @Test func `maps a Jellyfin configuration`() throws {
        let data = try Fixtures.data("jellyfin-user-preferences")
        let user = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let configuration = try #require(user["Configuration"] as? [String: Any])

        #expect(AccountPreferences(jellyfinConfiguration: configuration) == AccountPreferences(
            audioLanguage: "fr",
            selectsAudioByLanguage: true,
            subtitleLanguage: nil,
            subtitleMode: .smart,
        ))
    }

    @Test func `track languages resolve from codes and names`() {
        let expected: [(String?, String?)] = [
            ("fre", "fr"), ("fra", "fr"), ("fr-CA", "fr"), ("French", "fr"), ("français", "fr"),
            ("French (Canada)", "fr"), ("eng", "en"), ("English", "en"),
            (nil, nil), ("", nil), ("und", nil), ("Unknown", nil),
        ]
        for (value, code) in expected {
            #expect(AccountLanguageCode.code(fromTrackLanguage: value) == code, "\(value ?? "nil")")
        }
    }

    @Test func `an unset Jellyfin configuration follows the file`() {
        #expect(AccountPreferences(jellyfinConfiguration: [:]) == .empty)
    }

    @Test func `Jellyfin changes keep the other fields`() {
        var configuration: [String: Any] = ["OrderedViews": ["view-1"], "PlayDefaultAudioTrack": true]

        AccountPreferenceChange.selectsAudioByLanguage(true).apply(toJellyfinConfiguration: &configuration)
        AccountPreferenceChange.audioLanguage("fr").apply(toJellyfinConfiguration: &configuration)
        AccountPreferenceChange.subtitleLanguage(nil).apply(toJellyfinConfiguration: &configuration)
        AccountPreferenceChange.subtitleMode(.off).apply(toJellyfinConfiguration: &configuration)

        #expect(configuration["OrderedViews"] as? [String] == ["view-1"])
        #expect(configuration["PlayDefaultAudioTrack"] as? Bool == false)
        #expect(configuration["AudioLanguagePreference"] as? String == "fre")
        #expect(configuration["SubtitleLanguagePreference"] as? String == "")
        #expect(configuration["SubtitleMode"] as? String == "None")
    }

    @Test func `maps a Plex profile`() throws {
        let profile = try Fixtures.decode(PlexAccountProfile.self, from: "plex-account-profile")

        #expect(AccountPreferences(plexProfile: profile) == AccountPreferences(
            audioLanguage: "fr",
            selectsAudioByLanguage: true,
            subtitleLanguage: "en",
            subtitleMode: .always,
        ))
    }

    @Test func `a Plex profile tolerates other value shapes`() throws {
        let json = #"""
        {"defaultAudioLanguage": ["ja", "en"], "autoSelectAudio": "0", "autoSelectSubtitle": "1"}
        """#
        let profile = try JSONDecoder().decode(PlexAccountProfile.self, from: Data(json.utf8))

        #expect(AccountPreferences(plexProfile: profile) == AccountPreferences(
            audioLanguage: "ja",
            selectsAudioByLanguage: false,
            subtitleLanguage: nil,
            subtitleMode: .smart,
        ))
    }

    @Test func `turning Plex automatic audio off also turns automatic subtitles off`() {
        #expect(AccountPreferenceChange.selectsAudioByLanguage(false).plexQueryItems == [
            URLQueryItem(name: "autoSelectAudio", value: "0"),
            URLQueryItem(name: "autoSelectSubtitle", value: "0"),
        ])
        #expect(AccountPreferenceChange.selectsAudioByLanguage(true).plexQueryItems == [
            URLQueryItem(name: "autoSelectAudio", value: "1"),
        ])
    }

    @Test func `clearing a Plex language sends an empty value`() {
        #expect(AccountPreferenceChange.subtitleLanguage(nil).plexQueryItems == [
            URLQueryItem(name: "defaultSubtitleLanguage", value: ""),
        ])
    }
}
