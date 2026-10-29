import Foundation

/// Serves canned HTTP responses to a dedicated `URLSession` and records the requests it received.
/// Each stub tags its session with its own header, so tests running in parallel never see each other's traffic.
final nonisolated class HTTPStub: @unchecked Sendable {
    struct Response: Sendable {
        var statusCode: Int
        var headers: [String: String]
        var body: Data

        init(statusCode: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }

        static func json(_ body: Data, statusCode: Int = 200) -> Response {
            Response(statusCode: statusCode, headers: ["Content-Type": "application/json"], body: body)
        }

        static func json(_ body: String, statusCode: Int = 200) -> Response {
            json(Data(body.utf8), statusCode: statusCode)
        }

        static func fixture(_ name: String, statusCode: Int = 200) throws -> Response {
            try json(Fixtures.data(name), statusCode: statusCode)
        }

        static func status(_ statusCode: Int) -> Response {
            Response(statusCode: statusCode)
        }
    }

    typealias Handler = @Sendable (URLRequest) throws -> Response

    fileprivate static let idHeader = "X-HTTPStub-ID"

    let session: URLSession
    private let id = UUID().uuidString
    private let lock = NSLock()
    private var handler: Handler
    private var recordedRequests: [URLRequest] = []

    /// Without a handler, every request fails with a 404.
    init(_ handler: @escaping Handler = { _ in .status(404) }) {
        self.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [Self.idHeader: id]
        session = URLSession(configuration: configuration)
        StubURLProtocol.register(self, id: id)
    }

    deinit {
        StubURLProtocol.unregister(id: id)
        session.invalidateAndCancel()
    }

    func respond(_ handler: @escaping Handler) {
        lock.withLock { self.handler = handler }
    }

    /// Requests in the order they arrived, with their body read back into `httpBody`.
    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    fileprivate func handle(_ request: URLRequest) throws -> Response {
        var recorded = request
        recorded.setValue(nil, forHTTPHeaderField: Self.idHeader)
        recorded.httpBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let handler = lock.withLock {
            recordedRequests.append(recorded)
            return self.handler
        }
        return try handler(recorded)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final nonisolated class StubURLProtocol: URLProtocol {
    private nonisolated(unsafe) static var stubs: [String: HTTPStub] = [:]
    private static let lock = NSLock()

    static func register(_ stub: HTTPStub, id: String) {
        lock.withLock { stubs[id] = stub }
    }

    static func unregister(id: String) {
        lock.withLock { stubs[id] = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: HTTPStub.idHeader) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: HTTPStub.idHeader) ?? ""
        guard let stub = Self.lock.withLock({ Self.stubs[id] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        do {
            let response = try stub.handle(request)
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers,
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
