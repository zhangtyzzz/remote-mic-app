import SwiftUI

struct AgentControllerSection: View {
    @ObservedObject var model: AgentControllerModel
    @EnvironmentObject private var localization: LocalizationStore

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("settings.section.agents")
                .font(.system(size: 24, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    currentTargetCard

                    VStack(alignment: .leading, spacing: 10) {
                        Text("agent_controller.targets.title")
                            .font(.system(size: 16, weight: .semibold))

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(AgentTarget.allCases) { target in
                                targetCard(target)
                            }
                        }
                    }

                    controlGuide
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            model.refreshAvailability()
        }
    }

    private var currentTargetCard: some View {
        HStack(spacing: 16) {
            Image(systemName: model.selectedTarget.systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 5) {
                Text("agent_controller.current.title")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(model.selectedTarget.displayName)
                    .font(.system(size: 20, weight: .semibold))
                feedbackText
                    .font(.system(size: 12))
                    .foregroundStyle(feedbackColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button("agent_controller.action.activate") {
                _ = model.activateSelected()
            }
            .compatibilityButtonStyle(.prominent)
            .disabled(!model.availability(for: model.selectedTarget).canActivate)

            Button {
                model.refreshAvailability()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .compatibilityButtonStyle(.standard)
            .help("agent_controller.action.refresh")
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentColor.opacity(0.24))
        }
    }

    private func targetCard(_ target: AgentTarget) -> some View {
        let targetAvailability = model.availability(for: target)
        let selected = model.selectedTarget == target
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: target.systemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(target.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Text(availabilityLabel(targetAvailability))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(availabilityColor(targetAvailability))
                }

                Spacer(minLength: 0)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel(Text("agent_controller.current.badge"))
                }
            }

            Text(routeDescription(target, availability: targetAvailability))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(selected ? "agent_controller.action.selected" : "agent_controller.action.select") {
                    model.select(target)
                }
                .compatibilityButtonStyle(selected ? .prominent : .standard)
                .disabled(selected)

                Spacer(minLength: 8)

                if selected {
                    Button("agent_controller.action.activate_short") {
                        _ = model.activateSelected()
                    }
                    .compatibilityButtonStyle(.standard)
                    .disabled(!targetAvailability.canActivate)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        .background(
            selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    selected ? Color.accentColor.opacity(0.48) : Color.secondary.opacity(0.16)
                )
        }
    }

    private var controlGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("agent_controller.controls.title")
                .font(.system(size: 16, weight: .semibold))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                controlGuideItem("arrow.left.arrow.right", "agent_controller.controls.switch")
                controlGuideItem("scope", "agent_controller.controls.activate")
                controlGuideItem("return", "agent_controller.controls.submit")
                controlGuideItem("stop.circle", "agent_controller.controls.interrupt")
            }

            Text("agent_controller.controls.terminal_note")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func controlGuideItem(_ systemImage: String, _ key: LocalizedStringKey) -> some View {
        Label(key, systemImage: systemImage)
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var feedbackText: some View {
        switch model.feedback {
        case .idle:
            Text("agent_controller.feedback.ready")
        case let .selected(target):
            Text(String(format: localization.text("agent_controller.feedback.selected"), target.displayName))
        case let .activated(target):
            Text(String(format: localization.text("agent_controller.feedback.activated"), target.displayName))
        case let .submitted(target):
            Text(String(format: localization.text("agent_controller.feedback.submitted"), target.displayName))
        case let .interrupted(target):
            Text(String(format: localization.text("agent_controller.feedback.interrupted"), target.displayName))
        case let .unavailable(target):
            Text(String(format: localization.text("agent_controller.feedback.unavailable"), target.displayName))
        case let .notActive(target):
            Text(String(format: localization.text("agent_controller.feedback.not_active"), target.displayName))
        case .permissionRequired:
            Text("agent_controller.feedback.permission_required")
        }
    }

    private var feedbackColor: Color {
        switch model.feedback {
        case .unavailable, .notActive, .permissionRequired: return .orange
        case .activated, .submitted, .interrupted: return .green
        case .idle, .selected: return .secondary
        }
    }

    private func availabilityLabel(_ availability: AgentTargetAvailability) -> String {
        if availability.applicationInstalled {
            return localization.text("agent_controller.status.app_installed")
        }
        if availability.commandInstalled && availability.terminalHostInstalled {
            return localization.text("agent_controller.status.cli_installed")
        }
        if availability.commandInstalled {
            return localization.text("agent_controller.status.terminal_missing")
        }
        return localization.text("agent_controller.status.not_installed")
    }

    private func availabilityColor(_ availability: AgentTargetAvailability) -> Color {
        availability.canActivate ? .green : availability.isInstalled ? .orange : .secondary
    }

    private func routeDescription(
        _ target: AgentTarget,
        availability: AgentTargetAvailability
    ) -> String {
        if availability.applicationInstalled {
            return localization.text("agent_controller.route.desktop")
        }
        if availability.commandInstalled && availability.terminalHostInstalled {
            return String(
                format: localization.text("agent_controller.route.cmux"),
                target.executableName
            )
        }
        if availability.commandInstalled {
            return localization.text("agent_controller.route.cmux_required")
        }
        return String(
            format: localization.text("agent_controller.route.install_command"),
            target.executableName
        )
    }
}
