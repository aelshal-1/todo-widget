import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = AppSettings.apiKey
    @State private var modelName = AppSettings.model
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-api03-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model", text: $modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Claude API")
                } footer: {
                    Text("Create a key at console.anthropic.com → API Keys. It's stored only on this iPhone, in the Keychain.")
                }

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        Label(testing ? "Testing…" : "Test with an Arabic sentence", systemImage: "checkmark.seal")
                    }
                    .disabled(testing || key.isEmpty)
                    if let testResult {
                        Text(testResult).font(.footnote)
                    }
                }

                Section("Widget") {
                    HStack {
                        Text("Widget sync")
                        Spacer()
                        Text(AppGroup.isShared ? "Working" : "Not shared")
                            .foregroundStyle(AppGroup.isShared ? Color.green : DueLevel.urgent.foreground)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        persist()
                        dismiss()
                    }
                }
            }
        }
    }

    private func persist() {
        AppSettings.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func test() async {
        persist()
        testing = true
        defer { testing = false }
        do {
            let parsed = try await ClaudeClient.parse("بكرة الساعة ٣ عندي دكتور اسنان")
            let when = parsed.due.map { DueText.format($0, "EEE d MMM, h:mm a") } ?? "no date"
            testResult = "✓ \(parsed.title) — \(when)\(parsed.isAppointment ? " · calendar" : "")"
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }
    }
}
