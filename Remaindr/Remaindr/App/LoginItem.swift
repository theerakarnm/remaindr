import Foundation
import ServiceManagement

/// Launch at login via SMAppService. Registration can legitimately fail when the app runs
/// from a build directory, so the caller shows the error rather than assuming success.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
