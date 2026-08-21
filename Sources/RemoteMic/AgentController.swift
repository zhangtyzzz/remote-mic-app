import AppKit
import Combine
import Foundation

enum AgentTarget: String, CaseIterable, Codable, Identifiable {
    case codex
    case claudeCode = "claude_code"
    case grokBuild = "grok_build"
    case antigravity
    case openCode = "open_code"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .grokBuild: return "Grok Build"
        case .antigravity: return "Antigravity"
        case .openCode: return "OpenCode"
        }
    }

    var systemImage: String {
        switch self {
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .claudeCode: return "terminal"
        case .grokBuild: return "bolt.horizontal.circle"
        case .antigravity: return "sparkles.rectangle.stack"
        case .openCode: return "curlybraces.square"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .codex: return PresetApplication.codex.bundleIdentifier
        case .antigravity: return PresetApplication.antigravity.bundleIdentifier
        case .openCode: return PresetApplication.openCode.bundleIdentifier
        case .claudeCode, .grokBuild: return nil
        }
    }

    var executableName: String {
        switch self {
        case .codex: return "codex"
        case .claudeCode: return "claude"
        case .grokBuild: return "grok"
        case .antigravity: return "agy"
        case .openCode: return "opencode"
        }
    }

    var prefersDesktopApplication: Bool {
        switch self {
        case .codex, .antigravity, .openCode: return true
        case .claudeCode, .grokBuild: return false
        }
    }

    var desktopActivationAction: ButtonAction? {
        switch self {
        case .codex: return .openCodex
        case .antigravity: return .openAntigravity
        case .openCode: return .openOpenCode
        case .claudeCode, .grokBuild: return nil
        }
    }
}

struct AgentTargetAvailability: Equatable {
    let applicationInstalled: Bool
    let commandInstalled: Bool
    let terminalHostInstalled: Bool

    var isInstalled: Bool {
        applicationInstalled || commandInstalled
    }

    var canActivate: Bool {
        applicationInstalled || (commandInstalled && terminalHostInstalled)
    }

    var usesDesktopApplication: Bool {
        applicationInstalled
    }
}

enum AgentControllerFeedback: Equatable {
    case idle
    case selected(AgentTarget)
    case activated(AgentTarget)
    case submitted(AgentTarget)
    case interrupted(AgentTarget)
    case unavailable(AgentTarget)
    case notActive(AgentTarget)
    case permissionRequired
}

final class AgentControllerModel: ObservableObject {
    typealias ApplicationURLProvider = (String) -> URL?
    typealias ExecutableURLProvider = (String) -> URL?
    typealias FrontmostBundleIdentifierProvider = () -> String?
    typealias ActionSender = (ButtonAction, CustomKeyboardShortcut?) -> Bool

    private static let selectedTargetKey = "AgentController.selectedTarget"

    @Published private(set) var selectedTarget: AgentTarget
    @Published private(set) var availability: [AgentTarget: AgentTargetAvailability] = [:]
    @Published private(set) var feedback: AgentControllerFeedback = .idle

    private let defaults: UserDefaults
    private let applicationURLProvider: ApplicationURLProvider
    private let executableURLProvider: ExecutableURLProvider
    private let frontmostBundleIdentifierProvider: FrontmostBundleIdentifierProvider
    private let actionSender: ActionSender

    init(
        defaults: UserDefaults = .standard,
        applicationURLProvider: @escaping ApplicationURLProvider = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        executableURLProvider: @escaping ExecutableURLProvider = AgentControllerModel.defaultExecutableURL,
        frontmostBundleIdentifierProvider: @escaping FrontmostBundleIdentifierProvider = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        actionSender: @escaping ActionSender = {
            KeyboardInjector.send($0, shortcut: $1)
        }
    ) {
        self.defaults = defaults
        self.applicationURLProvider = applicationURLProvider
        self.executableURLProvider = executableURLProvider
        self.frontmostBundleIdentifierProvider = frontmostBundleIdentifierProvider
        self.actionSender = actionSender
        selectedTarget = defaults.string(forKey: Self.selectedTargetKey)
            .flatMap(AgentTarget.init(rawValue:)) ?? .codex
        refreshAvailability()
    }

    func refreshAvailability() {
        let terminalHostInstalled = applicationURLProvider(
            PresetApplication.cmux.bundleIdentifier
        ) != nil
        availability = Dictionary(uniqueKeysWithValues: AgentTarget.allCases.map { target in
            let applicationInstalled = target.bundleIdentifier
                .flatMap(applicationURLProvider) != nil
            let commandInstalled = executableURLProvider(target.executableName) != nil
            return (
                target,
                AgentTargetAvailability(
                    applicationInstalled: applicationInstalled,
                    commandInstalled: commandInstalled,
                    terminalHostInstalled: terminalHostInstalled
                )
            )
        })
    }

    func availability(for target: AgentTarget) -> AgentTargetAvailability {
        availability[target] ?? AgentTargetAvailability(
            applicationInstalled: false,
            commandInstalled: false,
            terminalHostInstalled: false
        )
    }

    func select(_ target: AgentTarget) {
        selectedTarget = target
        defaults.set(target.rawValue, forKey: Self.selectedTargetKey)
        feedback = .selected(target)
    }

    @discardableResult
    func selectNext() -> Bool {
        selectRelative(offset: 1)
    }

    @discardableResult
    func selectPrevious() -> Bool {
        selectRelative(offset: -1)
    }

    @discardableResult
    func activateSelected() -> Bool {
        refreshAvailability()
        let targetAvailability = availability(for: selectedTarget)
        guard targetAvailability.canActivate else {
            feedback = .unavailable(selectedTarget)
            return false
        }

        let action: ButtonAction
        if targetAvailability.usesDesktopApplication,
           let desktopAction = selectedTarget.desktopActivationAction {
            action = desktopAction
        } else {
            action = .openCmux
        }

        guard actionSender(action, nil) else {
            feedback = .permissionRequired
            return false
        }
        feedback = .activated(selectedTarget)
        return true
    }

    @discardableResult
    func submit() -> Bool {
        guard availability(for: selectedTarget).canActivate else {
            feedback = .unavailable(selectedTarget)
            return false
        }
        guard isSelectedTargetFrontmost else {
            feedback = .notActive(selectedTarget)
            return false
        }
        guard actionSender(.returnKey, nil) else {
            feedback = .permissionRequired
            return false
        }
        feedback = .submitted(selectedTarget)
        return true
    }

    @discardableResult
    func interrupt() -> Bool {
        guard availability(for: selectedTarget).canActivate else {
            feedback = .unavailable(selectedTarget)
            return false
        }
        guard isSelectedTargetFrontmost else {
            feedback = .notActive(selectedTarget)
            return false
        }

        let handled: Bool
        if availability(for: selectedTarget).usesDesktopApplication {
            handled = actionSender(.escape, nil)
        } else {
            handled = actionSender(
                .customShortcut,
                CustomKeyboardShortcut(
                    keyCode: 8,
                    modifierFlags: .control,
                    keyLabel: "C"
                )
            )
        }
        guard handled else {
            feedback = .permissionRequired
            return false
        }
        feedback = .interrupted(selectedTarget)
        return true
    }

    private var isSelectedTargetFrontmost: Bool {
        let selectedAvailability = availability(for: selectedTarget)
        let expectedBundleIdentifier = selectedAvailability.usesDesktopApplication
            ? selectedTarget.bundleIdentifier
            : PresetApplication.cmux.bundleIdentifier
        return frontmostBundleIdentifierProvider() == expectedBundleIdentifier
    }

    private func selectRelative(offset: Int) -> Bool {
        refreshAvailability()
        let candidates = AgentTarget.allCases.filter { availability(for: $0).canActivate }
        guard !candidates.isEmpty else {
            feedback = .unavailable(selectedTarget)
            return false
        }
        let currentIndex = candidates.firstIndex(of: selectedTarget) ?? (offset > 0 ? -1 : 0)
        let nextIndex = (currentIndex + offset + candidates.count) % candidates.count
        select(candidates[nextIndex])
        return activateSelected()
    }

    private static func defaultExecutableURL(name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)"),
            home.appendingPathComponent(".local/bin/\(name)"),
            home.appendingPathComponent(".grok/bin/\(name)"),
            home.appendingPathComponent(".opencode/bin/\(name)"),
            home.appendingPathComponent(".claude/bin/\(name)"),
        ]
        return candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        })
    }
}
