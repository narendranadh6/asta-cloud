import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var prefs = Preferences()
    @State private var prefsLoaded = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var confirmClear = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Profile") {
                TextField("Name for greetings (optional, stays on device)", text: $settings.displayName)
                    .textContentType(.givenName)
            }

            Section {
                Toggle(isOn: $settings.glowEffects) {
                    IconRow(symbol: "sparkles", color: MUSEColor.primary, title: "Neon glow effects")
                }
                Toggle(isOn: $settings.hapticsEnabled) {
                    IconRow(symbol: "hand.tap", color: MUSEColor.accent, title: "Haptic feedback")
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("MUSE uses a dark theme. It follows iOS Reduce Motion, Reduce Transparency and text size settings.")
            }

            Section("Language") {
                Picker(selection: Binding(
                    get: { settings.preferredLanguage ?? "" },
                    set: { settings.preferredLanguage = $0.isEmpty ? nil : $0 })) {
                    ForEach(PlaylistStudioViewModel.languages, id: \.self) {
                        Text($0.isEmpty ? "No preference" : $0).tag($0)
                    }
                } label: {
                    IconRow(symbol: "globe", color: Color(hex: 0x11998E), title: "Preferred music language")
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { prefs.personalizationEnabled },
                    set: { value in
                        prefs.personalizationEnabled = value
                        if !value { prefs.storeAiConversations = false }
                        settings.personalizationEnabled = value
                        savePrefs()
                    })) {
                    IconRow(symbol: "brain.head.profile", color: MUSEColor.secondary,
                            title: "AI personalization", subtitle: "Learn from my MUSE activity")
                }
                Toggle("Keep AI DJ conversations", isOn: Binding(
                    get: { prefs.storeAiConversations },
                    set: { prefs.storeAiConversations = $0; savePrefs() }))
                    .disabled(!prefs.personalizationEnabled)
                NavigationLink { TasteView() } label: {
                    IconRow(symbol: "chart.bar.xaxis", color: MUSEColor.primary,
                            title: "Taste Intelligence", subtitle: "See and correct what MUSE inferred")
                }
            } header: {
                Text("AI personalization")
            } footer: {
                Text("Off by default. When off, MUSE doesn't store recommendation history or "
                     + "feedback, and AI DJ chats are not saved.")
            }

            Section {
                Toggle(isOn: $settings.syncPlaylists) {
                    IconRow(symbol: "arrow.triangle.2.circlepath", color: MUSEColor.accent,
                            title: "Sync playlists", subtitle: "Back up to your MUSE account")
                }
                Toggle("Remember my searches", isOn: Binding(
                    get: { prefs.recordSearchHistory },
                    set: { prefs.recordSearchHistory = $0; savePrefs() }))
                Button("Clear search history", role: .destructive) { confirmClear = true }
            } header: {
                Text("Privacy")
            } footer: {
                Text("No ads, no advertising SDKs, no third-party analytics. Your account is an "
                     + "anonymous device account.")
            }

            Section("Browser") {
                NavigationLink {
                    BrowserHandoffView()
                } label: {
                    IconRow(symbol: "safari", color: Color(hex: 0xFB542B),
                            title: "Open songs in \(settings.browserPreference.label)",
                            subtitle: "Brave handoff · no ad or playback control")
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { settings.weeklyDiscoveryReminder },
                    set: { value in
                        Task {
                            if value {
                                settings.weeklyDiscoveryReminder = await app.notifications.enable()
                            } else {
                                await app.notifications.cancelAll()
                                settings.weeklyDiscoveryReminder = false
                            }
                        }
                    })) {
                    IconRow(symbol: "bell.badge", color: Color(hex: 0xF7971E), title: "Weekly discovery reminder")
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("A local reminder scheduled on this iPhone. MUSE doesn't use push notifications.")
            }

            Section("Your data") {
                Button {
                    Task { await export() }
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        IconRow(symbol: "square.and.arrow.up", color: MUSEColor.accent, title: "Export my data")
                    }
                }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share export file", systemImage: "doc") }
                }
                Button("Delete account and all data", role: .destructive) { confirmDelete = true }
                    .disabled(isDeleting)
            }

            Section("About") {
                LabeledContent("Music metadata", value: app.searchConfigured
                               ? "YouTube Data API" : "Not set up on the server")
                LabeledContent("AI planner", value: app.aiPlanner == "llm" ? "LLM + verification" : "Built-in")
                Text("MUSE is not affiliated with YouTube or Brave. It never streams, downloads or "
                     + "modifies YouTube content.")
                    .font(.footnote).foregroundStyle(MUSEColor.mutedText)
            }
        }
        .museScreen()
        .navigationTitle("Settings")
        .task {
            guard !prefsLoaded, let loaded = try? await app.api.preferences() else { return }
            prefs = loaded
            prefsLoaded = true
            settings.personalizationEnabled = loaded.personalizationEnabled
        }
        .confirmationDialog("Clear search history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                app.library.clearRecentSearches()
                Task { try? await app.api.clearSearchHistory() }
            }
        }
        .confirmationDialog("Delete your MUSE account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This permanently deletes your playlists, preferences and history on the server and this iPhone.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func savePrefs() {
        let snapshot = prefs
        Task {
            do {
                prefs = try await app.api.updatePreferences(snapshot)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let local = try app.library.exportJSON()
            let remote = (try? await app.api.exportData()) ?? Data("null".utf8)
            var combined = Data("{\"device_library\":".utf8)
            combined.append(local)
            combined.append(Data(",\"server_account\":".utf8))
            combined.append(remote)
            combined.append(Data("}".utf8))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("muse-export-\(Int(Date().timeIntervalSince1970)).json")
            try combined.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await app.deleteEverything()
        } catch {
            errorMessage = "Couldn't delete your account: \(error.localizedDescription)"
        }
    }
}
