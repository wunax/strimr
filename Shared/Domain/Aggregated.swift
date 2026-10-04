import Foundation

/// Result of a request sent to several servers. Only `succeeded` servers count as loaded; the others are retried on
/// the next refresh or when they come back online.
struct Aggregated<Value> {
    var value: Value
    var succeeded: Set<ServerIdentity> = []
    var failed: Set<ServerIdentity> = []
    var cancelled: Set<ServerIdentity> = []
    /// Offline, disabled, or without the requested capability.
    var skipped: Set<ServerIdentity> = []

    var queried: Set<ServerIdentity> {
        succeeded.union(failed).union(cancelled)
    }

    func map<Other>(_ transform: (Value) -> Other) -> Aggregated<Other> {
        Aggregated<Other>(
            value: transform(value),
            succeeded: succeeded,
            failed: failed,
            cancelled: cancelled,
            skipped: skipped,
        )
    }
}

extension Aggregated: Sendable where Value: Sendable {}
extension Aggregated: Equatable where Value: Equatable {}
