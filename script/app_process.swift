import AppKit

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.bitl8byteshort.Teleprompter")
if CommandLine.arguments.dropFirst().first == "stop" {
    // The app handles SIGTERM by flushing pending changes before terminating.
    for app in apps { kill(app.processIdentifier, SIGTERM) }
    for _ in 0..<30 {
        if apps.allSatisfy(\.isTerminated) { exit(0) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    fputs("Teleprompter did not finish saving and quitting. Build left on disk; launch cancelled.\n", stderr)
    exit(1)
} else {
    guard !apps.isEmpty else { exit(1) }
    for app in apps { print("Teleprompter running: \(app.processIdentifier) \(app.bundleURL?.path ?? "")") }
}
