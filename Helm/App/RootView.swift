import SwiftUI

struct RootView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(.systemGroupedBackground),
                        Color(.secondarySystemGroupedBackground),
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
                    .ignoresSafeArea()

                Group {
                    if appModel.connectionModel.configuration == nil {
                        ContentUnavailableView {
                            Label("Connect to OpenClaw", systemImage: "wave.3.right.circle")
                        } description: {
                            Text("Helm starts with one calm, trustworthy conversation surface.")
                        } actions: {
                            Button("Configure OpenClaw") {
                                appModel.showingConnectionSettings = true
                            }
                            .accessibilityIdentifier("root.configure")
                        }
                    } else {
                        VStack(spacing: HelmTheme.Layout.screenSpacing) {
                            ConnectionCard(
                                connectionModel: appModel.connectionModel,
                                onPrimaryAction: {
                                    Task {
                                        if appModel.connectionModel.state == .connected {
                                            await appModel.disconnect()
                                        } else if appModel.connectionModel.state == .connectionLost {
                                            await appModel.reconnect()
                                        } else {
                                            await appModel.connect()
                                        }
                                    }
                                },
                                onDisconnect: {
                                    Task {
                                        await appModel.disconnect()
                                    }
                                },
                                onOpenSettings: {
                                    appModel.showingConnectionSettings = true
                                })

                            ChatView(
                                connectionModel: appModel.connectionModel,
                                chatModel: appModel.chatModel,
                                onSend: {
                                    Task {
                                        await appModel.sendDraft()
                                    }
                                },
                                onRetry: { message in
                                    Task {
                                        await appModel.retry(message)
                                    }
                                })
                        }
                        .frame(maxWidth: HelmTheme.Layout.maxTranscriptWidth)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle("Helm")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "slider.horizontal.3") {
                        appModel.showingConnectionSettings = true
                    }
                }
            }
            .sheet(isPresented: $appModel.showingConnectionSettings) {
                ConnectionSettingsView(connectionModel: appModel.connectionModel) { configuration, secret in
                    await appModel.saveConfigurationAndConnect(configuration: configuration, secret: secret)
                }
            }
        }
    }
}
