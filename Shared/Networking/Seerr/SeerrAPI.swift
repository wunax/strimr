import Foundation

enum SeerrAPIError: Error {
    case invalidURL
    case requestFailed(statusCode: Int)
    case decodingFailed(Error)
}
