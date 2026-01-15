import Foundation

enum ErrorReporter {
    static func start() {
        #if canImport(Sentry)
            SentrySDK.start { options in
                options.dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String
                options.enableLogs = true
            }
        #endif
    }

    static func capture(_ error: Error) {
        #if canImport(Sentry)
            SentrySDK.capture(error: error)
        #endif
    }
}

#if canImport(Sentry)
    import Sentry
#endif
