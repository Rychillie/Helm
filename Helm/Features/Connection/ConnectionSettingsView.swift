import SwiftUI

struct ConnectionSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private let onSave: (GatewayConfiguration, String?) async -> Bool

    @State private var displayName: String
    @State private var endpointText: String
    @State private var authMode: GatewayAuthMode
    @State private var secret: String
    @State private var timeoutSeconds: Double
    @State private var validationError: UserFacingError?
    @State private var isSaving = false

    init(
        connectionModel: ConnectionModel,
        onSave: @escaping (GatewayConfiguration, String?) async -> Bool)
    {
        let configuration = connectionModel.configuration
        self.onSave = onSave
        _displayName = State(initialValue: configuration?.displayName ?? "")
        _endpointText = State(initialValue: configuration?.endpoint.absoluteString ?? "ws://127.0.0.1:18789")
        _authMode = State(initialValue: configuration?.authMode ?? .none)
        _secret = State(initialValue: "")
        _timeoutSeconds = State(initialValue: configuration?.timeoutSeconds ?? 30)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gateway") {
                    TextField("Display name", text: $displayName)
                        .textInputAutocapitalization(.words)

                    TextField("Gateway WebSocket URL", text: $endpointText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.endpoint")

                    Text("Use the gateway WebSocket URL, such as `ws://127.0.0.1:18789`.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Authentication") {
                    Picker("Mode", selection: $authMode) {
                        ForEach(GatewayAuthMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if let fieldTitle = authMode.fieldTitle {
                        SecureField(fieldTitle, text: $secret)
                    }
                }

                Section("Connection") {
                    LabeledContent("Timeout") {
                        TextField("30", value: $timeoutSeconds, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if let validationError {
                    Section {
                        Label(validationError.message, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task {
                            await self.saveAndConnect()
                        }
                    } label: {
                        if isSaving {
                            Label("Saving…", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        } else {
                            Label("Save and Connect", systemImage: "bolt.horizontal.circle")
                        }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("settings.save")
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveAndConnect() async {
        guard let configuration = self.buildConfiguration() else {
            return
        }

        self.isSaving = true
        let saved = await self.onSave(configuration, self.trimmedSecret)
        self.isSaving = false

        guard saved else {
            return
        }

        self.dismiss()
    }

    private func buildConfiguration() -> GatewayConfiguration? {
        let trimmedEndpoint = self.endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: trimmedEndpoint),
              let scheme = endpoint.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss"
        else {
            self.validationError = .invalidEndpoint()
            return nil
        }

        guard self.timeoutSeconds >= 5, self.timeoutSeconds <= 120 else {
            self.validationError = .invalidTimeout()
            return nil
        }

        if self.authMode != .none, self.trimmedSecret == nil {
            self.validationError = .missingCredential(for: self.authMode)
            return nil
        }

        self.validationError = nil
        return GatewayConfiguration(
            endpoint: endpoint,
            displayName: self.displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            timeoutSeconds: self.timeoutSeconds,
            authMode: self.authMode)
    }

    private var trimmedSecret: String? {
        self.secret.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
