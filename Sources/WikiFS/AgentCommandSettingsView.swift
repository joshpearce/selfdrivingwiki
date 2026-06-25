import SwiftUI
import WikiFSCore

/// Settings → Agent tab: configure the agent executable, prefix arguments,
/// model override, extra environment variables, and the optional seatbelt sandbox.
/// Mirrors `ZoteroSettingsView`: a `Form` whose fields persist immediately via
/// `.onChange(of:)` — no explicit save step, so a value is never lost when the
/// Settings window closes.
struct AgentCommandSettingsView: View {
    @State private var executable: String
    @State private var prefixArguments: String
    @State private var modelOverride: String
    @State private var extraEnvironment: String
    @State private var sandboxEnabled: Bool
    @State private var extraAllowedPaths: String

    let containerDirectory: URL

    init(containerDirectory: URL) {
        self.containerDirectory = containerDirectory
        let config = AgentCommandConfig.load(from: containerDirectory)
        _executable = State(initialValue: config.executable)
        _prefixArguments = State(initialValue: config.prefixArguments)
        _modelOverride = State(initialValue: config.modelOverride)
        _extraEnvironment = State(initialValue: config.extraEnvironment)
        let sandbox = SandboxConfig.load(from: containerDirectory)
        _sandboxEnabled = State(initialValue: sandbox.enabled)
        _extraAllowedPaths = State(initialValue: sandbox.extraAllowedPaths)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Executable", text: $executable, prompt: Text("claude"))
                    TextField("Prefix arguments", text: $prefixArguments)
                    TextField("Model override", text: $modelOverride, prompt: Text("default (per-op alias)"))
                } header: {
                    Text("Command")
                }

                Section {
                    TextEditor(text: $extraEnvironment)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 64)
                } header: {
                    Text("Extra Environment")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("KEY=VALUE, one per line. WIKI_ROOT and WIKI_DB are always set by the app and cannot be overridden.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if sandboxEnabled {
                            Text("While the sandbox is on, the app also sets CLAUDE_CONFIG_DIR and TMPDIR (redirecting the provider's config/temp into the scratch dir); any value you set for those keys here is overridden.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                sandboxSection
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Reset to Default") { resetToDefault() }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .onChange(of: executable) { _, _ in saveCommand() }
        .onChange(of: prefixArguments) { _, _ in saveCommand() }
        .onChange(of: modelOverride) { _, _ in saveCommand() }
        .onChange(of: extraEnvironment) { _, _ in saveCommand() }
        .onChange(of: sandboxEnabled) { _, _ in saveSandbox() }
        .onChange(of: extraAllowedPaths) { _, _ in saveSandbox() }
    }

    // MARK: - Sandbox section

    /// The seatbelt section. The sandbox confines the spawned agent's filesystem
    /// WRITES to a strict allowlist (the per-run scratch dir + the active wiki's
    /// database). Reads and network are unaffected. It is provider-agnostic — the
    /// seatbelt wraps whatever executable is set above.
    @ViewBuilder private var sandboxSection: some View {
        Section {
            Toggle("Confine agent writes (macOS seatbelt)", isOn: $sandboxEnabled)

            if sandboxEnabled {
                TextEditor(text: $extraAllowedPaths)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 64)
            }
        } header: {
            Text("Sandbox")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(sandboxEnabled
                     ? "The agent can write ONLY the active wiki's database and its per-run scratch directory; the provider's config and temp are redirected into the scratch dir automatically. Reads and network are unaffected."
                     : "When enabled, the spawned agent is wrapped in macOS's seatbelt (sandbox-exec) so its filesystem writes are confined to the wiki database and a per-run scratch directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if sandboxEnabled {
                    Text("Additional paths the agent may write to — one per line. `~` is expanded to your home. These can only widen the allowlist, never remove the core scratch/database paths.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("`/usr/bin/sandbox-exec` is Apple's long-stable, widely-used seatbelt CLI (Claude Code, Codex CLI, and SwiftPM depend on it). macOS 15+.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Actions

    /// Persist the command fields immediately (auto-save).
    private func saveCommand() {
        let config = AgentCommandConfig(
            executable: executable,
            prefixArguments: prefixArguments,
            modelOverride: modelOverride,
            extraEnvironment: extraEnvironment)
        try? config.save(to: containerDirectory)
    }

    /// Persist the sandbox fields immediately (auto-save) to a separate file.
    private func saveSandbox() {
        let config = SandboxConfig(
            enabled: sandboxEnabled,
            extraAllowedPaths: extraAllowedPaths)
        try? config.save(to: containerDirectory)
    }

    /// Restore the built-in defaults and persist both configs.
    private func resetToDefault() {
        let cmdDefaults = AgentCommandConfig.default
        executable = cmdDefaults.executable
        prefixArguments = cmdDefaults.prefixArguments
        modelOverride = cmdDefaults.modelOverride
        extraEnvironment = cmdDefaults.extraEnvironment

        let sandboxDefaults = SandboxConfig.default
        sandboxEnabled = sandboxDefaults.enabled
        extraAllowedPaths = sandboxDefaults.extraAllowedPaths

        saveCommand()
        saveSandbox()
    }
}
