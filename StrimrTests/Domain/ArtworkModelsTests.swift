import Foundation
@testable import Strimr
import Testing

struct ArtworkModelsTests {
    private func option(_ id: String, language: String?, isSelected: Bool = false) -> ArtworkOption {
        ArtworkOption(
            id: id,
            previewURL: URL(string: "https://images.test/\(id).jpg")!,
            source: id,
            provider: nil,
            width: nil,
            height: nil,
            language: language,
            isSelected: isSelected,
        )
    }

    @Test func `images in the app language or without text are shown by default`() {
        let options = [option("en", language: "en"), option("fr", language: "fr"), option("none", language: nil)]

        #expect(ArtworkLanguageFilter.visible(options, language: "fr", includeAllLanguages: false).map(\.id)
            == ["fr", "none"])
        #expect(ArtworkLanguageFilter.visible(options, language: "fr", includeAllLanguages: true).map(\.id)
            == ["en", "fr", "none"])
    }

    @Test func `regional codes match their language`() {
        let options = [option("br", language: "pt-BR"), option("en", language: "en")]

        #expect(ArtworkLanguageFilter.visible(options, language: "pt", includeAllLanguages: false).map(\.id) == ["br"])
    }

    @Test func `current image stays visible in another language`() {
        let options = [option("en", language: "en", isSelected: true), option("fr", language: "fr")]

        #expect(ArtworkLanguageFilter.visible(options, language: "fr", includeAllLanguages: false).map(\.id)
            == ["en", "fr"])
    }

    @Test func `language toggle is offered only when some images are hidden`() {
        #expect(ArtworkLanguageFilter.hasOtherLanguages([option("en", language: "en")], language: "fr"))
        #expect(!ArtworkLanguageFilter.hasOtherLanguages(
            [option("fr", language: "FR"), option("none", language: nil)],
            language: "fr",
        ))
    }
}
