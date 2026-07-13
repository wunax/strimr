import Foundation

enum ErrorReporter {
    static func start() {
        #if canImport(Sentry)
            SentrySDK.start { options in
                #if os(iOS)
                    options.dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN_IOS") as? String
                #elseif os(tvOS)
                    options.dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN_TVOS") as? String
                #endif
                options.enableLogs = true
            }
        #endif
    }

    static func capture(_ error: Error) {
        guard !error.isCancellation else { return }

        #if canImport(Sentry)
            SentrySDK.capture(error: error)
        #endif
    }
}

extension Error {
    var isCancellation: Bool {
        self is CancellationError
            || (self as? URLError)?.code == .cancelled
    }
}

#if canImport(Sentry)
    import Sentry
#endif
