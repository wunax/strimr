import Foundation

enum ErrorReporter {
    static func start() {
        #if canImport(Sentry)
            let dsn: String?
            #if os(iOS)
                dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN_IOS") as? String
            #elseif os(tvOS)
                dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN_TVOS") as? String
            #elseif os(macOS)
                dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN_MACOS") as? String
            #else
                dsn = nil
            #endif

            guard let dsn, !dsn.isEmpty, dsn != "https://" else { return }
            SentrySDK.start { options in
                options.dsn = dsn
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
