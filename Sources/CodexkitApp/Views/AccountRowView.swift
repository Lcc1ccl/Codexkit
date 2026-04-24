import SwiftUI

enum OpenAIAccountRowLayout {
    static let sectionHorizontalPadding: CGFloat = 16
    static let metricItemSpacing: CGFloat = 4
    static let metricGroupSpacing: CGFloat = 10
    static let metricLabelWidth: CGFloat = 14
    static let primaryProgressWidth: CGFloat = 30
    static let primaryPercentWidth: CGFloat = 27
    static let primaryCountdownWidth: CGFloat = 30
    static let secondaryProgressWidth: CGFloat = 36
    static let secondaryPercentWidth: CGFloat = 27
    static let secondaryCountdownWidth: CGFloat = 30
    static let rowHorizontalPadding: CGFloat = 18
    static let groupHorizontalPadding: CGFloat = 20

    static func usageMetricWidth(
        progressWidth: CGFloat,
        percentWidth: CGFloat,
        countdownWidth: CGFloat
    ) -> CGFloat {
        self.metricLabelWidth +
        progressWidth +
        percentWidth +
        countdownWidth +
        (self.metricItemSpacing * 3)
    }

    static var primaryUsageMetricWidth: CGFloat {
        self.usageMetricWidth(
            progressWidth: self.primaryProgressWidth,
            percentWidth: self.primaryPercentWidth,
            countdownWidth: self.primaryCountdownWidth
        )
    }

    static var secondaryUsageMetricWidth: CGFloat {
        self.usageMetricWidth(
            progressWidth: self.secondaryProgressWidth,
            percentWidth: self.secondaryPercentWidth,
            countdownWidth: self.secondaryCountdownWidth
        )
    }

    static func usageSummaryWidth(windowCount: Int) -> CGFloat {
        guard windowCount > 0 else { return 0 }
        if windowCount == 1 {
            return self.primaryUsageMetricWidth
        }

        return self.primaryUsageMetricWidth +
        self.metricGroupSpacing +
        self.secondaryUsageMetricWidth
    }

    static func totalRowWidth(windowCount: Int) -> CGFloat {
        self.rowHorizontalPadding + self.usageSummaryWidth(windowCount: windowCount)
    }

    static var popoverRowWidthBudget: CGFloat {
        MenuBarStatusItemIdentity.popoverContentWidth -
        self.sectionHorizontalPadding -
        self.groupHorizontalPadding
    }
}

/// One org/account row under an email group
struct AccountRowView: View {
    let account: TokenAccount
    let rowState: OpenAIAccountRowState
    let isRefreshing: Bool
    let usageDisplayMode: CodexBarUsageDisplayMode
    let defaultManualActivationBehavior: CodexBarOpenAIManualActivationBehavior?
    let showsStandaloneCard: Bool
    let onActivate: (OpenAIManualActivationTrigger) -> Void
    let onRefresh: () -> Void
    let onReauth: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    self.planBadge

                    if let runningThreadBadgeTitle = rowState.runningThreadBadgeTitle {
                        Text(runningThreadBadgeTitle)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundColor(.secondary)
                            .clipShape(Capsule())
                    }

                    if self.rowState.isNextUseTarget {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 10))
                    }
                }

                Spacer(minLength: 8)

                self.actionButtons
            }

            self.usageSummary
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(self.showsStandaloneCard ? rowBackgroundColor : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(self.showsStandaloneCard ? rowBorderColor : Color.clear, lineWidth: 0.6)
        }
        .overlay(alignment: .leading) {
            if self.rowState.isNextUseTarget {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .contextMenu {
            if let defaultManualActivationBehavior,
               rowState.showsUseAction {
                ForEach(
                    OpenAIAccountPresentation.manualActivationContextActions(
                        defaultBehavior: defaultManualActivationBehavior
                    ),
                    id: \.behavior
                ) { action in
                    Button {
                        onActivate(action.trigger)
                    } label: {
                        if action.isDefault {
                            Label(action.title, systemImage: "checkmark")
                        } else {
                            Text(action.title)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var usageSummary: some View {
        HStack(alignment: .center, spacing: OpenAIAccountRowLayout.metricGroupSpacing) {
            let windows = account.usageWindowDisplays(mode: self.usageDisplayMode)

            if let primary = windows.first {
                self.usageMetric(
                    primary,
                    progressWidth: OpenAIAccountRowLayout.primaryProgressWidth,
                    percentWidth: OpenAIAccountRowLayout.primaryPercentWidth,
                    countdownWidth: OpenAIAccountRowLayout.primaryCountdownWidth
                )
            }

            if windows.count > 1, let secondary = windows.dropFirst().first {
                self.usageMetric(
                    secondary,
                    progressWidth: OpenAIAccountRowLayout.secondaryProgressWidth,
                    percentWidth: OpenAIAccountRowLayout.secondaryPercentWidth,
                    countdownWidth: OpenAIAccountRowLayout.secondaryCountdownWidth
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func usageMetric(
        _ window: UsageWindowDisplay,
        progressWidth: CGFloat,
        percentWidth: CGFloat,
        countdownWidth: CGFloat
    ) -> some View {
        HStack(spacing: OpenAIAccountRowLayout.metricItemSpacing) {
            Text(window.label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: OpenAIAccountRowLayout.metricLabelWidth, alignment: .leading)

            ProgressView(value: min(max(window.displayPercent, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(usageColor(window))
                .frame(width: progressWidth)

            Text("\(Int(window.displayPercent))%")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: percentWidth, alignment: .leading)

            Text(OpenAIAccountPresentation.resetCountdownText(for: window) ?? "--")
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: countdownWidth, alignment: .leading)
        }
        .padding(.vertical, 2)
        .frame(alignment: .leading)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)

            if account.tokenExpired {
                Button(L.reauth, action: onReauth)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .font(.system(size: 10, weight: .medium))
                    .tint(.orange)
            } else if !account.isBanned {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(
                            isRefreshing
                                ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                : .default,
                            value: isRefreshing
                        )
                }
                .buttonStyle(.borderless)
                .foregroundColor(isRefreshing ? .accentColor : .secondary)
                .disabled(isRefreshing)

                if rowState.showsUseAction {
                    Button(
                        OpenAIAccountPresentation.manualActivationButtonTitle(
                            defaultBehavior: defaultManualActivationBehavior
                        )
                    ) {
                        onActivate(OpenAIAccountPresentation.primaryManualActivationTrigger)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .font(.system(size: 10, weight: .medium))
                }
            }
        }
    }

    private var planBadge: some View {
        Text(
            OpenAIAccountPresentation.planBadgeTitle(
                for: self.account,
                isHovered: false
            )
        )
        .font(.system(size: 9, weight: .medium))
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(planBadgeColor.opacity(0.12))
        .foregroundColor(planBadgeColor)
        .overlay(
            Capsule()
                .stroke(planBadgeColor.opacity(0.18), lineWidth: 0.6)
        )
        .clipShape(Capsule())
    }

    private var rowBackgroundColor: Color {
        if self.rowState.isNextUseTarget { return Color.accentColor.opacity(0.12) }
        return Color.secondary.opacity(0.045)
    }

    private var rowBorderColor: Color {
        if self.rowState.isNextUseTarget { return Color.accentColor.opacity(0.24) }
        return Color.primary.opacity(0.08)
    }

    private var planBadgeColor: Color {
        switch account.planType.lowercased() {
        case "team": return Color(red: 0.38, green: 0.55, blue: 0.78)
        case "plus": return Color(red: 0.34, green: 0.63, blue: 0.48)
        case "pro": return Color(red: 0.50, green: 0.46, blue: 0.80)
        default: return Color.secondary
        }
    }

    private func usageColor(_ window: UsageWindowDisplay) -> Color {
        if window.usedPercent >= 100 { return .red }
        if window.remainingPercent <= OpenAIVisualWarningThreshold.remainingPercent {
            return .orange
        }

        switch self.usageDisplayMode {
        case .remaining:
            return .green
        case .used:
            if window.usedPercent >= 70 { return .orange }
            return .green
        }
    }
}
