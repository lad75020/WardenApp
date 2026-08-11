import SwiftUI
import AttributedText
import os

struct TabGeneralSettingsView: View {
    private struct BackupErrorAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @AppStorage("chatFontSize", store: AppShellPreferenceStore.defaults) var chatFontSize: Double = 14.0
    @AppStorage("preferredColorScheme", store: AppShellPreferenceStore.defaults) private var preferredColorSchemeRaw: Int = 0
    @AppStorage("enableMultiAgentMode", store: AppShellPreferenceStore.defaults) private var enableMultiAgentMode: Bool = false
    @AppStorage("showSidebarAIIcons", store: AppShellPreferenceStore.defaults) private var showSidebarAIIcons: Bool = true
    @EnvironmentObject private var store: ChatStore
    @State private var selectedColorSchemeRaw: Int = 0
    @State private var backupError: BackupErrorAlert?

    private let fontSizeOptions: [Double] = [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24]

    private var selectedAppearanceLabel: String {
        switch selectedColorSchemeRaw {
        case 1: return "Light"
        case 2: return "Dark"
        default: return "System"
        }
    }

    private var preferredColorScheme: Binding<ColorScheme?> {
        Binding(
            get: {
                switch preferredColorSchemeRaw {
                case 1: return .light
                case 2: return .dark
                default: return nil
                }
            },
            set: { newValue in
                switch newValue {
                case .light: preferredColorSchemeRaw = 1
                case .dark: preferredColorSchemeRaw = 2
                case .none: preferredColorSchemeRaw = 0
                case .some(_): preferredColorSchemeRaw = 0
                }
                selectedColorSchemeRaw = preferredColorSchemeRaw
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("General")
                        .font(.system(size: 24, weight: .bold))
                    Text("Customize appearance and behavior")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                
                // Appearance Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(title: "Appearance", icon: "paintbrush.fill", iconColor: .purple)
                        
                        VStack(spacing: 12) {
                            SettingsRow(title: "Theme") {
                                Picker("", selection: $selectedColorSchemeRaw) {
                                    Text("System").tag(0)
                                    Text("Light").tag(1)
                                    Text("Dark").tag(2)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                                .labelsHidden()
                                .accessibilityIdentifier("settings.theme")
                                .accessibilityValue(selectedAppearanceLabel)
                                .onChange(of: selectedColorSchemeRaw) { _, newValue in
                                    switch newValue {
                                    case 0: preferredColorScheme.wrappedValue = nil
                                    case 1: preferredColorScheme.wrappedValue = .light
                                    case 2: preferredColorScheme.wrappedValue = .dark
                                    default: preferredColorScheme.wrappedValue = nil
                                    }
                                }
                            }
                            
                            SettingsDivider()
                            
                            SettingsRow(title: "Chat Font Size") {
                                Picker("", selection: $chatFontSize) {
                                    ForEach(fontSizeOptions, id: \.self) { size in
                                        Text("\(Int(size)) pt").tag(size)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 100)
                                .labelsHidden()
                                .accessibilityIdentifier("settings.chatFont")
                            }
                            
                            SettingsDivider()
                            
                            SettingsRow(
                                title: "Sidebar Icons",
                                subtitle: "Show AI service logos next to chat names"
                            ) {
                                Toggle("", isOn: $showSidebarAIIcons)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                    .accessibilityIdentifier("settings.sidebarIcons")
                                    .accessibilityLabel(showSidebarAIIcons ? "Sidebar icons shown" : "Sidebar icons hidden")
                            }
                        }
                    }
                }
                
                // Features Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(title: "Features", icon: "sparkles", iconColor: .orange)
                        
                        VStack(spacing: 12) {
                            SettingsRow(
                                title: "Multi-Agent Mode",
                                subtitle: "Query up to 3 AI models simultaneously"
                            ) {
                                Toggle("", isOn: $enableMultiAgentMode)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                            
                            if enableMultiAgentMode {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.system(size: 12))
                                    Text("Beta: May cause instability. Chats are not saved.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.orange)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.orange.opacity(0.1))
                                )
                            }
                        }
                    }
                }
                
                // Data & Privacy Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(title: "Data & Privacy", icon: "lock.shield.fill", iconColor: .green)
                        
                        Text("Export and import your chat history. Data is stored locally in unencrypted JSON format.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Export Chats")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Save all conversations to a file")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Button {
                                    Task {
                                        let result = await store.loadFromCoreData()
                                        handleExportResult(result)
                                    }
                                } label: {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            SettingsDivider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Import Chats")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Restore conversations from a backup")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Button {
                                    let openPanel = NSOpenPanel()
                                    openPanel.allowedContentTypes = [.json]
                                    openPanel.begin { result in
                                        guard result == .OK, let url = openPanel.url else { return }
                                        handleImport(from: url)
                                    }
                                } label: {
                                    Label("Import", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .onAppear {
            selectedColorSchemeRaw = preferredColorSchemeRaw
        }
        .alert(item: $backupError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // MARK: - Backup/Restore Helpers
    private func handleExportResult(_ result: Result<[ChatBackup], Error>) {
        switch result {
        case .failure(let error):
            WardenLog.app.error("Unable to prepare local export")
            _ = error
            showErrorAlert("Export Failed", "Warden could not prepare a local backup. Your existing chats were not changed.")
        case .success(let chats):
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            do {
                let data = try encoder.encode(chats)
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.json]
                savePanel.nameFieldStringValue = "warden_chats_\(getCurrentFormattedDate()).json"
                savePanel.begin { result in
                    guard result == .OK, let url = savePanel.url else { return }
                    do {
                        try data.write(to: url)
                    } catch {
                        showErrorAlert("Export Failed", "Warden could not write the local backup. Your existing chats were not changed.")
                    }
                }
            } catch {
                showErrorAlert("Export Failed", "Warden could not encode a local backup. Your existing chats were not changed.")
            }
        }
    }
    
    private func handleImport(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let chats = try JSONDecoder().decode([ChatBackup].self, from: data)
            
            Task {
                let result = await store.saveToCoreData(chats: chats)
                if case .failure(let error) = result {
                    _ = error
                    showErrorAlert("Import Failed", "Warden could not import this backup. Your existing chats were not changed.")
                }
            }
        } catch {
            WardenLog.app.error("Local backup import failed")
            showErrorAlert("Import Failed", "The selected backup could not be read.")
        }
    }
    
    private func showErrorAlert(_ title: String, _ message: String) {
        backupError = BackupErrorAlert(title: title, message: message)
    }
}
