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

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private var hasLoaded = false

    init(person: Person, context: PlexAPIContext) {
        self.person = person
        self.context = context
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

    func imageURL(width: Int = 320, height: Int = 320) -> URL? {
        guard let thumbPath = person.thumbPath,
              let repository = try? ImageRepository(context: context)
        else {
            return nil
        }

        return repository.transcodeImageURL(path: thumbPath, width: width, height: height)
    }

    private func loadPerson() async {
        isLoadingPerson = true
        personErrorMessage = nil
        defer { isLoadingPerson = false }

        do {
            let repository = try PersonRepository(context: context)
            let response = try await repository.getPerson(id: person.id)
            if let directory = response.mediaContainer.directory?.first {
                person = Person(directory: directory)
            }
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
            let repository = try PersonRepository(context: context)
            let response = try await repository.getMedia(id: person.id)
            items = (response.mediaContainer.metadata ?? [])
                .filter(\.type.isSupported)
                .compactMap(MediaDisplayItem.init)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            mediaErrorMessage = String(localized: "person.detail.error.loadFailed")
        }
    }
}
