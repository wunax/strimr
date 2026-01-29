import Foundation

enum SeerrPermission: Int {
    case none = 0
    case admin = 2
    case manageSettings = 4
    case manageUsers = 8
    case manageRequests = 16
    case request = 32
    case vote = 64
    case autoApprove = 128
    case autoApproveMovie = 256
    case autoApproveTV = 512
    case request4K = 1024
    case request4KMovie = 2048
    case request4KTV = 4096
    case requestAdvanced = 8192
    case requestView = 16384
    case autoApprove4K = 32768
    case autoApprove4KMovie = 65536
    case autoApprove4KTV = 131_072
    case requestMovie = 262_144
    case requestTV = 524_288
    case manageIssues = 1_048_576
    case viewIssues = 2_097_152
    case createIssues = 4_194_304
    case autoRequest = 8_388_608
    case autoRequestMovie = 16_777_216
    case autoRequestTV = 33_554_432
    case recentView = 67_108_864
    case watchlistView = 134_217_728
    case manageBlacklist = 268_435_456
    case viewBlacklist = 1_073_741_824
}

struct PermissionCheckOptions {
    enum CheckType {
        case and
        case or
    }

    let type: CheckType

    init(type: CheckType = .and) {
        self.type = type
    }
}

final class SeerrPermissionService {
    func hasPermission(
        _ permissions: SeerrPermission,
        value: Int,
    ) -> Bool {
        if permissions == .none {
            return true
        }

        return hasPermissionValue(value, required: permissions.rawValue)
    }

    func hasPermission(
        _ permissions: [SeerrPermission],
        value: Int,
        options: PermissionCheckOptions = PermissionCheckOptions(),
    ) -> Bool {
        if permissions.isEmpty || permissions == [.none] {
            return true
        }

        if hasPermissionValue(value, required: SeerrPermission.admin.rawValue) {
            return true
        }

        switch options.type {
        case .and:
            return permissions.allSatisfy { hasPermissionValue(value, required: $0.rawValue) }
        case .or:
            return permissions.contains { hasPermissionValue(value, required: $0.rawValue) }
        }
    }

    func hasPermission(
        _ permissions: SeerrPermission,
        user: SeerrUser?,
    ) -> Bool {
        guard let user else {
            return false
        }

        return hasPermission(permissions, value: user.permissions ?? 0)
    }

    func hasPermission(
        _ permissions: [SeerrPermission],
        user: SeerrUser?,
        options: PermissionCheckOptions = PermissionCheckOptions(),
    ) -> Bool {
        guard let user else {
            return false
        }

        return hasPermission(permissions, value: user.permissions ?? 0, options: options)
    }

    private func hasPermissionValue(_ value: Int, required: Int) -> Bool {
        (value & SeerrPermission.admin.rawValue) != 0 || (value & required) != 0
    }
}
