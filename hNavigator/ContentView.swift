import SwiftUI
import AppKit

public enum ActiveModal: String, Identifiable {
    case help, about, viewer, editor, copy, move, mkdir, delete, search, compareDirs, diskSpace, checksums, rename, zip, fileConflict, quitConfirmation, connectServer, renamePanel, error, progress
    public var id: String { rawValue }
}

public struct ContentView: View {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var tooltipState = TooltipState()

    // Panel States — each has its own persistence key
    @StateObject private var leftPanel  = PanelState(initialPath: NSHomeDirectory(), key: "leftPanel")
    @StateObject private var rightPanel = PanelState(initialPath: NSHomeDirectory(), key: "rightPanel")
    @State private var activePanelIndex = 0 // 0 = Left, 1 = Right

    // Panel renaming state
    @State private var panelToRename: PanelState? = nil
    @State private var panelRenameText = ""

    // Modal state management
    @State private var activeModal: ActiveModal? = nil
    @State private var modalFilePath = ""
    @State private var copyMoveSource = ""
    @State private var copyMoveDestination = ""
    @State private var globalErrorMessage = ""

    // Operation progress
    @State private var isOperationInProgress = false
    @State private var operationMessage = ""

    // ZIP dialog
    @State private var zipName = ""
    @State private var renameText = ""

    @FocusState private var conflictFocusedField: ConflictFocusField?
    
    enum ConflictFocusField: Hashable {
        case overwrite, skip, overwriteAll, skipAll, cancel
    }

    // Custom Popover Menus State
    @State private var showGoMenu = false
    @State private var showToolsMenu = false
    @State private var showThemeMenu = false

    private var activePanel: PanelState {
        activePanelIndex == 0 ? leftPanel : rightPanel
    }

    private var inactivePanel: PanelState {
        activePanelIndex == 0 ? rightPanel : leftPanel
    }

    private var mountedVolumes: [URL] {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
    }

    // MARK: - File operation callbacks & Queue processor
    @State private var filesToProcess: [VFSNode] = []
    @State private var conflictDestination: String = ""
    @State private var conflictIsMove: Bool = false
    @State private var overwriteAll = false
    @State private var skipAll = false
    @State private var currentProcessingNode: VFSNode? = nil
    
    // Copy Progress State
    @State private var totalBytesToProcess: Int64 = 0
    @State private var totalBytesProcessed: Int64 = 0
    @State private var operationStartTime: Date? = nil
    @State private var timeRemainingString: String = ""
    @State private var currentCopyFileName: String = ""
    @State private var currentCopyFileProgress: Double = 0.0
    @State private var isOperationCancelled: Bool = false
    @State private var currentOperationTask: Task<Void, Never>? = nil
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func startCopyMoveQueue(nodes: [VFSNode], dest: String, isMove: Bool) {
        activeModal = .progress
        isOperationInProgress = true
        isOperationCancelled = false
        totalBytesToProcess = 0
        totalBytesProcessed = 0
        operationStartTime = Date()
        timeRemainingString = ""
        currentCopyFileProgress = 0.0
        
        self.filesToProcess = nodes
        self.conflictDestination = dest
        self.conflictIsMove = isMove
        self.overwriteAll = false
        self.skipAll = false
        self.currentProcessingNode = nil
        
        operationMessage = "Calculating size..."
        
        Task {
            var totalBytes: Int64 = 0
            if let _ = activePanel.provider as? LocalVFSProvider {
                let fm = FileManager.default
                for node in nodes {
                    if node.isDirectory {
                        if let enumerator = fm.enumerator(atPath: node.path) {
                            while let item = enumerator.nextObject() as? String {
                                let path = (node.path as NSString).appendingPathComponent(item)
                                if let attrs = try? fm.attributesOfItem(atPath: path), let s = attrs[.size] as? Int64 {
                                    totalBytes += s
                                }
                            }
                        }
                    } else {
                        totalBytes += node.size
                    }
                }
            } else {
                for node in nodes {
                    totalBytes += node.size
                }
            }
            
            await MainActor.run {
                self.totalBytesToProcess = totalBytes
                self.operationMessage = ""
                self.processNextFile()
            }
        }
    }

    private func appendPathComponent(_ path: String, _ component: String) -> String {
        return path.hasSuffix("/") ? path + component : path + "/" + component
    }

    private func deleteLastPathComponent(_ path: String) -> String {
        guard let lastSlashIndex = path.lastIndex(of: "/") else { return path }
        // Ensure we don't truncate sftp:// down to sftp:/
        if path.hasPrefix("sftp://") || path.hasPrefix("ftp://") || path.hasPrefix("webdav://") || path.hasPrefix("smb://") || path.hasPrefix("archive://") {
            let prefixIndex = path.firstIndex(of: ":")!
            let afterScheme = path.index(prefixIndex, offsetBy: 3)
            if lastSlashIndex < afterScheme {
                return path // don't truncate the scheme
            }
        }
        if lastSlashIndex == path.startIndex { return "/" }
        return String(path[..<lastSlashIndex])
    }

    private func processNextFile() {
        if isOperationCancelled {
            filesToProcess.removeAll()
            isOperationInProgress = false
            activeModal = nil
            return
        }
        
        guard !filesToProcess.isEmpty else {
            isOperationInProgress = false
            activeModal = nil
            Task {
                await leftPanel.loadDirectory()
                await rightPanel.loadDirectory()
            }
            return
        }
        
        let node = filesToProcess.removeFirst()
        currentProcessingNode = node
        currentCopyFileName = node.name
        currentCopyFileProgress = 0.0
        let destPath = appendPathComponent(conflictDestination, node.name)
        
        Task {
            let provider = inactivePanel.provider
            let fileExists = (try? await provider.exists(at: destPath)) ?? false
            
            await MainActor.run {
                if fileExists {
                    if overwriteAll {
                        performCopyMoveAction(node: node, destPath: destPath, overwrite: true)
                    } else if skipAll {
                        processNextFile()
                    } else {
                        activeModal = .fileConflict
                    }
                } else {
                    performCopyMoveAction(node: node, destPath: destPath, overwrite: false)
                }
            }
        }
    }

    private func updateTimeRemaining() {
        guard let start = operationStartTime, totalBytesProcessed > 0, totalBytesToProcess > 0 else {
            timeRemainingString = ""
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 1.0 else { return } // Wait a bit for stable speed
        
        let bytesPerSecond = Double(totalBytesProcessed) / elapsed
        let remainingBytes = Double(totalBytesToProcess - totalBytesProcessed)
        let remainingSeconds = remainingBytes / bytesPerSecond
        
        if remainingSeconds.isFinite && remainingSeconds >= 0 {
            let mins = Int(remainingSeconds) / 60
            let secs = Int(remainingSeconds) % 60
            timeRemainingString = String(format: "%dm %02ds", mins, secs)
        } else {
            timeRemainingString = ""
        }
    }

    private func performCopyMoveAction(node: VFSNode, destPath: String, overwrite: Bool) {
        currentOperationTask = Task {
            do {
                if overwrite {
                    try? await inactivePanel.provider.deleteItem(at: destPath)
                }
                
                if conflictIsMove {
                    try await activePanel.provider.moveItem(from: node.path, to: destPath)
                    await MainActor.run {
                        self.totalBytesProcessed += node.size
                    }
                } else {
                    var fileBytesAdded: Int64 = 0
                    try await activePanel.provider.copyItem(from: node.path, to: destPath) { progress, deltaBytes in
                        DispatchQueue.main.async {
                            self.currentCopyFileProgress = progress
                            self.totalBytesProcessed += deltaBytes
                            fileBytesAdded += deltaBytes
                            self.updateTimeRemaining()
                        }
                    }
                    await MainActor.run {
                        if fileBytesAdded == 0 && node.size > 0 {
                            self.totalBytesProcessed += node.size
                        }
                    }
                }
                
                await MainActor.run {
                    processNextFile()
                }
            } catch is CancellationError {
                // Clean up partially copied file
                try? await inactivePanel.provider.deleteItem(at: destPath)
            } catch {
                await MainActor.run {
                    showError("Operation failed for \(node.name):\n\(error.localizedDescription)")
                }
            }
        }
    }
    
    @MainActor
    private func showError(_ message: String) {
        isOperationInProgress = false
        globalErrorMessage = message
        activeModal = .error
    }

    private func handleCopy(dest: String) {
        let nodes = activePanel.selectedNodes.filter { $0.name != ".." }
        guard !nodes.isEmpty else { activeModal = nil; return }
        startCopyMoveQueue(nodes: nodes, dest: dest, isMove: false)
    }

    private func handleMove(dest: String) {
        let nodes = activePanel.selectedNodes.filter { $0.name != ".." }
        guard !nodes.isEmpty else { activeModal = nil; return }
        startCopyMoveQueue(nodes: nodes, dest: dest, isMove: true)
    }

    private func handleMkDir(name: String) {
        guard !name.isEmpty else { activeModal = nil; return }
        activeModal = nil
        isOperationInProgress = true
        operationMessage = "Creating directory \(name)..."
        let newPath = appendPathComponent(activePanel.currentPath, name)
        Task {
            do {
                try await activePanel.provider.createDirectory(at: newPath)
                await activePanel.loadDirectory()
                isOperationInProgress = false
            } catch {
                showError("Create directory failed:\n\(error.localizedDescription)")
            }
        }
    }

    private func handleDelete() {
        let nodes = activePanel.selectedNodes.filter { $0.name != ".." }
        guard !nodes.isEmpty else { activeModal = nil; return }
        
        activeModal = nil
        isOperationInProgress = true
        operationMessage = "Deleting \(nodes.count) item(s)..."
        
        Task {
            do {
                for node in nodes {
                    try await activePanel.provider.deleteItem(at: node.path)
                }
                await leftPanel.loadDirectory()
                await rightPanel.loadDirectory()
                isOperationInProgress = false
            } catch {
                await MainActor.run {
                    showError("Delete failed:\n\(error.localizedDescription)")
                }
            }
        }
    }

    private func handleCreateZip() {
        let name = zipName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        activeModal = nil
        zipName = ""
        isOperationInProgress = true
        operationMessage = "Creating ZIP..."
        Task {
            do {
                try await activePanel.createZip(named: name)
                await activePanel.loadDirectory()
                isOperationInProgress = false
            } catch {
                showError("ZIP creation failed:\n\(error.localizedDescription)")
            }
        }
    }

    private func openInTerminal(_ path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", path]
        try? process.run()
    }
    
    private func openInFinder(_ path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [path]
        try? process.run()
    }

    private func nextTheme(after current: AppTheme) -> AppTheme {
        let all = AppTheme.allCases
        let idx = all.firstIndex(of: current) ?? 0
        return all[(idx + 1) % all.count]
    }



    private var detectedClouds: [CloudStorageFolder] {
        var folders: [CloudStorageFolder] = []
        let fm = FileManager.default
        let home = NSHomeDirectory()
        
        // 1. iCloud Drive
        let icloudPath = (home as NSString).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: icloudPath) {
            folders.append(CloudStorageFolder(name: "iCloud Drive", path: icloudPath, systemImage: "icloud.fill"))
        }
        
        // 2. Scan ~/Library/CloudStorage
        let cloudStoragePath = (home as NSString).appendingPathComponent("Library/CloudStorage")
        if let contents = try? fm.contentsOfDirectory(atPath: cloudStoragePath) {
            for name in contents {
                let fullPath = (cloudStoragePath as NSString).appendingPathComponent(name)
                
                // Map names to nice display names and icons
                let lower = name.lowercased()
                var displayName = name
                var icon = "cloud.fill"
                
                if lower.contains("googledrive") || lower.contains("google drive") {
                    displayName = "Google Drive"
                    icon = "arrow.triangle.2.circlepath.doc.on.clipboard"
                } else if lower.contains("dropbox") {
                    displayName = "Dropbox"
                    icon = "archivebox.fill"
                } else if lower.contains("onedrive") {
                    displayName = "OneDrive"
                    icon = "icloud.fill"
                } else if lower.contains("box") {
                    displayName = "Box"
                    icon = "square.grid.3x1.folder.fill.badge.plus"
                }
                
                folders.append(CloudStorageFolder(name: displayName, path: fullPath, systemImage: icon))
            }
        }
        
        return folders
    }

    private var goMenuHeight: CGFloat {
        let count = 6 + mountedVolumes.count + detectedClouds.count
        let height = CGFloat(count * 28 + 16)
        return min(height, 400.0)
    }

    @ViewBuilder
    private func goMenuContent(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverMenuItem(title: "Home", icon: "house.fill", theme: theme) {
                showGoMenu = false
                Task { await activePanel.navigateTo(path: NSHomeDirectory()) }
            }
            PopoverMenuItem(title: "Desktop", icon: "desktopcomputer", theme: theme) {
                showGoMenu = false
                Task { await activePanel.navigateTo(path: (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")) }
            }
            PopoverMenuItem(title: "Documents", icon: "doc.text.fill", theme: theme) {
                showGoMenu = false
                Task { await activePanel.navigateTo(path: (NSHomeDirectory() as NSString).appendingPathComponent("Documents")) }
            }
            PopoverMenuItem(title: "Downloads", icon: "arrow.down.circle.fill", theme: theme) {
                showGoMenu = false
                Task { await activePanel.navigateTo(path: (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")) }
            }
            PopoverMenuItem(title: "Applications", icon: "app.badge.fill", theme: theme) {
                showGoMenu = false
                Task { await activePanel.navigateTo(path: "/Applications") }
            }
            PopoverMenuItem(title: "Root (/)", icon: "folder.fill", theme: theme) {
                showGoMenu = false
                Task { await activePanel.navigateTo(path: "/") }
            }
            
            let vols = mountedVolumes
            let clouds = detectedClouds
            
            if !vols.isEmpty || !clouds.isEmpty {
                Divider().padding(.vertical, 4)
            }
            
            ForEach(vols, id: \.self) { url in
                PopoverMenuItem(title: url.lastPathComponent, icon: "externaldrive.fill", theme: theme) {
                    showGoMenu = false
                    Task { await activePanel.navigateTo(path: url.path) }
                }
            }
            
            if !clouds.isEmpty {
                Divider().padding(.vertical, 4)
                ForEach(clouds) { cloud in
                    PopoverMenuItem(title: cloud.name, icon: cloud.systemImage, theme: theme) {
                        showGoMenu = false
                        Task { await activePanel.navigateTo(path: cloud.path) }
                    }
                }
            }
        }
        .padding(4)
    }

    @ViewBuilder
    private func toolsMenuContent(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverMenuItem(title: "Create ZIP Archive...", icon: "archivebox.fill", theme: theme) {
                showToolsMenu = false
                activeModal = .zip
            }
            PopoverMenuItem(title: "Compare Directories", icon: "arrow.2.squarepath", theme: theme) {
                showToolsMenu = false
                activeModal = .compareDirs
            }
            PopoverMenuItem(title: "Disk Space Analyzer", icon: "chart.pie.fill", theme: theme) {
                showToolsMenu = false
                activeModal = .diskSpace
            }
            PopoverMenuItem(title: "Checksum Hash Calculator", icon: "number.square.fill", theme: theme) {
                showToolsMenu = false
                if let node = activePanel.currentSelectedNode {
                    modalFilePath = node.path
                    activeModal = .checksums
                }
            }
            PopoverMenuItem(title: "Connect to Server...", icon: "network", theme: theme) {
                showToolsMenu = false
                activeModal = .connectServer
            }
            PopoverMenuItem(title: "Rename Active Panel...", icon: "pencil", theme: theme) {
                showToolsMenu = false
                panelRenameText = activePanel.panelTitle
                panelToRename = activePanel
                activeModal = .renamePanel
            }
            
            Divider().padding(.vertical, 4)
            
            PopoverMenuItem(title: "Open in Terminal", icon: "terminal.fill", theme: theme) {
                showToolsMenu = false
                openInTerminal(activePanel.currentPath)
            }
            PopoverMenuItem(title: "Open in Finder", icon: "finder", theme: theme) {
                showToolsMenu = false
                openInFinder(activePanel.currentPath)
            }
        }
        .padding(4)
    }

    @ViewBuilder
    private func themeMenuContent(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AppTheme.allCases) { t in
                PopoverMenuItem(
                    title: t.rawValue,
                    icon: theme == t ? "checkmark" : nil,
                    theme: theme
                ) {
                    showThemeMenu = false
                    themeManager.selectTheme(t)
                }
            }
        }
        .padding(4)
    }

    // Custom Top Bar (Toolbar)
    private var topBar: some View {
        let theme = themeManager.currentTheme
        return HStack(spacing: 12) {
            HStack(spacing: theme == .humaniaq ? 8 : 6) {
                if theme == .humaniaq {
                    WaterLineDropLogo(lineColor: theme.textColor, dropColor: theme.glowColor)
                    Text("hNavigator")
                        .font(theme.font(size: 16, weight: .medium))
                        .foregroundColor(theme.topMenuBarTextColor)
                } else {
                    Image(systemName: "compass")
                        .font(.system(size: 16))
                        .foregroundColor(theme.glowColor)
                    Text("HNAVIGATOR")
                        .font(theme.font(size: 14, weight: .bold))
                        .foregroundColor(theme.topMenuBarTextColor)
                }
            }
            .padding(.leading, 12)
            
            Spacer()
            
            // About hNavigator Button
            Button(action: { activeModal = .about }) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                    Text("About hNavigator")
                }
                .font(theme.font(size: 12))
                .foregroundColor(theme.topMenuBarTextColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(theme.borderColor.opacity(0.25))
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .retroTooltip("Information about this application", theme: theme)
            
            // Go Menu Button
            Button(action: { showGoMenu.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill.badge.gearshape")
                    Text("Go")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(theme.font(size: 12))
                .foregroundColor(theme.topMenuBarTextColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(theme.borderColor.opacity(0.25))
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .retroTooltip("Quick directory navigation", theme: theme)
            .popover(isPresented: $showGoMenu, arrowEdge: .bottom) {
                ScrollView {
                    goMenuContent(theme: theme)
                }
                .frame(width: 200, height: goMenuHeight)
                .background(theme.panelBgColor)
                .environment(\.tooltipState, tooltipState)
            }
            
            // Tools Menu Button
            Button(action: { showToolsMenu.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                    Text("Tools")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(theme.font(size: 12))
                .foregroundColor(theme.topMenuBarTextColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(theme.borderColor.opacity(0.25))
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .retroTooltip("Utility commands & operations", theme: theme)
            .popover(isPresented: $showToolsMenu, arrowEdge: .bottom) {
                toolsMenuContent(theme: theme)
                    .frame(width: 220)
                    .background(theme.panelBgColor)
                    .environment(\.tooltipState, tooltipState)
            }
            
            // Theme Dropdown Menu Button
            Button(action: { showThemeMenu.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette.fill")
                    Text(theme.rawValue)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(theme.font(size: 12))
                .foregroundColor(theme.topMenuBarTextColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(theme.borderColor.opacity(0.25))
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .retroTooltip("Switch interface appearance", theme: theme)
            .popover(isPresented: $showThemeMenu, arrowEdge: .bottom) {
                themeMenuContent(theme: theme)
                    .frame(width: 160)
                    .background(theme.panelBgColor)
                    .environment(\.tooltipState, tooltipState)
            }
            
            // Help button
            Button(action: { activeModal = .help }) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(theme.topMenuBarTextColor)
            }
            .buttonStyle(PlainButtonStyle())
            .retroTooltip("Show help documentation (F1)", theme: theme)
            .padding(.trailing, 12)
        }
        .frame(height: 40)
        .background(theme.topMenuBarBgColor)
    }

    private var fKeyBar: some View {
        let theme = themeManager.currentTheme
        return HStack(spacing: 2) {
            ForEach(1...10, id: \.self) { num in
                fKeyButton(num: num, theme: theme)
            }
        }
        .frame(height: 28)
        .background(theme.topMenuBarBgColor)
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }
    
    @ViewBuilder
    private func fKeyButton(num: Int, theme: AppTheme) -> some View {
        let labels = [
            1: "Help",
            2: "Rename",
            3: "View",
            4: "Edit",
            5: "Copy",
            6: "Move",
            7: "MkDir",
            8: "Delete",
            9: "Theme",
            10: "Quit"
        ]
        
        let helpTexts = [
            1: "Show help documentation (F1)",
            2: "Rename selected file or folder (F2)",
            3: "View selected file internally (F3)",
            4: "Edit selected file internally (F4)",
            5: "Copy selected files (F5)",
            6: "Move selected files (F6)",
            7: "Create new folder (Make Directory) (F7)",
            8: "Delete selected files (F8)",
            9: "Cycle interface color theme (F9)",
            10: "Quit application (F10)"
        ]
        
        let label = labels[num] ?? ""
        let helpText = helpTexts[num] ?? ""
        
        let btn = Button(action: {
            if activeModal == nil {
                triggerFunctionKey("F\(num)")
            }
        }) {
            HStack(spacing: 2) {
                Text(num == 10 ? "fn+F10" : "fn+F\(num)")
                    .font(theme.monoFont(size: 10, weight: .bold))
                    .foregroundColor(theme.fKeyLabelColor)
                Text(label)
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundColor(theme.fKeyActionColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.panelBgColor.opacity(0.4))
            .border(theme.borderColor, width: 0.5)
        }
        .buttonStyle(PlainButtonStyle())
        .retroTooltip(helpText, theme: theme, edge: .top)

        switch num {
        case 1: btn.keyboardShortcut("1", modifiers: [.command])
        case 2: btn.keyboardShortcut("2", modifiers: [.command])
        case 3: btn.keyboardShortcut("3", modifiers: [.command])
        case 4: btn.keyboardShortcut("4", modifiers: [.command])
        case 5: btn.keyboardShortcut("5", modifiers: [.command])
        case 6: btn.keyboardShortcut("6", modifiers: [.command])
        case 7: btn.keyboardShortcut("7", modifiers: [.command])
        case 8: btn.keyboardShortcut("8", modifiers: [.command])
        case 9: btn.keyboardShortcut("9", modifiers: [.command])
        case 10: btn.keyboardShortcut("0", modifiers: [.command])
        default: btn
        }
    }

    @ViewBuilder
    private func operationProgressBanner(theme: AppTheme) -> some View {
        HStack {
            ProgressView()
                .controlSize(.small)
                .padding(.trailing, 8)
            Text(operationMessage)
                .font(theme.font(size: 12))
                .foregroundColor(theme.textColor)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.panelBgColor)
        .border(theme.borderColor, width: 1)
    }

    @ViewBuilder
    private func renameDialog(theme: AppTheme) -> some View {
        VStack(spacing: 20) {
            Text("Rename Item")
                .font(theme.font(size: 16, weight: .bold))
                .foregroundColor(theme.textColor)
            
            TextField("New name", text: $renameText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(theme.monoFont(size: 13))
                .foregroundColor(theme.textColor)
                .padding(8)
                .background(theme.borderColor.opacity(0.15))
                .cornerRadius(6)
                .frame(width: 260)
                .onSubmit {
                    handleRename()
                }
            
            HStack(spacing: 12) {
                Button("Cancel") { activeModal = nil; renameText = "" }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(theme.subtleTextColor)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(theme.borderColor.opacity(0.2))
                    .cornerRadius(6)
                    .keyboardShortcut(.escape, modifiers: [])
                
                Button("Rename") {
                    handleRename()
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(theme.glowColor.opacity(0.7))
                .cornerRadius(6)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .background(theme.panelBgColor)
        .cornerRadius(14)
        .shadow(color: theme.shadowColor, radius: 24, y: 8)
    }

    private func handleRename() {
        if let node = activePanel.currentSelectedNode {
            let oldPath = node.path
            let basePath = deleteLastPathComponent(oldPath)
            let newPath = appendPathComponent(basePath, renameText)
            Task {
                do {
                    try await activePanel.provider.moveItem(from: oldPath, to: newPath)
                    await leftPanel.loadDirectory()
                    await rightPanel.loadDirectory()
                    activeModal = nil
                    renameText = ""
                } catch {
                    await MainActor.run {
                        showError("Rename error:\n\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renamePanelDialog(theme: AppTheme) -> some View {
        VStack(spacing: 20) {
            Text("Rename Panel")
                .font(theme.font(size: 16, weight: .bold))
                .foregroundColor(theme.textColor)
            
            TextField("Panel Name", text: $panelRenameText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(theme.font(size: 13))
                .foregroundColor(theme.textColor)
                .padding(8)
                .background(theme.borderColor.opacity(0.15))
                .cornerRadius(6)
                .frame(width: 260)
                .onSubmit {
                    handleRenamePanel()
                }
            
            HStack(spacing: 12) {
                Button("Cancel") { activeModal = nil }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(theme.subtleTextColor)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(theme.borderColor.opacity(0.2))
                    .cornerRadius(6)
                    .keyboardShortcut(.escape, modifiers: [])
                
                Button("Save") {
                    handleRenamePanel()
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.black)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(theme.glowColor)
                .cornerRadius(6)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .background(theme.panelBgColor)
        .cornerRadius(14)
        .shadow(color: theme.shadowColor, radius: 24, y: 8)
    }

    private func handleRenamePanel() {
        if let panel = panelToRename {
            panel.panelTitle = panelRenameText
        }
        activeModal = nil
    }

    @ViewBuilder
    private func zipDialog(theme: AppTheme) -> some View {
        VStack(spacing: 20) {
            Text("Create ZIP Archive")
                .font(theme.font(size: 16, weight: .bold))
                .foregroundColor(theme.textColor)

            let selected = activePanel.selectedNodes.filter { $0.name != ".." }
            Text("Will archive \(selected.count) item(s) from\n\(activePanel.currentPath)")
                .font(theme.font(size: 11))
                .foregroundColor(theme.subtleTextColor)
                .multilineTextAlignment(.center)

            TextField("Archive name", text: $zipName)
                .textFieldStyle(PlainTextFieldStyle())
                .font(theme.monoFont(size: 13))
                .foregroundColor(theme.textColor)
                .padding(8)
                .background(theme.borderColor.opacity(0.15))
                .cornerRadius(6)
                .frame(width: 260)
                .onSubmit {
                    if !zipName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        handleCreateZip()
                    }
                }

            HStack(spacing: 12) {
                Button("Cancel") { activeModal = nil; zipName = "" }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(theme.subtleTextColor)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(theme.borderColor.opacity(0.2))
                    .cornerRadius(6)
                    .keyboardShortcut(.escape, modifiers: [])

                Button("Create ZIP") { handleCreateZip() }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(theme.glowColor.opacity(0.7))
                    .cornerRadius(6)
                    .disabled(zipName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .background(theme.panelBgColor)
        .cornerRadius(14)
        .shadow(color: theme.shadowColor, radius: 24, y: 8)
    }

    private func cycleConflictFocus(forward: Bool) {
        let fields: [ConflictFocusField] = [.overwrite, .skip, .overwriteAll, .skipAll, .cancel]
        guard let current = conflictFocusedField else {
            conflictFocusedField = .overwrite
            return
        }
        guard let idx = fields.firstIndex(of: current) else { return }
        if forward {
            conflictFocusedField = fields[(idx + 1) % fields.count]
        } else {
            conflictFocusedField = fields[(idx - 1 + fields.count) % fields.count]
        }
    }
    
    private func triggerConflictAction() {
        guard let current = conflictFocusedField else { return }
        activeModal = nil
        switch current {
        case .overwrite:
            if let node = currentProcessingNode {
                let destPath = (conflictDestination as NSString).appendingPathComponent(node.name)
                performCopyMoveAction(node: node, destPath: destPath, overwrite: true)
            }
        case .skip:
            processNextFile()
        case .overwriteAll:
            overwriteAll = true
            if let node = currentProcessingNode {
                let destPath = (conflictDestination as NSString).appendingPathComponent(node.name)
                performCopyMoveAction(node: node, destPath: destPath, overwrite: true)
            }
        case .skipAll:
            skipAll = true
            processNextFile()
        case .cancel:
            filesToProcess = []
            isOperationInProgress = false
            currentProcessingNode = nil
        }
    }

    @ViewBuilder
    private func conflictDialog(theme: AppTheme) -> some View {
        RetroBox(title: "File Conflict Resolution", theme: theme, isActive: true, doubleLine: true) {
            VStack(spacing: 12) {
                if let node = currentProcessingNode {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The destination file already exists:")
                            .font(theme.font(size: 11))
                            .foregroundColor(theme.textColor)
                        Text(node.name)
                            .font(theme.monoFont(size: 12, weight: .bold))
                            .foregroundColor(theme.glowColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(theme.borderColor.opacity(0.15))
                            .cornerRadius(4)
                        Text("Destination folder:\n\(conflictDestination)")
                            .font(theme.font(size: 10))
                            .foregroundColor(theme.subtleTextColor)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .frame(width: 320)
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button("Overwrite") {
                            activeModal = nil
                            if let node = currentProcessingNode {
                                let destPath = (conflictDestination as NSString).appendingPathComponent(node.name)
                                performCopyMoveAction(node: node, destPath: destPath, overwrite: true)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(conflictFocusedField == .overwrite ? .white : .black)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(conflictFocusedField == .overwrite ? theme.glowColor : Color.green)
                        .border(conflictFocusedField == .overwrite ? Color.white : Color.clear, width: 2)
                        .focusable()
                        .focused($conflictFocusedField, equals: .overwrite)
                        
                        Button("Skip") {
                            activeModal = nil
                            processNextFile()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(conflictFocusedField == .skip ? .white : .black)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(conflictFocusedField == .skip ? theme.glowColor : Color.gray)
                        .border(conflictFocusedField == .skip ? Color.white : Color.clear, width: 2)
                        .focusable()
                        .focused($conflictFocusedField, equals: .skip)
                    }
                    
                    HStack(spacing: 12) {
                        Button("Overwrite All") {
                            activeModal = nil
                            overwriteAll = true
                            if let node = currentProcessingNode {
                                let destPath = (conflictDestination as NSString).appendingPathComponent(node.name)
                                performCopyMoveAction(node: node, destPath: destPath, overwrite: true)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(conflictFocusedField == .overwriteAll ? .white : .black)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(conflictFocusedField == .overwriteAll ? theme.glowColor : Color.green)
                        .border(conflictFocusedField == .overwriteAll ? Color.white : Color.clear, width: 2)
                        .focusable()
                        .focused($conflictFocusedField, equals: .overwriteAll)
                        
                        Button("Skip All") {
                            activeModal = nil
                            skipAll = true
                            processNextFile()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(conflictFocusedField == .skipAll ? .white : .black)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(conflictFocusedField == .skipAll ? theme.glowColor : Color.gray)
                        .border(conflictFocusedField == .skipAll ? Color.white : Color.clear, width: 2)
                        .focusable()
                        .focused($conflictFocusedField, equals: .skipAll)
                    }
                    
                    Button("Cancel Operation") {
                        activeModal = nil
                        filesToProcess = []
                        isOperationInProgress = false
                        currentProcessingNode = nil
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(conflictFocusedField == .cancel ? .white : .red)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(conflictFocusedField == .cancel ? theme.glowColor : theme.borderColor.opacity(0.15))
                    .border(conflictFocusedField == .cancel ? Color.white : Color.clear, width: 2)
                    .focusable()
                    .focused($conflictFocusedField, equals: .cancel)
                }
            }
        }
        .frame(width: 380, height: 280)
        .onAppear {
            conflictFocusedField = .overwrite
        }
        .onKeyPress { press in
            if press.key == .tab {
                cycleConflictFocus(forward: true)
                return .handled
            } else if press.key == .leftArrow || press.key == .upArrow {
                cycleConflictFocus(forward: false)
                return .handled
            } else if press.key == .rightArrow || press.key == .downArrow {
                cycleConflictFocus(forward: true)
                return .handled
            } else if press.key == .return {
                triggerConflictAction()
                return .handled
            } else if press.key == .escape {
                activeModal = nil
                filesToProcess = []
                isOperationInProgress = false
                currentProcessingNode = nil
                return .handled
            }
            return .ignored
        }
    }

    @ViewBuilder
    private func modalView(for modal: ActiveModal, theme: AppTheme) -> some View {
        switch modal {
        case .about:
            RetroAboutDialog(theme: theme, onClose: { activeModal = nil })
        case .help:
            RetroHelpDialog(theme: theme, onClose: { activeModal = nil })
        case .viewer:
            RetroViewerModal(filePath: modalFilePath, provider: activePanel.provider, theme: theme, onClose: { activeModal = nil })
        case .editor:
            RetroEditorModal(filePath: modalFilePath, provider: activePanel.provider, theme: theme, onClose: { activeModal = nil }, onSave: { Task { await activePanel.loadDirectory() } })
        case .copy:
            RetroCopyMoveDialog(title: "Copy File(s)", sourcePath: copyMoveSource, destPath: copyMoveDestination, theme: theme, onCancel: { activeModal = nil }, onConfirm: { dest in handleCopy(dest: dest) })
        case .move:
            RetroCopyMoveDialog(title: "Move File(s)", sourcePath: copyMoveSource, destPath: copyMoveDestination, theme: theme, onCancel: { activeModal = nil }, onConfirm: { dest in handleMove(dest: dest) })
        case .mkdir:
            RetroMkDirDialog(theme: theme, onCancel: { activeModal = nil }, onConfirm: { name in handleMkDir(name: name) })
        case .delete:
            RetroDeleteDialog(fileName: modalFilePath, theme: theme, onCancel: { activeModal = nil }, onConfirm: { handleDelete() })
        case .search:
            RetroSearchDialog(rootPath: activePanel.currentPath, theme: theme, onCancel: { activeModal = nil }, onSelectFile: { path in activeModal = nil; Task { await activePanel.navigateTo(path: path) } })
        case .compareDirs:
            RetroCompareDirsDialog(leftFiles: leftPanel.files, rightFiles: rightPanel.files, theme: theme, onClose: { activeModal = nil })
        case .diskSpace:
            RetroDiskAnalysisDialog(currentPath: activePanel.currentPath, theme: theme, onClose: { activeModal = nil })
        case .checksums:
            RetroChecksumDialog(filePath: modalFilePath, theme: theme, onClose: { activeModal = nil })
        case .rename:
            renameDialog(theme: theme)
        case .zip:
            zipDialog(theme: theme)
        case .fileConflict:
            conflictDialog(theme: theme)
        case .quitConfirmation:
            RetroQuitConfirmationDialog(theme: theme, onCancel: { activeModal = nil }, onConfirm: { NSApplication.shared.terminate(nil) })
        case .connectServer:
            RetroConnectServerDialog(theme: theme, onCancel: { activeModal = nil }, onConnect: { url in
                activeModal = nil
                Task {
                    await activePanel.navigateTo(path: url)
                }
            })
        case .renamePanel:
            renamePanelDialog(theme: theme)
        case .error:
            RetroErrorDialog(message: globalErrorMessage, theme: theme, onDismiss: {
                activeModal = nil
                globalErrorMessage = ""
            })
        case .progress:
            RetroCopyProgressDialog(
                currentFileName: currentCopyFileName,
                fileProgress: currentCopyFileProgress,
                totalBytes: totalBytesToProcess,
                processedBytes: totalBytesProcessed,
                timeRemaining: timeRemainingString,
                theme: theme,
                onCancel: {
                    isOperationCancelled = true
                    currentOperationTask?.cancel()
                    activeModal = nil
                },
                onBackground: {
                    activeModal = nil
                }
            )
        }
    }

    private func triggerFunctionKey(_ key: String) {
        switch key {
        case "F1":
            activeModal = .help
        case "F2":
            if let node = activePanel.currentSelectedNode, node.name != ".." {
                renameText = node.name
                activeModal = .rename
            }
        case "F3":
            if let node = activePanel.currentSelectedNode, !node.isDirectory {
                let handled = activePanel.openFile(node)
                if !handled {
                    modalFilePath = node.path
                    activeModal = .viewer
                }
            }
        case "F4":
            if let node = activePanel.currentSelectedNode, !node.isDirectory {
                modalFilePath = node.path
                activeModal = .editor
            } else if let node = activePanel.currentSelectedNode, node.isDirectory {
                modalFilePath = appendPathComponent(node.path, "new_file.txt")
                activeModal = .editor
            }
        case "F5":
            let nodes = activePanel.selectedNodes.filter { $0.name != ".." }
            if !nodes.isEmpty {
                copyMoveSource = nodes.count == 1 ? nodes[0].path : "\(nodes.count) selected items"
                copyMoveDestination = inactivePanel.currentPath
                activeModal = .copy
            }
        case "F6":
            let nodes = activePanel.selectedNodes.filter { $0.name != ".." }
            if !nodes.isEmpty {
                copyMoveSource = nodes.count == 1 ? nodes[0].path : "\(nodes.count) selected items"
                copyMoveDestination = inactivePanel.currentPath
                activeModal = .move
            }
        case "F7":
            activeModal = .mkdir
        case "F8":
            let nodes = activePanel.selectedNodes.filter { $0.name != ".." }
            if !nodes.isEmpty {
                modalFilePath = nodes.count == 1 ? nodes[0].name : "\(nodes.count) item(s)"
                activeModal = .delete
            }
        case "F9":
            themeManager.selectTheme(nextTheme(after: themeManager.currentTheme))
        case "F10":
            activeModal = .quitConfirmation
        default:
            break
        }
    }

    private func setupKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags       = event.modifierFlags
            let isCmd       = flags.contains(.command)
            let isShift     = flags.contains(.shift)
            let isAlt       = flags.contains(.option)
            let isCtrl      = flags.contains(.control)
            let ch          = event.charactersIgnoringModifiers ?? ""

            // Always intercept Cmd+Q globally first to confirm exit!
            if isCmd && !isAlt && !isCtrl && (ch == "q" || ch == "Q") {
                activeModal = .quitConfirmation
                return nil
            }

            // If modal is active, let SwiftUI handle the key, including ESC
            if activeModal != nil { return event }

            // ── Ctrl combinations ────────────────────────────────────────
            if isCtrl && !isCmd && !isAlt && !isShift {
                if ch == "l" || ch == "L" || event.keyCode == 37 {
                    activeModal = .diskSpace
                    return nil
                }
            }

            // ESC closes any popups if modal is not active
            if event.keyCode == 53 {
                if showGoMenu { showGoMenu = false }
                if showToolsMenu { showToolsMenu = false }
                if showThemeMenu { showThemeMenu = false }
                return nil
            }

            // ── Cmd combinations ─────────────────────────────────────────
            if isCmd && !isAlt && !isCtrl {
                switch ch {

                // Navigation
                case "[":
                    Task { await activePanel.goBack() };    return nil
                case "]":
                    Task { await activePanel.goForward() }; return nil

                // Cmd+↑ = go to parent
                case _ where event.keyCode == 126:
                    Task { await activePanel.goUp() };      return nil
                // Cmd+↓ = open selected
                case _ where event.keyCode == 125:
                    Task { _ = await activePanel.openSelected() }; return nil

                // Selection
                case "a" where !isShift, "A" where !isShift:
                    let all = Set(activePanel.filteredFiles.indices.filter { activePanel.filteredFiles[$0].name != ".." })
                    activePanel.selectedIndices = all
                    return nil
                case "a" where isShift, "A" where isShift:
                    activePanel.selectedIndices = []
                    return nil
                case "i" where !isShift, "I" where !isShift:
                    let all = Set(activePanel.filteredFiles.indices.filter { activePanel.filteredFiles[$0].name != ".." })
                    activePanel.selectedIndices = all.subtracting(activePanel.selectedIndices)
                    return nil

                // File ops
                case "d" where !isShift, "D" where !isShift:
                    let nodes = activePanel.selectedNodes.filter { $0.name != ".." }
                    if !nodes.isEmpty {
                        copyMoveSource = nodes.count == 1 ? nodes[0].path : "\(nodes.count) selected items"
                        copyMoveDestination = inactivePanel.currentPath
                        activeModal = .copy
                    }
                    return nil
                case "m" where !isShift, "M" where !isShift:
                    let nodes = activePanel.selectedNodes.filter { $0.name != ".." }
                    if !nodes.isEmpty {
                        copyMoveSource = nodes.count == 1 ? nodes[0].path : "\(nodes.count) selected items"
                        copyMoveDestination = inactivePanel.currentPath
                        activeModal = .move
                    }
                    return nil
                case "n" where isShift, "N" where isShift:
                    activeModal = .mkdir
                    return nil
                case _ where event.keyCode == 51 && isCmd:
                    let nodes = activePanel.selectedNodes.filter { $0.name != ".." }
                    if !nodes.isEmpty {
                        modalFilePath = nodes.count == 1 ? nodes[0].name : "\(nodes.count) item(s)"
                        activeModal = .delete
                    }
                    return nil
                case "z" where !isShift, "Z" where !isShift:
                    activeModal = .zip
                    return nil
                case "o", "O":
                    if let node = activePanel.currentSelectedNode, !node.isDirectory {
                        NSWorkspace.shared.open(URL(fileURLWithPath: node.path))
                    } else {
                        Task { _ = await activePanel.openSelected() }
                    }
                    return nil

                // View / Search
                case "f", "F":
                    withAnimation(.easeInOut(duration: 0.2)) { activePanel.isFilterActive.toggle() }
                    if !activePanel.isFilterActive { activePanel.filterText = "" }
                    return nil
                case "g", "G":
                    activeModal = .search
                    return nil
                case "/":
                    withAnimation(.easeInOut(duration: 0.2)) { activePanel.isFilterActive.toggle() }
                    if !activePanel.isFilterActive { activePanel.filterText = "" }
                    return nil

                // Bookmarks
                case "b", "B":
                    let folderName = (activePanel.currentPath as NSString).lastPathComponent
                    activePanel.addBookmark(name: folderName.isEmpty ? "Root" : folderName, path: activePanel.currentPath)
                    return nil
                // Bottom bar actions via Cmd+Number
                case "1": triggerFunctionKey("F1"); return nil
                case "2": triggerFunctionKey("F2"); return nil
                case "3": triggerFunctionKey("F3"); return nil
                case "4": triggerFunctionKey("F4"); return nil
                case "5": triggerFunctionKey("F5"); return nil
                case "6": triggerFunctionKey("F6"); return nil
                case "7": triggerFunctionKey("F7"); return nil
                case "8": triggerFunctionKey("F8"); return nil
                case "9": triggerFunctionKey("F9"); return nil
                case "0": triggerFunctionKey("F10"); return nil

                // Tools
                case "t" where !isShift, "T" where !isShift:
                    openInTerminal(activePanel.currentPath)
                    return nil
                case "r" where isShift, "R" where isShift:
                    openInFinder(activePanel.currentPath)
                    return nil
                case "c" where isShift, "C" where isShift:
                    activeModal = .compareDirs
                    return nil
                case "k" where isShift, "K" where isShift:
                    if let node = activePanel.currentSelectedNode {
                        modalFilePath = node.path
                        activeModal = .checksums
                    }
                    return nil
                case "d" where isShift, "D" where isShift:
                    activeModal = .diskSpace
                    return nil

                // Help
                case "/" where isShift, "?":
                    activeModal = .help
                    return nil

                // System
                case "q", "Q":
                    activeModal = .quitConfirmation
                    return nil
                case "h", "H":
                    NSApplication.shared.hide(nil)
                    return nil
                case "w", "W":
                    NSApplication.shared.hide(nil)
                    return nil

                default:
                    break
                }
            }

            // ── Alt combinations ─────────────────────────────────────────
            if isAlt {
                switch event.keyCode {
                case 98:  // Alt+F7 = Search
                    activeModal = .search; return nil
                default: break
                }
            }

            // ── Cmd combinations (KeyCodes) ──────────────────────────────
            if isCmd && !isAlt && !isCtrl {
                switch event.keyCode {
                case 122: triggerFunctionKey("F1"); return nil
                case 120: triggerFunctionKey("F2"); return nil
                case 99:  triggerFunctionKey("F3"); return nil
                case 118: triggerFunctionKey("F4"); return nil
                case 96:  triggerFunctionKey("F5"); return nil
                case 97:  triggerFunctionKey("F6"); return nil
                case 98:  triggerFunctionKey("F7"); return nil
                case 100: triggerFunctionKey("F8"); return nil
                case 101: triggerFunctionKey("F9"); return nil
                case 109: triggerFunctionKey("F10"); return nil
                default: break
                }
            }

            // ── Plain keyCode (no modifiers or Shift only) ────────────────
            switch event.keyCode {

            // F-keys without modifiers
            case 122: triggerFunctionKey("F1"); return nil
            case 120: triggerFunctionKey("F2"); return nil
            case 99:  triggerFunctionKey("F3"); return nil
            case 118: triggerFunctionKey("F4"); return nil
            case 96:  triggerFunctionKey("F5"); return nil
            case 97:  triggerFunctionKey("F6"); return nil
            case 98:  triggerFunctionKey("F7"); return nil
            case 100: triggerFunctionKey("F8"); return nil
            case 101: triggerFunctionKey("F9"); return nil
            case 109: triggerFunctionKey("F10"); return nil

            // Tab — switch panels
            case 48:
                activePanelIndex = activePanelIndex == 0 ? 1 : 0
                return nil

            // Arrow Up
            case 126:
                guard !isCmd else { break }
                let newIdx = max(0, activePanel.selectedIndex - 1)
                if isShift {
                    if activePanel.selectionAnchor == nil {
                        activePanel.selectionAnchor = activePanel.selectedIndex
                    }
                    activePanel.selectedIndex = newIdx
                    if let anchor = activePanel.selectionAnchor {
                        let lo = min(anchor, newIdx)
                        let hi = max(anchor, newIdx)
                        activePanel.selectedIndices = Set(lo...hi)
                    }
                } else {
                    activePanel.selectedIndex = newIdx
                    activePanel.selectionAnchor = newIdx
                }
                return nil

            // Arrow Down
            case 125:
                guard !isCmd else { break }
                let limit  = activePanel.filteredFiles.count - 1
                let newIdx = min(limit, activePanel.selectedIndex + 1)
                if isShift {
                    if activePanel.selectionAnchor == nil {
                        activePanel.selectionAnchor = activePanel.selectedIndex
                    }
                    activePanel.selectedIndex = newIdx
                    if let anchor = activePanel.selectionAnchor {
                        let lo = min(anchor, newIdx)
                        let hi = max(anchor, newIdx)
                        activePanel.selectedIndices = Set(lo...hi)
                    }
                } else {
                    activePanel.selectedIndex = newIdx
                    activePanel.selectionAnchor = newIdx
                }
                return nil

            // Home (Fn+←)
            case 115:
                activePanel.selectedIndex = 0
                activePanel.selectionAnchor = 0
                return nil

            // End (Fn+→)
            case 119:
                let idx = max(0, activePanel.filteredFiles.count - 1)
                activePanel.selectedIndex = idx
                activePanel.selectionAnchor = idx
                return nil

            // Page Up (Fn+↑)
            case 116:
                let idx = max(0, activePanel.selectedIndex - 15)
                activePanel.selectedIndex = idx
                activePanel.selectionAnchor = idx
                return nil

            // Page Down (Fn+↓)
            case 121:
                let limit = max(0, activePanel.filteredFiles.count - 1)
                let idx = min(limit, activePanel.selectedIndex + 15)
                activePanel.selectedIndex = idx
                activePanel.selectionAnchor = idx
                return nil

            // Enter — open
            case 36:
                Task {
                    let handled = await activePanel.openSelected()
                    if !handled, let node = activePanel.currentSelectedNode {
                        modalFilePath = node.path
                        activeModal   = .viewer
                    }
                }
                return nil

            // Backspace — go up
            case 51:
                guard !isCmd else { break }
                Task { await activePanel.goUp() }
                return nil

            // Space / Insert — toggle selection
            case 49, 63:
                activePanel.toggleSelection(idx: activePanel.selectedIndex)
                if activePanel.selectedIndex < activePanel.filteredFiles.count - 1 {
                    activePanel.selectedIndex += 1
                }
                activePanel.selectionAnchor = activePanel.selectedIndex
                return nil

            // F-keys are now handled natively via .keyboardShortcut on buttons

            default: break
            }

            return event
        }
    }

    public var body: some View {
        let theme = themeManager.currentTheme
        ZStack {
            VStack(spacing: 0) {
                topBar
                
                HStack(spacing: 4) {
                    PanelComponentView(
                        state: leftPanel,
                        title: "Left Panel",
                        isActive: activePanelIndex == 0,
                        theme: theme,
                        onOpenInFinder: { path in openInFinder(path) },
                        onOpenInTerminal: { path in openInTerminal(path) },
                        onZip: { activeModal = .zip },
                        onRenameTitle: {
                            panelRenameText = leftPanel.panelTitle
                            panelToRename = leftPanel
                            activeModal = .renamePanel
                        },
                        onFocus: {
                            activePanelIndex = 0
                        }
                    )
                    
                    PanelComponentView(
                        state: rightPanel,
                        title: "Right Panel",
                        isActive: activePanelIndex == 1,
                        theme: theme,
                        onOpenInFinder: { path in openInFinder(path) },
                        onOpenInTerminal: { path in openInTerminal(path) },
                        onZip: { activeModal = .zip },
                        onRenameTitle: {
                            panelRenameText = rightPanel.panelTitle
                            panelToRename = rightPanel
                            activeModal = .renamePanel
                        },
                        onFocus: {
                            activePanelIndex = 1
                        }
                    )
                }
                .padding(4)
                
                // Background Operation Status Bar
                if isOperationInProgress && activeModal != .progress {
                    HStack(spacing: 8) {
                        if totalBytesToProcess > 0 {
                            // Copy/Move with progress bar
                            let totalProgress = totalBytesToProcess > 0 ? Double(totalBytesProcessed) / Double(totalBytesToProcess) : 0.0
                            Text(conflictIsMove ? "Moving:" : "Copying:")
                                .font(theme.font(size: 11, weight: .bold))
                                .foregroundColor(theme.subtleTextColor)
                            Text(currentCopyFileName.isEmpty ? "Preparing..." : currentCopyFileName)
                                .font(theme.monoFont(size: 11))
                                .foregroundColor(theme.glowColor)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Text("\(formatBytes(totalBytesProcessed)) / \(formatBytes(totalBytesToProcess))")
                                .font(theme.monoFont(size: 11))
                                .foregroundColor(theme.textColor)
                            
                            ASCIIProgressBar(progress: totalProgress, width: 20, theme: theme)
                            
                            Button(action: { activeModal = .progress }) {
                                Text("Show Dialog")
                                    .font(theme.font(size: 10, weight: .bold))
                                    .foregroundColor(theme.textColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(theme.borderColor.opacity(0.3))
                                    .cornerRadius(3)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .retroTooltip("Show full progress dialog", theme: theme)
                        } else {
                            // Other operations (ZIP, Delete, etc.)
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                            Text(operationMessage)
                                .font(theme.font(size: 11))
                                .foregroundColor(theme.textColor)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        
                        // Cancel button to stop any operation
                        Button(action: {
                            isOperationCancelled = true
                            isOperationInProgress = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .retroTooltip("Cancel operation", theme: theme)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(theme.panelBgColor)
                    .border(theme.borderColor, width: 1.5)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
                }
                
                fKeyBar
            }
            .background(theme.backgroundColor)
            
            if let modal = activeModal {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        activeModal = nil
                    }
                
                modalView(for: modal, theme: theme)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            
            // Global Tooltip Overlay
            if tooltipState.isVisible && !tooltipState.text.isEmpty {
                Text(tooltipState.text)
                    .font(theme.monoFont(size: 11))
                    .foregroundColor(theme.textColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.panelBgColor)
                    .border(theme.borderColor, width: 1.5)
                    .shadow(color: Color.black.opacity(0.4), radius: 2, x: 1, y: 1)
                    .fixedSize()
                    .position(tooltipState.position)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .environment(\.tooltipState, tooltipState)
        .coordinateSpace(name: "windowSpace")
        .onChange(of: leftPanel.panelError) { newValue in
            if let error = newValue {
                showError(error)
                leftPanel.panelError = nil
            }
        }
        .onChange(of: rightPanel.panelError) { newValue in
            if let error = newValue {
                showError(error)
                rightPanel.panelError = nil
            }
        }
        .onAppear {
            setupKeyboardMonitor()
            Task {
                await leftPanel.loadDirectory()
                await rightPanel.loadDirectory()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("hNavigator.OpenViewer"))) { notification in
            if let path = notification.object as? String {
                modalFilePath = path
                activeModal = .viewer
            }
        }
    }
}

// MARK: - Water Line and Drop Logo
struct WaterLineDropLogo: View {
    let lineColor: Color
    let dropColor: Color
    
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            
            // Border path for document
            var docPath = Path()
            docPath.move(to: CGPoint(x: 3, y: 2))
            docPath.addLine(to: CGPoint(x: w - 8, y: 2))
            docPath.addLine(to: CGPoint(x: w - 2, y: 8))
            docPath.addLine(to: CGPoint(x: w - 2, y: h - 2))
            docPath.addLine(to: CGPoint(x: 3, y: h - 2))
            docPath.closeSubpath()
            
            context.stroke(docPath, with: .color(lineColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            
            // Folded corner
            var foldPath = Path()
            foldPath.move(to: CGPoint(x: w - 8, y: 2))
            foldPath.addLine(to: CGPoint(x: w - 8, y: 8))
            foldPath.addLine(to: CGPoint(x: w - 2, y: 8))
            context.stroke(foldPath, with: .color(lineColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            
            // 3 text lines
            var linesPath = Path()
            linesPath.move(to: CGPoint(x: 7, y: 12))
            linesPath.addLine(to: CGPoint(x: w - 7, y: 12))
            
            linesPath.move(to: CGPoint(x: 7, y: 15))
            linesPath.addLine(to: CGPoint(x: w - 9, y: 15))
            
            linesPath.move(to: CGPoint(x: 7, y: 18))
            linesPath.addLine(to: CGPoint(x: w - 11, y: 18))
            
            context.stroke(linesPath, with: .color(lineColor), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            
            // Tiny terracotta seal at bottom-right
            var sealPath = Path()
            sealPath.addEllipse(in: CGRect(x: w - 9, y: h - 9, width: 4.5, height: 4.5))
            context.fill(sealPath, with: .color(dropColor))
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Popover Menu Item
struct PopoverMenuItem: View {
    let title: String
    let icon: String?
    let theme: AppTheme
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .frame(width: 14, alignment: .center)
                } else {
                    Spacer().frame(width: 14)
                }
                Text(title)
                    .font(theme.font(size: 12))
            }
            .foregroundColor(isHovered ? theme.selectionTextColor : theme.textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? theme.selectionBgColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            isHovered = hover
        }
    }
}

// Preview
#Preview {
    ContentView()
}