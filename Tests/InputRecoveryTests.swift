import Testing
@testable import TeleprompterCore

@Test func startupConfigurationChangeRestartsStoppedInput() {
    var recovery = InputRecovery()
    #expect(recovery.action(now: 0.08, isRunning: false, formatUnchanged: false) == .rebuild)
}

@Test func harmlessNotificationDoesNotInterruptWorkingInput() {
    var recovery = InputRecovery()
    for _ in 0..<10 {
        #expect(recovery.action(now: 0.2, isRunning: true, formatUnchanged: true) == .keepRunning)
    }
    #expect(recovery.action(now: 0.3, isRunning: false, formatUnchanged: true) == .rebuild)
}

@Test func changedFormatRebuildsEvenWhenEngineIsRunning() {
    var recovery = InputRecovery()
    #expect(recovery.action(now: 10, isRunning: true, formatUnchanged: false) == .rebuild)
}

@Test func unstableDeviceCannotCauseAnEndlessRecoveryLoop() {
    var recovery = InputRecovery()
    #expect(recovery.action(now: 0, isRunning: false, formatUnchanged: false) == .rebuild)
    #expect(recovery.action(now: 1, isRunning: false, formatUnchanged: false) == .rebuild)
    #expect(recovery.action(now: 2, isRunning: false, formatUnchanged: false) == .rebuild)
    #expect(recovery.action(now: 3, isRunning: false, formatUnchanged: false) == .stop)
    // A later, separate hardware change can recover again.
    #expect(recovery.action(now: 10, isRunning: false, formatUnchanged: false) == .rebuild)
}
