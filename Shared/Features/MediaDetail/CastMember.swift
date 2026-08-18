import Foundation

struct CastMember: Identifiable, Hashable {
    let id: String
    let personID: String?
    let name: String
    let character: String?
    let thumbPath: String?

    var person: Person? {
        guard let personID else { return nil }
        return Person(id: personID, name: name, thumbPath: thumbPath)
    }
}
