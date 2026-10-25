import Foundation

enum ErrorReporter {
    private static let enabledKey = "strimr.diagnostics.errorReporting"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            start()
        } else {
            #if canImport(Sentry)
                SentrySDK.close()
            #endif
        }
    }

    static func start() {
        // Unit tests run hosted in the app; keep test-induced errors out of production Sentry.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil, isEnabled else { return }

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
                // Automatic capture reports 5xx from self-hosted servers and third-party proxies we can't act on.
                options.enableCaptureFailedRequests = false
                options.beforeBreadcrumb = { breadcrumb in
                    breadcrumb.data = removingSensitiveData(from: breadcrumb.data)
                    return breadcrumb
                }
            }
        #endif
    }

    static func capture(_ error: Error) {
        guard !error.isCancellation, !(error is any ExpectedConnectivityError) else { return }
        #if !os(tvOS)
            guard !error.isTransportFailure, !error.isHostUnreachable else { return }
        #endif

        #if canImport(Sentry)
            SentrySDK.capture(error: error)
        #endif
    }

    /// Plex and Jellyfin pass access tokens in query strings, which network breadcrumbs record.
    static func removingSensitiveData(from data: [String: Any]?) -> [String: Any]? {
        data?.filter { key, _ in key != "http.query" && key != "http.fragment" }
    }
}

/// Errors that describe an expected lack of connectivity and must never be reported.
protocol ExpectedConnectivityError: Error {}

extension Error {
    var isCancellation: Bool {
        self is CancellationError
            || (self as? URLError)?.code == .cancelled
    }

    /// Surfaces outside `URLError` when a LAN address is unreachable or local network access is denied.
    var isHostUnreachable: Bool {
        let error = self as NSError
        return error.domain == NSPOSIXErrorDomain && error.code == Int(EHOSTUNREACH)
    }
}

#if canImport(Sentry)
    import Sentry
#endif
