import Foundation

struct SeerrPlexAuthRequest: Encodable {
    let authToken: String
}

struct SeerrLocalAuthRequest: Encodable {
    let email: String
    let password: String
}
