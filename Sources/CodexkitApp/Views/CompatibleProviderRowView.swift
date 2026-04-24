import SwiftUI

struct CompatibleProviderRowView: View {
    let provider: CodexBarProvider
    let isActiveProvider: Bool
    let activeAccountId: String?
    let onActivate: (CodexBarProviderAccount) -> Void
    let onConfigure: () -> Void
    let onDeleteAccount: (CodexBarProviderAccount) -> Void
    let onDeleteProvider: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(provider.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Text(provider.baseURLBadgeLabel)
                    .font(.system(size: 9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundColor(.secondary)
                    .cornerRadius(3)

                Spacer()

                Button(action: onConfigure) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)

                Button(action: onDeleteProvider) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }

            ForEach(provider.accounts) { account in
                HStack(spacing: 6) {
                    Circle()
                        .fill(account.id == activeAccountId ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)

                    Text(account.label)
                        .font(.system(size: 11, weight: account.id == activeAccountId ? .semibold : .regular))

                    Spacer()

                    Text(account.maskedAPIKey)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if account.id != activeAccountId || isActiveProvider == false {
                        Button("Use") {
                            onActivate(account)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .font(.system(size: 10, weight: .medium))
                    }

                    Button {
                        onDeleteAccount(account)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                }
                .padding(.leading, 14)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActiveProvider ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05))
        )
        .overlay(alignment: .leading) {
            if isActiveProvider {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isActiveProvider ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06), lineWidth: 0.8)
        }
    }
}
