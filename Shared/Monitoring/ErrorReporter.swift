import Foundation

enum ErrorReporter {
    static func start() {
        #if canImport(Sentry)
            SentrySDK.start { options in
                #if os(iOS)
                    options.dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN_IOS") as? String
                #elseif os(tvOS)
                    options.dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN_TVOS") as? String
                #elseif os(visionOS)
                    options.dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN_VISIONOS") as? String
                #endif
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
