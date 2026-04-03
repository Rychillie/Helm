import SwiftUI

struct ConnectionCard: View {
    let connectionModel: ConnectionModel
    let onPrimaryAction: () -> Void
    let onDisconnect: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HelmTheme.Layout.cardSpacing) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(connectionModel.configuration?.title ?? "OpenClaw")
                        .font(.headline)

                    Text(connectionModel.configuration?.endpointLabel ?? "Set up a gateway to begin.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Label(connectionModel.state.statusTitle, systemImage: connectionModel.state.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(self.statusStyle)
                        .accessibilityIdentifier("connection.status")
                }

                Spacer(minLength: 12)

                if connectionModel.state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let bannerError = connectionModel.bannerError {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(bannerError.title)
                            .font(.subheadline)
                            .bold()
                        Text(bannerError.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            }

            HStack(spacing: 12) {
                Button("Configure", systemImage: "slider.horizontal.3", action: onOpenSettings)
                    .buttonStyle(.bordered)

                if connectionModel.state == .connected {
                    Button("Disconnect", systemImage: "bolt.slash", action: onDisconnect)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .accessibilityIdentifier("connection.disconnect")
                } else {
                    Button(self.primaryActionTitle, systemImage: self.primaryActionSymbol, action: onPrimaryAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!connectionModel.canConnect)
                        .accessibilityIdentifier("connection.primary")
                }
            }
        }
        .padding(HelmTheme.Layout.cardPadding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: HelmTheme.CornerRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: HelmTheme.CornerRadius.card)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }

    private var primaryActionTitle: String {
        switch connectionModel.state {
        case .connectionLost:
            "Reconnect"
        case .failed:
            "Retry"
        default:
            "Connect"
        }
    }

    private var primaryActionSymbol: String {
        switch connectionModel.state {
        case .connectionLost:
            "arrow.clockwise"
        case .failed:
            "arrow.trianglehead.2.clockwise.rotate.90"
        default:
            "bolt.horizontal"
        }
    }

    private var statusStyle: some ShapeStyle {
        switch connectionModel.state {
        case .connected:
            Color.green
        case .connecting, .disconnecting:
            Color.accentColor
        case .connectionLost, .failed:
            Color.orange
        default:
            Color.secondary
        }
    }
}
