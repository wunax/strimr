import Foundation
@testable import Strimr
import Testing

@MainActor
struct PlexItemSettingsTests {
    private func settings() throws -> [ItemSetting] {
        let response = try Fixtures.decode(PlexItemPreferencesResponse.self, from: "plex-item-preferences")
        return PlexManagementService.itemSettings(from: response)
    }

    @Test func `only visible settings with choices are offered`() throws {
        #expect(try settings().map(\.id) == ["episodeSort", "showOrdering", "useOriginalTitle", "languageOverride"])
    }

    @Test func `choices keep the server's values and labels`() throws {
        let episodeSort = try #require(try settings().first)

        #expect(episodeSort.label == "Episode sorting")
        #expect(episodeSort.summary == "How to sort the episodes of this show.")
        #expect(episodeSort.value == "1")
        #expect(episodeSort.options == [
            .init(value: "-1", label: "Library default"),
            .init(value: "0", label: "Oldest first"),
            .init(value: "1", label: "Newest first"),
        ])
    }

    @Test func `an empty value is a choice of its own`() throws {
        let ordering = try #require(try settings().first { $0.id == "showOrdering" })

        #expect(ordering.value == "")
        #expect(ordering.options.first == .init(value: "", label: "Library default"))
        #expect(ordering.summary == nil)
    }

    @Test func `a value missing from the choices is kept as a choice of its own`() throws {
        let setting = try #require(try settings().first { $0.id == "useOriginalTitle" })

        #expect(setting.value == "7")
        #expect(setting.options.map(\.value) == ["7", "-1", "0", "1"])
        #expect(setting.options.first?.label == "7")
    }

    @Test func `percent-encoded choices are decoded`() throws {
        let language = try #require(try settings().first { $0.id == "languageOverride" })

        #expect(language.options == [
            .init(value: "", label: "Library default"),
            .init(value: "fr-FR", label: "Français"),
        ])
    }

    @Test func `settings listed on the item itself are read too`() throws {
        let json = Data("""
        {"MediaContainer": {"Metadata": [{"Setting": [
            {"id": "episodeSort", "label": "Episode sorting", "value": "0", "enumValues": "0:Oldest|1:Newest"}
        ]}]}}
        """.utf8)
        let response = try JSONDecoder().decode(PlexItemPreferencesResponse.self, from: json)

        #expect(PlexManagementService.itemSettings(from: response).map(\.value) == ["0"])
    }

    @Test func `only movies and series have settings`() {
        for type in [MediaKind.movie, .series] {
            #expect(PlexManagementService.supportsAdvancedSettings(for: type))
        }
        for type in [MediaKind.season, .episode, .clip] {
            #expect(!PlexManagementService.supportsAdvancedSettings(for: type))
        }
    }
}
