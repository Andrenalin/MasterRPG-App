// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §6.11: the event carries the verbosity of what happened, and the configured
/// verbosity decides what is logged.
@MainActor
@Suite("Navigation event logging")
struct NavigationEventLoggingTests {
    private final class Recorder {
        var events: [NavigationEvent] = []
    }

    private func makeNavigator(verbosity: NavigationEvent.Verbosity, recorder: Recorder) -> Navigator {
        Navigator(configuration: NavigationConfiguration(
            logger: { recorder.events.append($0) },
            verbosity: verbosity
        ))
    }

    @Test("A warning and an error are logged with their own verbosity")
    func eventKeepsItsVerbosity() {
        let recorder = Recorder()
        let navigator = makeNavigator(verbosity: .info, recorder: recorder)
        recorder.events.removeAll()

        navigator.log(.message("hello"))
        navigator.log(.warning("careful"))
        navigator.log(.error("broken"))

        #expect(recorder.events.map(\.verbosity) == [.info, .warning, .error])
    }

    @Test("A configured verbosity of warning drops info events")
    func configuredVerbosityFilters() {
        let recorder = Recorder()
        let navigator = makeNavigator(verbosity: .warning, recorder: recorder)
        recorder.events.removeAll()

        navigator.log(.message("hello"))
        navigator.log(.warning("careful"))

        #expect(recorder.events.map(\.verbosity) == [.warning])
    }

    @Test("A verbosity of none logs nothing")
    func noneLogsNothing() {
        let recorder = Recorder()
        let navigator = makeNavigator(verbosity: .none, recorder: recorder)

        navigator.log(.error("broken"))

        #expect(recorder.events.isEmpty)
    }
}
