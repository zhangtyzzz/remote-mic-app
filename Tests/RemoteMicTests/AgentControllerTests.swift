import AppKit
import Foundation
import Testing
@testable import RemoteMic

@Suite("Agent controller")
struct AgentControllerTests {
    @Test func discoversDesktopAndTerminalTargetsWithoutConfusingClaudeDesktopForClaudeCode() {
        let harness = makeHarness(
            applicationBundles: [
                PresetApplication.codex.bundleIdentifier,
                PresetApplication.claude.bundleIdentifier,
                PresetApplication.cmux.bundleIdentifier,
                PresetApplication.openCode.bundleIdentifier,
            ],
            executables: ["codex", "grok", "opencode"]
        )

        #expect(harness.model.availability(for: .codex).applicationInstalled)
        #expect(harness.model.availability(for: .grokBuild).canActivate)
        #expect(harness.model.availability(for: .openCode).applicationInstalled)
        #expect(!harness.model.availability(for: .claudeCode).isInstalled)
    }

    @Test func desktopTargetUsesItsApplicationAction() {
        let harness = makeHarness(
            applicationBundles: [PresetApplication.antigravity.bundleIdentifier],
            executables: []
        )
        harness.model.select(.antigravity)

        #expect(harness.model.activateSelected())
        #expect(harness.actions.map(\.0) == [.openAntigravity])
        #expect(harness.model.feedback == .activated(.antigravity))
    }

    @Test func terminalTargetUsesCmuxAndInterruptsWithControlC() throws {
        let harness = makeHarness(
            applicationBundles: [PresetApplication.cmux.bundleIdentifier],
            executables: ["grok"],
            frontmostBundleIdentifier: PresetApplication.cmux.bundleIdentifier
        )
        harness.model.select(.grokBuild)

        #expect(harness.model.activateSelected())
        #expect(harness.model.submit())
        #expect(harness.model.interrupt())
        #expect(harness.actions.map(\.0) == [.openCmux, .returnKey, .customShortcut])
        let shortcut = try #require(harness.actions.last?.1)
        #expect(shortcut.keyCode == 8)
        #expect(shortcut.modifierFlags == .control)
    }

    @Test func submitAndInterruptFailClosedWhenTheSelectedTargetIsNotFrontmost() {
        let harness = makeHarness(
            applicationBundles: [PresetApplication.codex.bundleIdentifier],
            executables: [],
            frontmostBundleIdentifier: "com.example.OtherApp"
        )

        #expect(!harness.model.submit())
        #expect(harness.model.feedback == .notActive(.codex))
        #expect(!harness.model.interrupt())
        #expect(harness.actions.isEmpty)
    }

    @Test func nextAndPreviousSkipUnavailableTargetsAndActivateTheSelection() {
        let harness = makeHarness(
            applicationBundles: [
                PresetApplication.codex.bundleIdentifier,
                PresetApplication.openCode.bundleIdentifier,
            ],
            executables: []
        )
        harness.model.select(.codex)

        #expect(harness.model.selectNext())
        #expect(harness.model.selectedTarget == .openCode)
        #expect(harness.actions.last?.0 == .openOpenCode)

        #expect(harness.model.selectPrevious())
        #expect(harness.model.selectedTarget == .codex)
        #expect(harness.actions.last?.0 == .openCodex)
    }

    @Test func selectedTargetPersists() {
        let suiteName = "AgentControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider: AgentControllerModel.ApplicationURLProvider = { _ in nil }
        let executableProvider: AgentControllerModel.ExecutableURLProvider = { _ in nil }

        let first = AgentControllerModel(
            defaults: defaults,
            applicationURLProvider: provider,
            executableURLProvider: executableProvider,
            actionSender: { _, _ in true }
        )
        first.select(.grokBuild)

        let restored = AgentControllerModel(
            defaults: defaults,
            applicationURLProvider: provider,
            executableURLProvider: executableProvider,
            actionSender: { _, _ in true }
        )
        #expect(restored.selectedTarget == .grokBuild)
    }

    private func makeHarness(
        applicationBundles: Set<String>,
        executables: Set<String>,
        frontmostBundleIdentifier: String? = nil
    ) -> AgentControllerHarness {
        let suiteName = "AgentControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let actions = AgentActionRecorder()
        let model = AgentControllerModel(
            defaults: defaults,
            applicationURLProvider: { bundleIdentifier in
                applicationBundles.contains(bundleIdentifier)
                    ? URL(fileURLWithPath: "/Applications/\(bundleIdentifier).app")
                    : nil
            },
            executableURLProvider: { executable in
                executables.contains(executable)
                    ? URL(fileURLWithPath: "/usr/local/bin/\(executable)")
                    : nil
            },
            frontmostBundleIdentifierProvider: { frontmostBundleIdentifier },
            actionSender: { action, shortcut in
                actions.values.append((action, shortcut))
                return true
            }
        )
        return AgentControllerHarness(model: model, recorder: actions)
    }
}

private final class AgentActionRecorder {
    var values: [(ButtonAction, CustomKeyboardShortcut?)] = []
}

private struct AgentControllerHarness {
    let model: AgentControllerModel
    let recorder: AgentActionRecorder

    var actions: [(ButtonAction, CustomKeyboardShortcut?)] {
        recorder.values
    }
}
