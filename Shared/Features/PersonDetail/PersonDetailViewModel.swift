import Foundation
import Observation

@MainActor
@Observable
final class PersonDetailViewModel {
    var person: Person
    var items: [MediaDisplayItem] = []
    var isLoadingPerson = false
    var isLoadingMedia = false
    var personErrorMessage: String?
    var mediaErrorMessage: String?
    var imageResource: ArtworkResource?

    @ObservationIgnored private let services: MediaServices
    @ObservationIgnored private var hasLoaded = false

    init(person: Person, services: MediaServices) {
        self.person = person
        self.services = services
    }

    var isLoading: Bool {
        isLoadingPerson || isLoadingMedia
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        await loadPerson()
        await loadMedia()
    }

    private func loadPerson() async {
        isLoadingPerson = true
        personErrorMessage = nil
        defer { isLoadingPerson = false }

        do {
            person = try await services.detail.person(id: person.id)
            imageResource = try await services.artwork.artwork(
                path: person.thumbPath,
                width: 320,
                height: 320
            )
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            personErrorMessage = String(localized: "person.detail.error.loadFailed")
        }
    }

    private func loadMedia() async {
        isLoadingMedia = true
        mediaErrorMessage = nil
        defer { isLoadingMedia = false }

        do {
            items = try await services.detail.personMedia(id: person.id)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            mediaErrorMessage = String(localized: "person.detail.error.loadFailed")
        }
    }
}
