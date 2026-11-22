import AppKit

// Single instance: a second launch (e.g. opening the app again from Spotlight) toggles the
// running visor instead of starting a copy that can't register the hotkey.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
       .contains(where: { $0 != NSRunningApplication.current }) {
    DistributedNotificationCenter.default().postNotificationName(
        .awningToggle, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
