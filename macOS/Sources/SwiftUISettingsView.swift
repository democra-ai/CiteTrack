import SwiftUI
import AppKit

// MARK: - SwiftUI Settings View
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label(L("sidebar_general"), systemImage: "gearshape")
                }

            ScholarsSettingsTab()
                .tabItem {
                    Label(L("sidebar_scholars"), systemImage: "person.2")
                }

            DataSettingsTab()
                .tabItem {
                    Label(L("sidebar_data"), systemImage: "externaldrive")
                }
        }
        .frame(minWidth: 560, minHeight: 460)
    }
}

// MARK: - General Settings Tab
struct GeneralSettingsTab: View {
    @State private var updateIntervalIndex: Int
    @State private var showInDock: Bool
    @State private var showInMenuBar: Bool
    @State private var launchAtLogin: Bool
    @State private var iCloudSyncEnabled: Bool
    @State private var selectedLanguageIndex: Int

    private let intervals: [(String, TimeInterval)] = [
        (L("interval_30min"), 1800),
        (L("interval_1hour"), 3600),
        (L("interval_2hours"), 7200),
        (L("interval_6hours"), 21600),
        (L("interval_12hours"), 43200),
        (L("interval_1day"), 86400),
        (L("interval_3days"), 259200),
        (L("interval_1week"), 604800)
    ]

    private let languages = LocalizationManager.Language.allCases

    init() {
        let prefs = PreferencesManager.shared
        let currentInterval = prefs.updateInterval
        let intervals: [TimeInterval] = [1800, 3600, 7200, 21600, 43200, 86400, 259200, 604800]
        let idx = intervals.firstIndex(of: currentInterval) ?? 5
        _updateIntervalIndex = State(initialValue: idx)
        _showInDock = State(initialValue: prefs.showInDock)
        _showInMenuBar = State(initialValue: prefs.showInMenuBar)
        _launchAtLogin = State(initialValue: prefs.launchAtLogin)
        _iCloudSyncEnabled = State(initialValue: prefs.iCloudSyncEnabled)

        let currentLang = LocalizationManager.shared.currentLanguageCode
        let langIdx = LocalizationManager.Language.allCases.firstIndex { $0.rawValue == currentLang } ?? 0
        _selectedLanguageIndex = State(initialValue: langIdx)
    }

    var body: some View {
        Form {
            Section {
                Picker(L("setting_update_interval"), selection: $updateIntervalIndex) {
                    ForEach(0..<intervals.count, id: \.self) { i in
                        Text(intervals[i].0).tag(i)
                    }
                }
                .onChange(of: updateIntervalIndex) { newValue in
                    PreferencesManager.shared.updateInterval = intervals[newValue].1
                }

                Picker(L("setting_language"), selection: $selectedLanguageIndex) {
                    ForEach(0..<languages.count, id: \.self) { i in
                        Text(languages[i].displayName).tag(i)
                    }
                }
                .onChange(of: selectedLanguageIndex) { newValue in
                    LocalizationManager.shared.setLanguage(languages[newValue])
                }
            } header: {
                Label(L("setting_update_interval"), systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(L("setting_show_in_dock"), isOn: $showInDock)
                    .onChange(of: showInDock) { newValue in
                        PreferencesManager.shared.showInDock = newValue
                        updateDockVisibility(newValue)
                    }

                Toggle(L("setting_show_in_menubar"), isOn: $showInMenuBar)
                    .onChange(of: showInMenuBar) { newValue in
                        PreferencesManager.shared.showInMenuBar = newValue
                    }

                Toggle(L("setting_launch_at_login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        PreferencesManager.shared.launchAtLogin = newValue
                    }
            } header: {
                Label(L("setting_show_in_dock"), systemImage: "macwindow")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(L("setting_icloud_sync_enabled"), isOn: $iCloudSyncEnabled)
                    .onChange(of: iCloudSyncEnabled) { newValue in
                        PreferencesManager.shared.iCloudSyncEnabled = newValue
                    }

                Button(action: { iCloudSyncManager.shared.openFolderInFinder() }) {
                    HStack {
                        Text(L("button_open_folder"))
                        Spacer()
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Label("iCloud", systemImage: "icloud")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func updateDockVisibility(_ show: Bool) {
        if show {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Scholars Settings Tab
struct ScholarsSettingsTab: View {
    @State private var scholars: [Scholar] = PreferencesManager.shared.scholars
    @State private var selectedId: String?
    @State private var showAddSheet = false
    @State private var addInput = ""
    @State private var addError: String?
    @State private var isUpdating = false
    @State private var hoveredId: String?

    var body: some View {
        VStack(spacing: 0) {
            if scholars.isEmpty {
                // Empty state
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(.blue.opacity(0.08))
                            .frame(width: 64, height: 64)
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.blue.opacity(0.6))
                    }

                    VStack(spacing: 4) {
                        Text(L("add_scholar_title"))
                            .font(.system(size: 14, weight: .medium))
                        Text(L("add_scholar_message"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                    }

                    Button(action: { showAddSheet = true }) {
                        Label(L("button_add"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Scholar cards
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(scholars.enumerated()), id: \.element.id) { index, scholar in
                            ScholarCard(
                                scholar: scholar,
                                isSelected: selectedId == scholar.id,
                                isHovered: hoveredId == scholar.id,
                                index: index,
                                total: scholars.count
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedId = selectedId == scholar.id ? nil : scholar.id
                                }
                            }
                            .onHover { isHovered in
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    hoveredId = isHovered ? scholar.id : nil
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            // Bottom toolbar
            HStack(spacing: 6) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .frame(width: 28, height: 22)
                .help(L("button_add"))

                Button(action: removeSelected) {
                    Image(systemName: "minus")
                        .font(.system(size: 12))
                }
                .frame(width: 28, height: 22)
                .disabled(selectedId == nil)
                .help(L("button_remove"))

                Divider()
                    .frame(height: 16)

                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(width: 28, height: 22)
                .disabled(selectedId == nil || isFirstSelected)

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(width: 28, height: 22)
                .disabled(selectedId == nil || isLastSelected)

                Spacer()

                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("syncing"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: updateScholars) {
                    Label(L("button_update"), systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .disabled(scholars.isEmpty || isUpdating)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showAddSheet) {
            AddScholarSheet(
                input: $addInput,
                error: $addError,
                onAdd: { performAdd() },
                onCancel: {
                    addInput = ""
                    addError = nil
                    showAddSheet = false
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .scholarsDataUpdated)) { _ in
            scholars = PreferencesManager.shared.scholars
        }
    }

    private var isFirstSelected: Bool {
        guard let id = selectedId,
              let idx = scholars.firstIndex(where: { $0.id == id }) else { return true }
        return idx == 0
    }

    private var isLastSelected: Bool {
        guard let id = selectedId,
              let idx = scholars.firstIndex(where: { $0.id == id }) else { return true }
        return idx == scholars.count - 1
    }

    private func removeSelected() {
        guard let id = selectedId else { return }
        PreferencesManager.shared.removeScholar(withId: id)
        selectedId = nil
        scholars = PreferencesManager.shared.scholars
        NotificationCenter.default.post(name: .scholarsDataUpdated, object: nil)
    }

    private func moveUp() {
        guard let id = selectedId,
              let idx = scholars.firstIndex(where: { $0.id == id }),
              idx > 0 else { return }
        var updated = scholars
        updated.swapAt(idx, idx - 1)
        PreferencesManager.shared.scholars = updated
        scholars = updated
        NotificationCenter.default.post(name: .scholarsDataUpdated, object: nil)
    }

    private func moveDown() {
        guard let id = selectedId,
              let idx = scholars.firstIndex(where: { $0.id == id }),
              idx < scholars.count - 1 else { return }
        var updated = scholars
        updated.swapAt(idx, idx + 1)
        PreferencesManager.shared.scholars = updated
        scholars = updated
        NotificationCenter.default.post(name: .scholarsDataUpdated, object: nil)
    }

    private func performAdd() {
        let text = addInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            addError = L("error_invalid_scholar_id_message")
            return
        }
        guard let scholarId = GoogleScholarService.extractScholarId(from: text) else {
            addError = L("error_invalid_scholar_id_message")
            return
        }
        if scholars.contains(where: { $0.id == scholarId }) {
            addError = L("error_scholar_exists_message")
            return
        }

        let newScholar = Scholar(id: scholarId)
        PreferencesManager.shared.addScholar(newScholar)
        scholars = PreferencesManager.shared.scholars
        NotificationCenter.default.post(name: .scholarsDataUpdated, object: nil)

        addInput = ""
        addError = nil
        showAddSheet = false

        GoogleScholarService().fetchScholarInfo(for: scholarId) { result in
            DispatchQueue.main.async {
                if case .success(let info) = result {
                    PreferencesManager.shared.updateScholar(withId: scholarId, name: info.name, citations: info.citations)
                    scholars = PreferencesManager.shared.scholars
                    NotificationCenter.default.post(name: .scholarsDataUpdated, object: nil)
                }
            }
        }
    }

    private func updateScholars() {
        isUpdating = true
        let service = GoogleScholarService()
        let group = DispatchGroup()

        for scholar in scholars {
            group.enter()
            service.fetchScholarInfo(for: scholar.id) { result in
                DispatchQueue.main.async {
                    if case .success(let info) = result {
                        PreferencesManager.shared.updateScholar(withId: scholar.id, name: info.name, citations: info.citations)
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            isUpdating = false
            scholars = PreferencesManager.shared.scholars
            NotificationCenter.default.post(name: .scholarsDataUpdated, object: nil)
        }
    }
}

// MARK: - Scholar Card
struct ScholarCard: View {
    let scholar: Scholar
    let isSelected: Bool
    let isHovered: Bool
    let index: Int
    let total: Int

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Text(initials)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(avatarColor)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(scholar.name.isEmpty ? "Scholar \(scholar.id.prefix(8))" : scholar.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(scholar.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    if let date = scholar.lastUpdated {
                        freshnessIndicator(date)
                    }
                }
            }

            Spacer()

            // Citation count
            if let citations = scholar.citations {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(citations.formatted())")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(L("total_citations"))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("-")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.quaternary)
            }

            // Reorder indicator
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.blue.opacity(0.4) : .clear, lineWidth: 1.5)
        )
    }

    private var cardBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.blue.opacity(0.06))
        } else if isHovered {
            return AnyShapeStyle(Color.primary.opacity(0.03))
        } else {
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var initials: String {
        let name = scholar.name
        if name.isEmpty { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .teal, .orange, .green, .pink]
        return colors[index % colors.count]
    }

    private func freshnessIndicator(_ date: Date) -> some View {
        let hours = abs(date.timeIntervalSinceNow) / 3600
        let color: Color = hours < 24 ? .green : hours < 72 ? .orange : .red
        let label = formatRelative(date)

        return HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func formatRelative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Add Scholar Sheet
struct AddScholarSheet: View {
    @Binding var input: String
    @Binding var error: String?
    var onAdd: () -> Void
    var onCancel: () -> Void
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("add_scholar_title"))
                        .font(.headline)
                    Text(L("add_scholar_message"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField(L("scholar_id_placeholder"), text: $input)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .focused($isInputFocused)
                        .onSubmit { onAdd() }

                    Button("Paste") {
                        if let pasted = NSPasteboard.general.string(forType: .string) {
                            input = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            error = nil
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Text("e.g. MeaDj20AAAAJ or https://scholar.google.com/citations?user=MeaDj20AAAAJ")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                if let error = error {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(error)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button(L("button_cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(L("button_add"), action: onAdd)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }
}

// MARK: - Data Settings Tab
struct DataSettingsTab: View {
    @State private var iCloudDriveEnabled: Bool = PreferencesManager.shared.iCloudDriveFolderEnabled
    @State private var syncStatus: String = ""
    @State private var isSyncing = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        Form {
            Section {
                Toggle(L("show_in_icloud_drive"), isOn: $iCloudDriveEnabled)
                    .onChange(of: iCloudDriveEnabled) { newValue in
                        PreferencesManager.shared.iCloudDriveFolderEnabled = newValue
                        if newValue {
                            try? iCloudSyncManager.shared.createiCloudFolder()
                        }
                    }

                HStack(spacing: 12) {
                    Button(action: performSync) {
                        Label(L("sync_now"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isSyncing)

                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if !syncStatus.isEmpty {
                        Text(syncStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } header: {
                Label(L("icloud_sync"), systemImage: "icloud")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(action: importData) {
                    HStack {
                        Label(L("manual_import_file"), systemImage: "square.and.arrow.down")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.quaternary)
                    }
                }
                .buttonStyle(.plain)

                Button(action: exportData) {
                    HStack {
                        Label(L("export_to_device"), systemImage: "square.and.arrow.up")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.quaternary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Label(L("data_management"), systemImage: "externaldrive")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshSyncStatus() }
        .alert(alertTitle, isPresented: $showAlert) {
            Button(L("button_ok"), role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func refreshSyncStatus() {
        DispatchQueue.global(qos: .utility).async {
            let status = iCloudSyncManager.shared.getSyncStatus()
            DispatchQueue.main.async { syncStatus = status }
        }
    }

    private func performSync() {
        if !PreferencesManager.shared.iCloudDriveFolderEnabled {
            PreferencesManager.shared.iCloudDriveFolderEnabled = true
            iCloudDriveEnabled = true
            try? iCloudSyncManager.shared.createiCloudFolder()
        }

        isSyncing = true
        syncStatus = L("syncing")

        iCloudSyncManager.shared.exportUsingCloudKit { result in
            DispatchQueue.main.async {
                isSyncing = false
                switch result {
                case .success:
                    refreshSyncStatus()
                    alertTitle = L("sync_success_title")
                    alertMessage = L("sync_export_success_message")
                case .failure(let error):
                    syncStatus = L("sync_failed")
                    alertTitle = L("sync_failed_title")
                    alertMessage = error.localizedDescription
                }
                showAlert = true
            }
        }
    }

    private func importData() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.message = L("import_file_panel_message")

        openPanel.begin { response in
            guard response == .OK, let url = openPanel.urls.first else { return }
            do {
                let data = try Data(contentsOf: url)
                let result = try DataManager.shared.importFromiOSData(jsonData: data)
                DispatchQueue.main.async {
                    alertTitle = L("import_success_title")
                    alertMessage = L("import_success_message", result.importedScholars, result.importedHistory)
                    showAlert = true
                    NotificationCenter.default.post(name: .scholarsDataUpdated, object: nil)
                }
            } catch {
                DispatchQueue.main.async {
                    alertTitle = L("import_failed_title")
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }

    private func exportData() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json, .commaSeparatedText]
        savePanel.nameFieldStringValue = "CiteTrack_Export_\(Int(Date().timeIntervalSince1970)).json"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            let format: ExportFormat = url.pathExtension.lowercased() == "csv" ? .csv : .json

            CitationHistoryManager.shared.exportAllHistory(format: format) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let data):
                        do {
                            try data.write(to: url)
                            alertTitle = L("export_successful")
                            alertMessage = L("export_successful_message", url.lastPathComponent, data.count)
                        } catch {
                            alertTitle = L("export_failed")
                            alertMessage = error.localizedDescription
                        }
                    case .failure(let error):
                        alertTitle = L("export_failed")
                        alertMessage = error.localizedDescription
                    }
                    showAlert = true
                }
            }
        }
    }
}
