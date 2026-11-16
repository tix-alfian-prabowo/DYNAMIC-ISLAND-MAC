import Foundation
import IOKit.pwr_mgt

/// Holds off the Mac's sleep for a moment, so the app can finish something first, like telling
/// friends it's going offline. NSWorkspace's sleep notification doesn't wait for anyone: the
/// network can be gone before a message goes out.
final class SleepGate {
    // IOKit's messages are C macros, which Swift doesn't import.
    private static let canSystemSleep: natural_t = 0xE000_0270
    private static let systemWillSleep: natural_t = 0xE000_0280

    /// How long sleep may wait at most; macOS allows up to 30 seconds.
    private static let maximumWait: TimeInterval = 3

    private let willSleep: (_ done: @escaping () -> Void) -> Void
    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var notifyPort: IONotificationPortRef?

    /// `willSleep` runs on the main thread as the Mac is about to sleep; it calls `done` once
    /// finished. The Mac sleeps then, or after `maximumWait`, whichever comes first.
    init(willSleep: @escaping (_ done: @escaping () -> Void) -> Void) {
        self.willSleep = willSleep
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(refcon, &notifyPort, { refcon, _, messageType, argument in
            guard let refcon else { return }
            let notificationID = Int(bitPattern: argument)
            MainActor.assumeIsolated {
                Unmanaged<SleepGate>.fromOpaque(refcon).takeUnretainedValue()
                    .handle(messageType, notificationID: notificationID)
            }
        }, &notifier)
        if rootPort != 0, let notifyPort {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .defaultMode)
        }
    }

    private func handle(_ messageType: natural_t, notificationID: Int) {
        switch messageType {
        case Self.canSystemSleep:
            // Idle sleep asks first; never in the way.
            IOAllowPowerChange(rootPort, notificationID)
        case Self.systemWillSleep:
            var allowed = false
            let allow = { [rootPort] in
                guard !allowed else { return }
                allowed = true
                IOAllowPowerChange(rootPort, notificationID)
            }
            willSleep(allow)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.maximumWait, execute: allow)
        default:
            break
        }
    }
}
