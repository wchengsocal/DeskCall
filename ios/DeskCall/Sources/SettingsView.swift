import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LookupStore
    @State private var baseURL = AppConfig.localBaseURLString
    @State private var clientKey = AppConfig.localClientKey
    @State private var healthResult: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://your-api.onrender.com", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Client key (optional)", text: $clientKey)

                    Button {
                        AppConfig.setBaseURL(baseURL.trimmingCharacters(in: .whitespaces))
                        AppConfig.setClientKey(clientKey.trimmingCharacters(in: .whitespaces))
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Save and test connection")
                            Spacer()
                            if testing { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(testing)

                    if let healthResult {
                        Text(healthResult)
                            .font(.footnote)
                            .foregroundStyle(healthResult.hasPrefix("Connected") ? .green : .red)
                    }
                } header: {
                    Text("Lookup server")
                } footer: {
                    Text("Point this at your own FastAPI deployment. In mock mode the server answers with demo data, so you can try everything without paid API keys.")
                }

                Section("Privacy") {
                    privacyRow("No contacts permission",
                               "DeskCall has no address-book entitlement, so it cannot read or upload your contacts.")
                    privacyRow("Outbound lookups only",
                               "Requests carry the number being checked and nothing else — no device ID, no account, no analytics.")
                    privacyRow("Transient results",
                               "The server caches answers under a hash for 24 hours, in memory, then forgets them.")
                    privacyRow("Write-only system hook",
                               "The Call Directory extension can only hand names to iOS. It is never told who called you.")
                }

                Section("Diagnostics") {
                    LabeledContent("App Group",
                                   value: store.appGroupAvailable ? "Available" : "Not entitled")
                    LabeledContent("Saved names", value: "\(store.savedForCallerID.count)")
                    LabeledContent("Local history", value: "\(store.history.count)")
                    LabeledContent("Version", value: Self.version)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "\(short ?? "1.0") (\(build ?? "1"))"
    }

    private func testConnection() async {
        testing = true
        defer { testing = false }

        let api = DeskCallAPI(
            baseURL: URL(string: baseURL) ?? AppConfig.bakedBaseURL,
            clientKey: clientKey.isEmpty ? nil : clientKey
        )
        do {
            let health = try await api.health()
            healthResult = "Connected · server is in \(health["mode"] ?? "unknown") mode"
        } catch {
            healthResult = error.localizedDescription
        }
    }

    private func privacyRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "checkmark.shield")
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
