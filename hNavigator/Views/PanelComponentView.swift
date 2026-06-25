import SwiftUI
import Combine
import AppKit
import QuickLookThumbnailing
import QuickLook
public enum FileSortField: String, CaseIterable, Identifiable {
    case name = "Name"
    case size = "Size"
    case date = "Date"
    public var id: String { rawValue }
}

// MARK: - Bookmark Struct
public struct Bookmark: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var path: String

    public init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

public struct CloudStorageFolder: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let path: String
    public let systemImage: String

    public init(id: UUID = UUID(), name: String, path: String, systemImage: String) {
        self.id = id
        self.name = name
        self.path = path
        self.systemImage = systemImage
    }
}

// MARK: - Panel State
@MainActor
public final class PanelState: ObservableObject, Identifiable {
    private let persistenceKey: String

    public let id = UUID()
    @Published public var currentPath: String = ""
    @Published public var files: [VFSNode] = []
    @Published public var selectedIndex: Int = 0
    @Published public var selectedIndices: Set<Int> = []
    @Published public var selectionAnchor: Int? = nil
    @Published public var isLoading: Bool = false
    @Published public var bookmarks: [Bookmark] = []
    @Published public var draggedBookmark: Bookmark? = nil
    @Published public var showHiddenFiles: Bool = false
    @Published public var showPreviews: Bool = false
    @Published public var panelTitle: String = "" {
        didSet {
            savePersistentState()
        }
    }
    @Published public var previewSize: Double = 50.0 {
        didSet {
            savePersistentState()
        }
    }

    public var mountedVolumes: [URL] {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
    }

    public var detectedClouds: [CloudStorageFolder] {
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

    @Published public var sortField: FileSortField = .name
    @Published public var filterText: String = ""
    @Published public var isFilterActive: Bool = false
    @Published public var isRenaming: Bool = false
    @Published public var renameText: String = ""
    @Published public var panelError: String? = nil

    // Navigation history
    private var backStack: [String] = []
    private var forwardStack: [String] = []
    @Published public var canGoBack: Bool = false
    @Published public var canGoForward: Bool = false

    // Disk info
    @Published public var diskFreeBytes: Int64 = 0
    @Published public var diskTotalBytes: Int64 = 0

    public var provider: any VFSProvider = LocalVFSProvider()

    private let localProvider   = LocalVFSProvider()
    private let archiveProvider = ArchiveVFSProvider()
    private let networkProvider = NetworkVFSProvider()
    private let watcher = FileSystemWatcher()

    public var filteredFiles: [VFSNode] {
        var list = files
        if !showHiddenFiles {
            list = list.filter { $0.name == ".." || !$0.name.hasPrefix(".") }
        }
        if isFilterActive && !filterText.isEmpty {
            list = list.filter { $0.name == ".." || $0.name.localizedCaseInsensitiveContains(filterText) }
        }
        return list
    }

    public init(initialPath: String = NSHomeDirectory(), key: String = "panel") {
        self.persistenceKey = key
        self.showHiddenFiles = UserDefaults.standard.bool(forKey: "\(key).showHiddenFiles")
        self.showPreviews = UserDefaults.standard.bool(forKey: "\(key).showPreviews")
        let savedSize = UserDefaults.standard.double(forKey: "\(key).previewSize")
        self.previewSize = savedSize > 0 ? savedSize : 50.0
        let defaultTitle = (key == "leftPanel") ? "Left Panel" : "Right Panel"
        self.panelTitle = UserDefaults.standard.string(forKey: "\(key).panelTitle") ?? defaultTitle

        // Restore last path or fall back to provided initialPath
        let savedPath = UserDefaults.standard.string(forKey: "\(key).lastPath") ?? initialPath
        let isRemote = savedPath.hasPrefix("sftp://") || savedPath.hasPrefix("ftp://") || savedPath.hasPrefix("webdav://") || savedPath.hasPrefix("smb://") || savedPath.hasPrefix("archive://")
        self.currentPath = (isRemote || FileManager.default.fileExists(atPath: savedPath)) ? savedPath : initialPath

        // Restore bookmarks
        if let data = UserDefaults.standard.data(forKey: "\(key).bookmarks"),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            self.bookmarks = decoded
        } else {
            let home = NSHomeDirectory()
            self.bookmarks = [
                Bookmark(name: "Home", path: home),
                Bookmark(name: "Documents", path: (home as NSString).appendingPathComponent("Documents")),
                Bookmark(name: "Downloads", path: (home as NSString).appendingPathComponent("Downloads"))
            ]
        }
    }

    // MARK: - Persistence helpers
    private func savePersistentState() {
        UserDefaults.standard.set(currentPath, forKey: "\(persistenceKey).lastPath")
        UserDefaults.standard.set(showHiddenFiles, forKey: "\(persistenceKey).showHiddenFiles")
        UserDefaults.standard.set(showPreviews, forKey: "\(persistenceKey).showPreviews")
        UserDefaults.standard.set(previewSize, forKey: "\(persistenceKey).previewSize")
        UserDefaults.standard.set(panelTitle, forKey: "\(persistenceKey).panelTitle")
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "\(persistenceKey).bookmarks")
        }
    }

    public func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        savePersistentState()
        let limit = filteredFiles.count
        if selectedIndex >= limit {
            selectedIndex = max(0, limit - 1)
        }
    }

    public func togglePreviews() {
        showPreviews.toggle()
        savePersistentState()
    }

    public var currentSelectedNode: VFSNode? {
        let list = filteredFiles
        guard selectedIndex >= 0 && selectedIndex < list.count else { return nil }
        return list[selectedIndex]
    }

    public func updateProviderForPath(_ path: String) {
        if path.hasPrefix("archive://") {
            provider = archiveProvider
        } else if path.hasPrefix("sftp://") || path.hasPrefix("ftp://") || path.hasPrefix("webdav://") || path.hasPrefix("smb://") {
            provider = networkProvider
        } else {
            provider = localProvider
        }
    }

    public func loadDirectory(silent: Bool = false) async {
        if !silent { isLoading = true }
        updateProviderForPath(currentPath)
        
        if !currentPath.hasPrefix("archive://") && !currentPath.hasPrefix("sftp://") && !currentPath.hasPrefix("ftp://") && !currentPath.hasPrefix("webdav://") && !currentPath.hasPrefix("smb://") {
            watcher.onChange = { [weak self] in
                guard let self = self else { return }
                Task { await self.loadDirectory(silent: true) }
            }
            watcher.start(url: URL(fileURLWithPath: currentPath))
        } else {
            watcher.stop()
        }

        do {
            let loadedFiles = try await provider.listDirectory(at: currentPath)
            let dotDot = loadedFiles.filter { $0.name.hasPrefix("..") }
            var others  = loadedFiles.filter { !$0.name.hasPrefix("..") }

            switch sortField {
            case .name:
                others.sort { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            case .size:
                others.sort { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.size > $1.size }
            case .date:
                others.sort { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.modificationDate > $1.modificationDate }
            }

            self.files = dotDot + others
            if selectedIndex >= files.count { selectedIndex = max(0, files.count - 1) }
            if !silent {
                selectedIndices = []
                selectionAnchor = nil
            }
        } catch let error as NSError {
            if error.domain == "LocalVFSProvider" && error.code == 403 {
                Task { @MainActor in
                    self.panelError = error.localizedDescription
                }
                self.files = [
                    VFSNode(name: ".. [Access Denied]", path: (currentPath as NSString).deletingLastPathComponent.isEmpty ? "/" : (currentPath as NSString).deletingLastPathComponent, size: 0, isDirectory: true),
                    VFSNode(name: "Error: Permission Denied", path: currentPath, size: 0, isDirectory: false)
                ]
            } else {
                self.files = [
                    VFSNode(name: ".. [Go Back]", path: (currentPath as NSString).deletingLastPathComponent.isEmpty ? "/" : (currentPath as NSString).deletingLastPathComponent, size: 0, isDirectory: true),
                    VFSNode(name: "Error: \(error.localizedDescription)", path: currentPath, size: 0, isDirectory: false)
                ]
            }
            self.selectedIndex = 0
        }
        if !silent { isLoading = false }
        updateDiskInfo()
        savePersistentState()
    }

    private func updateDiskInfo() {
        guard !currentPath.hasPrefix("archive://") else {
            diskFreeBytes = 0; diskTotalBytes = 0; return
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: currentPath) {
            diskFreeBytes  = (attrs[.systemFreeSize]  as? Int64) ?? 0
            diskTotalBytes = (attrs[.systemSize]       as? Int64) ?? 0
        }
    }

    // MARK: - Navigation
    public func navigateTo(path: String) async {
        guard path != currentPath else { return }
        backStack.append(currentPath)
        forwardStack.removeAll()
        canGoBack    = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
        currentPath   = path
        selectedIndex = 0
        isFilterActive = false
        filterText = ""
        await loadDirectory()
    }

    public func goBack() async {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(currentPath)
        canGoBack    = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
        currentPath   = prev
        selectedIndex = 0
        await loadDirectory()
    }

    public func goForward() async {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentPath)
        canGoBack    = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
        currentPath   = next
        selectedIndex = 0
        await loadDirectory()
    }

    // MARK: - Bookmarks
    public func addBookmark(name: String, path: String) {
        bookmarks.append(Bookmark(name: name, path: path))
        savePersistentState()
    }

    public func deleteBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        savePersistentState()
    }

    public func renameBookmark(id: UUID, newName: String) {
        if let idx = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks[idx].name = newName
        }
        savePersistentState()
    }

    public func moveBookmark(fromOffsets indices: IndexSet, toOffset newOffset: Int) {
        bookmarks.move(fromOffsets: indices, toOffset: newOffset)
        savePersistentState()
    }

    // MARK: - Multi-select helpers
    public func toggleSelection(idx: Int) {
        if selectedIndices.contains(idx) {
            selectedIndices.remove(idx)
        } else {
            selectedIndices.insert(idx)
        }
    }

    public func rangeSelect(from: Int, to: Int) {
        let lo = min(from, to), hi = max(from, to)
        for i in lo...hi { selectedIndices.insert(i) }
    }

    public var selectedNodes: [VFSNode] {
        if selectedIndices.isEmpty {
            if let n = currentSelectedNode { return [n] }
            return []
        }
        return selectedIndices.sorted().compactMap { idx in
            let list = filteredFiles
            guard idx < list.count else { return nil }
            return list[idx]
        }
    }

    // MARK: - Open
    public func openFile(_ node: VFSNode) -> Bool {
        let ext = (node.name as NSString).pathExtension.lowercased()
        let textExtensions = [
            "txt", "md", "markdown", "rtf", "cfg", "conf", "config", "ini", "plist",
            "json", "xml", "yaml", "yml", "csv", "tsv", "log",
            "html", "htm", "css", "js", "mjs", "ts", "jsx", "tsx",
            "swift", "c", "cpp", "h", "hpp", "cc", "cxx", "java", "kt", "py", "rb", "go",
            "rs", "sh", "bash", "pl", "pm", "php", "sql", "bat", "cmd", "make", "makefile"
        ]
        
        if ext.isEmpty || textExtensions.contains(ext) {
            return false // Open internally via viewer/editor
        }
        
        if !node.path.hasPrefix("archive://") {
            let fileURL = URL(fileURLWithPath: node.path)
            if NSWorkspace.shared.open(fileURL) {
                return true
            }
        }
        return false
    }

    public func openSelected() async -> Bool {
        guard let node = currentSelectedNode else { return false }
        if node.isDirectory {
            await navigateTo(path: node.path)
            return true
        } else {
            let ext = (node.name as NSString).pathExtension.lowercased()
            if ["zip", "7z", "tar", "rar"].contains(ext) {
                await navigateTo(path: "archive://\(node.path)::/")
                return true
            }
            return openFile(node)
        }
    }

    // MARK: - Go Up
    public func goUp() async {
        if currentPath == "/" { return }

        if currentPath.hasPrefix("archive://") {
            let components = currentPath.replacingOccurrences(of: "archive://", with: "").components(separatedBy: "::/")
            if components.count > 1 {
                let inner = components[1]
                if inner.isEmpty {
                    let localFolder = (components[0] as NSString).deletingLastPathComponent
                    await navigateTo(path: localFolder.isEmpty ? "/" : localFolder)
                } else {
                    let parentInner = (inner as NSString).deletingLastPathComponent
                    let parentPath  = "archive://\(components[0])::/\(parentInner)"
                    await navigateTo(path: parentPath == "archive://\(components[0]):://" ? "archive://\(components[0])" : parentPath)
                }
            }
        } else {
            let parent = (currentPath as NSString).deletingLastPathComponent
            await navigateTo(path: parent.isEmpty ? "/" : parent)
        }
    }

    // MARK: - Rename
    public func startRename() {
        guard let node = currentSelectedNode, node.name != ".." else { return }
        renameText = node.name
        isRenaming = true
    }

    public func commitRename() async {
        guard isRenaming, let node = currentSelectedNode, node.name != ".." else {
            isRenaming = false; return
        }
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != node.name else {
            isRenaming = false; return
        }
        let destPath = ((node.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(newName)
        do {
            try await provider.moveItem(from: node.path, to: destPath)
            await loadDirectory()
        } catch {
            print("Rename failed: \(error.localizedDescription)")
        }
        isRenaming = false
    }

    public func cancelRename() {
        isRenaming = false
        renameText = ""
    }

    // MARK: - ZIP creation
    public func createZip(named zipName: String) async throws {
        let nodes = selectedNodes.filter { $0.name != ".." }
        guard !nodes.isEmpty else { return }
        let basePath = currentPath
        
        guard basePath.hasPrefix("/") else {
            throw NSError(domain: "PanelComponentView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Archives can only be created on local filesystems."])
        }
        
        let destZip = (basePath as NSString).appendingPathComponent(zipName.hasSuffix(".zip") ? zipName : "\(zipName).zip")
        let names = nodes.map(\.name)
        
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            var args = ["-r", destZip, "--"]
            args += names
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: basePath)
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw NSError(domain: "PanelComponentView", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Zip creation failed with code \(process.terminationStatus)"])
            }
        }.value
        await loadDirectory()
    }
}

// MARK: - File Icon helper (macOS NSWorkspace icons)
@MainActor
private func fileIcon(for node: VFSNode, theme: AppTheme) -> some View {
    // Use system workspace icons for local files
    if !node.path.hasPrefix("archive://") && node.name != ".." {
        let nsImage = NSWorkspace.shared.icon(forFile: node.path)
        return AnyView(
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .padding(.leading, 8)
                .padding(.trailing, 6)
        )
    }

    // Fallback SF Symbols for archive paths or parent ".."
    let (name, color) = sfSymbol(for: node, theme: theme)
    return AnyView(
        Image(systemName: name)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(color)
            .frame(width: 18, alignment: .center)
            .padding(.leading, 8)
            .padding(.trailing, 6)
    )
}

private func sfSymbol(for node: VFSNode, theme: AppTheme) -> (String, Color) {
    if node.name == ".." {
        return ("arrow.up.circle.fill", theme.subtleTextColor)
    } else if node.isDirectory {
        return ("folder.fill", theme.folderColor)
    } else {
        let ext = (node.name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":   return ("doc.richtext.fill", Color(red: 1, green: 0.35, blue: 0.3))
        case "jpg", "jpeg", "png", "gif", "webp", "heic":
                      return ("photo.fill", Color(red: 0.4, green: 0.8, blue: 0.6))
        case "mp4", "mov", "avi", "mkv":
                      return ("film.fill", Color(red: 0.7, green: 0.3, blue: 1.0))
        case "mp3", "wav", "aac", "flac", "m4a":
                      return ("music.note", Color(red: 1.0, green: 0.6, blue: 0.2))
        case "zip", "gz", "tar", "rar", "7z":
                      return ("archivebox.fill", Color(red: 0.9, green: 0.7, blue: 0.2))
        case "swift", "py", "js", "ts", "go", "rs", "c", "cpp", "h":
                      return ("chevron.left.forwardslash.chevron.right", theme.glowColor)
        case "json", "yaml", "yml", "toml", "xml", "plist":
                      return ("curlybraces", Color(red: 0.5, green: 0.9, blue: 0.6))
        case "sh", "zsh", "bash":
                      return ("terminal.fill", Color(red: 0.3, green: 0.9, blue: 0.5))
        case "app":   return ("app.fill", Color(red: 0.3, green: 0.6, blue: 1.0))
        default:      return ("doc.fill", theme.fileColor)
        }
    }
}

// MARK: - Size formatter
private func formatSize(_ size: Int64, isDir: Bool) -> String {
    if isDir { return "  —  " }
    if size > 1_073_741_824 { return String(format: "%.1f GB", Double(size) / 1_073_741_824.0) }
    if size > 1_048_576     { return String(format: "%.1f MB", Double(size) / 1_048_576.0) }
    if size > 1_024         { return String(format: "%.1f KB", Double(size) / 1_024.0) }
    return "\(size) B"
}

private func formatDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "MM/dd  HH:mm"
    return f.string(from: date)
}

// MARK: - Panel Component View
public struct PanelComponentView: View {
    @ObservedObject var state: PanelState
    let title: String
    let isActive: Bool
    let theme: AppTheme
    var onOpenInFinder: ((String) -> Void)?
    var onOpenInTerminal: ((String) -> Void)?
    var onZip: (() -> Void)?
    var onRenameTitle: (() -> Void)? = nil
    var onFocus: (() -> Void)? = nil

    // Hover & rename tracking
    @State private var hoveredIndex: Int? = nil
    @State private var renamingIdx: Int? = nil
    @State private var renameFieldText: String = ""
    @FocusState private var renameFieldFocused: Bool
    @State private var previewURL: URL? = nil

    public var body: some View {
        RetroBox(title: state.panelTitle, theme: theme, isActive: isActive, doubleLine: true, onDoubleTapTitle: onRenameTitle) {
            ZStack {
                VStack(spacing: 0) {
                    bookmarksBar
                    driveBar
                    navigationBar
                    if state.isFilterActive {
                        filterBar
                    }
                    columnHeaders
                    fileList
                    footerBar
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onFocus?()
                }
                
                Button("") {
                    if let node = state.currentSelectedNode, !node.path.hasPrefix("archive://") {
                        previewURL = URL(fileURLWithPath: node.path)
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
            }
        }
        .quickLookPreview($previewURL)
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers, _ in
            return handleDrop(providers: providers)
        }
    }

    // MARK: - Bookmarks Bar & Buttons
    @State private var editingBookmarkId: UUID? = nil
    @State private var tempBookmarkName: String = ""

    @ViewBuilder
    private func bookmarkButton(_ bookmark: Bookmark) -> some View {
        let isBookmarkActive = state.currentPath == bookmark.path

        HStack(spacing: 4) {
            Image(systemName: "pin.fill")
                .font(.system(size: 8))
                .foregroundColor(isBookmarkActive ? .white : theme.subtleTextColor)

            if editingBookmarkId == bookmark.id {
                TextField("", text: $tempBookmarkName, onCommit: {
                    if !tempBookmarkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        state.renameBookmark(id: bookmark.id, newName: tempBookmarkName)
                    }
                    editingBookmarkId = nil
                })
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 85)
                .foregroundColor(theme.textColor)
            } else {
                Text(bookmark.name)
                    .font(.system(size: 11, weight: isBookmarkActive ? .semibold : .regular))
                    .foregroundColor(isBookmarkActive ? .white : theme.subtleTextColor)
            }

            Button(action: {
                state.deleteBookmark(id: bookmark.id)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isBookmarkActive ? Color.white.opacity(0.8) : theme.subtleTextColor.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle())
            .retroTooltip("Remove bookmark", theme: theme)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isBookmarkActive
                ? AnyView(Capsule().fill(theme.accentGradient).opacity(0.8))
                : AnyView(Capsule().fill(theme.borderColor.opacity(0.15)))
        )
        .contextMenu {
            Button("Rename") {
                tempBookmarkName = bookmark.name
                editingBookmarkId = bookmark.id
            }
            Button("Pin current folder here") {
                if let idx = state.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                    state.bookmarks[idx].path = state.currentPath
                    let folderName = (state.currentPath as NSString).lastPathComponent
                    state.bookmarks[idx].name = folderName.isEmpty ? "Root" : folderName
                }
            }
            Button("Delete") {
                state.deleteBookmark(id: bookmark.id)
            }
        }
        .onTapGesture {
            onFocus?()
            if editingBookmarkId != bookmark.id {
                Task { await state.navigateTo(path: bookmark.path) }
            }
        }
        .retroTooltip("Go to bookmark: \(bookmark.path)", theme: theme)
        .onTapGesture(count: 2) {
            onFocus?()
            tempBookmarkName = bookmark.name
            editingBookmarkId = bookmark.id
        }
    }

    private var bookmarksBar: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(state.bookmarks.enumerated()), id: \.element.id) { idx, bookmark in
                        if idx < 9 {
                            bookmarkButton(bookmark)
                                .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: [.command, .option])
                                .onDrag {
                                    state.draggedBookmark = bookmark
                                    return NSItemProvider(object: bookmark.id.uuidString as NSString)
                                }
                                .onDrop(of: ["public.text"], delegate: BookmarkDropDelegate(item: bookmark, state: state))
                        } else {
                            bookmarkButton(bookmark)
                                .onDrag {
                                    state.draggedBookmark = bookmark
                                    return NSItemProvider(object: bookmark.id.uuidString as NSString)
                                }
                                .onDrop(of: ["public.text"], delegate: BookmarkDropDelegate(item: bookmark, state: state))
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Button(action: {
                let folderName = (state.currentPath as NSString).lastPathComponent
                state.addBookmark(name: folderName.isEmpty ? "Root" : folderName, path: state.currentPath)
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(theme.glowColor)
                    .padding(4)
            }
            .buttonStyle(PlainButtonStyle())
            .retroTooltip("Bookmark current folder (add tab)", theme: theme)

            Menu {
                ForEach(FileSortField.allCases) { field in
                    Button(action: {
                        state.sortField = field
                        Task { await state.loadDirectory() }
                    }) {
                        Label(field.rawValue, systemImage: sortIcon(field))
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.textColor)
                    .padding(5)
                    .background(theme.borderColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .foregroundColor(theme.textColor)
            .frame(width: 26)
            .retroTooltip("Sort files", theme: theme)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func sortIcon(_ field: FileSortField) -> String {
        switch field {
        case .name: return "textformat.abc"
        case .size: return "scalemass"
        case .date: return "calendar"
        }
    }

    // MARK: - Drive Bar & Buttons
    @ViewBuilder
    private func driveButton(name: String, path: String, icon: String) -> some View {
        let isActive = state.currentPath == path
        Button(action: {
            onFocus?()
            Task { await state.navigateTo(path: path) }
        }) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(name)
                    .font(.system(size: 10, weight: isActive ? .bold : .regular, design: .monospaced))
            }
            .foregroundColor(isActive ? .white : theme.textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isActive ? AnyView(theme.accentGradient) : AnyView(theme.borderColor.opacity(0.12)))
            .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
        .retroTooltip("Go to \(name) (\(path))", theme: theme)
    }

    private var driveBar: some View {
        HStack(spacing: 4) {
            Text("DRIVES:")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(theme.subtleTextColor)
                .padding(.leading, 6)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    driveButton(name: "Home", path: NSHomeDirectory(), icon: "house.fill")
                    driveButton(name: "Root", path: "/", icon: "folder.fill")
                    
                    let vols = state.mountedVolumes
                    ForEach(vols, id: \.self) { url in
                        driveButton(name: url.lastPathComponent, path: url.path, icon: "externaldrive.fill")
                    }
                    
                    let clouds = state.detectedClouds
                    ForEach(clouds) { cloud in
                        driveButton(name: cloud.name, path: cloud.path, icon: cloud.systemImage)
                    }
                    
                    if state.currentPath.hasPrefix("sftp://") || state.currentPath.hasPrefix("ftp://") || state.currentPath.hasPrefix("webdav://") || state.currentPath.hasPrefix("smb://") {
                        let serverHost = state.currentPath.components(separatedBy: "://").last?.components(separatedBy: "/").first ?? "Remote"
                        driveButton(name: "Net: \(serverHost)", path: state.currentPath, icon: "network")
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .background(theme.borderColor.opacity(0.05))
        .border(theme.borderColor.opacity(0.15), width: 0.5)
    }

    // MARK: - Navigation bar (back / forward / path)
    private var navigationBar: some View {
        HStack(spacing: 4) {
            // Back
            Button(action: { onFocus?(); Task { await state.goBack() } }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(state.canGoBack ? theme.glowColor : theme.subtleTextColor.opacity(0.35))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!state.canGoBack)
            .retroTooltip("Go back", theme: theme)

            // Forward
            Button(action: { onFocus?(); Task { await state.goForward() } }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(state.canGoForward ? theme.glowColor : theme.subtleTextColor.opacity(0.35))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!state.canGoForward)
            .retroTooltip("Go forward", theme: theme)

            Image(systemName: "folder")
                .font(.system(size: 10))
                .foregroundColor(theme.subtleTextColor)

            Text(state.currentPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.subtleTextColor)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Hidden files toggle
            Button(action: {
                onFocus?()
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.toggleHiddenFiles()
                }
            }) {
                Image(systemName: state.showHiddenFiles ? "eye.fill" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundColor(state.showHiddenFiles ? theme.glowColor : theme.subtleTextColor)
            }
            .buttonStyle(PlainButtonStyle())
            .retroTooltip(state.showHiddenFiles ? "Hide hidden files" : "Show hidden files", theme: theme)

            // Previews toggle
            Button(action: {
                onFocus?()
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.togglePreviews()
                }
            }) {
                Image(systemName: state.showPreviews ? "photo.fill" : "photo")
                    .font(.system(size: 11))
                    .foregroundColor(state.showPreviews ? theme.glowColor : theme.subtleTextColor)
            }
            .buttonStyle(PlainButtonStyle())
            .retroTooltip(state.showPreviews ? "Hide image/video previews" : "Show image/video previews", theme: theme)

            if state.showPreviews {
                Slider(value: $state.previewSize, in: 30...80)
                .frame(width: 70)
                .controlSize(.mini)
                .retroTooltip("Adjust preview size", theme: theme)
            }

            // Filter toggle
            Button(action: {
                onFocus?()
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.isFilterActive.toggle()
                    if !state.isFilterActive { state.filterText = "" }
                }
            }) {
                Image(systemName: state.isFilterActive ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(state.isFilterActive ? theme.glowColor : theme.subtleTextColor)
            }
            .buttonStyle(PlainButtonStyle())
            .retroTooltip("Toggle filter (Cmd+F)", theme: theme)

            if state.isLoading {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Filter bar
    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(theme.glowColor)

            TextField("Filter...", text: $state.filterText)
                .onTapGesture { onFocus?() }
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(theme.textColor)

            if !state.filterText.isEmpty {
                Button(action: { state.filterText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(theme.subtleTextColor)
                }
                .buttonStyle(PlainButtonStyle())
                .retroTooltip("Clear filter", theme: theme)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(theme.borderColor.opacity(0.12))
        .overlay(
            Rectangle().fill(theme.borderColor.opacity(0.3)).frame(height: 1),
            alignment: .bottom
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Column headers
    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            if state.showPreviews {
                Text("Preview")
                    .frame(width: state.previewSize + 20, alignment: .center)
            }
            Text("Size")
                .frame(width: 78, alignment: .trailing)
            Text("Modified")
                .frame(width: 100, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(theme.subtleTextColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Rectangle().fill(theme.borderColor.opacity(0.12)))
        .overlay(Rectangle().fill(theme.borderColor.opacity(0.35)).frame(height: 1), alignment: .bottom)
    }

    // MARK: - File list
    private var fileList: some View {
        Group {
            let displayFiles = state.filteredFiles
            if state.isLoading && displayFiles.isEmpty {
                loadingView
            } else if displayFiles.isEmpty {
                emptyView
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(0..<displayFiles.count, id: \.self) { idx in
                            fileRow(idx: idx, node: displayFiles[idx])
                                .id(idx)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 0)
                    .onChange(of: state.selectedIndex) {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(state.selectedIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading…")
                .font(.system(size: 12))
                .foregroundColor(theme.subtleTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(theme.subtleTextColor.opacity(0.5))
            Text("Empty directory")
                .font(.system(size: 12))
                .foregroundColor(theme.subtleTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Single file row
    @ViewBuilder
    private func fileRow(idx: Int, node: VFSNode) -> some View {
        let isSelected     = state.selectedIndex == idx
        let isMultiSelected = state.selectedIndices.contains(idx)
        let isHovered      = hoveredIndex == idx
        let isBeingRenamed = renamingIdx == idx
        let isHidden       = node.name.hasPrefix(".") && node.name != ".."

        HStack(spacing: 0) {
            fileIcon(for: node, theme: theme)
                .opacity(isHidden ? 0.6 : 1.0)

            // Name / Rename field
            if isBeingRenamed {
                TextField("", text: $renameFieldText, onCommit: {
                    commitRowRename(node: node)
                })
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 12.5, design: theme == .retroDark ? .monospaced : .default))
                .foregroundColor(theme.textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused($renameFieldFocused)
                .onExitCommand { cancelRowRename() }
            } else {
                let nameText = Text(node.name)
                    .font(.system(
                        size: 12.5,
                        weight: isSelected ? .semibold : .regular,
                        design: theme == .retroDark ? .monospaced : .default
                    ))
                
                (isHidden ? nameText.italic() : nameText)
                    .lineLimit(1)
                    .foregroundColor(
                        isSelected || isMultiSelected
                            ? theme.selectionTextColor
                            : (node.isDirectory ? theme.folderColor : theme.textColor)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isHidden ? 0.6 : 1.0)
            }

            if state.showPreviews {
                RetroFilePreviewView(node: node, theme: theme, size: state.previewSize)
                    .id(node.path)
                    .frame(width: state.previewSize + 20, alignment: .center)
                    .opacity(isHidden ? 0.6 : 1.0)
            }

            let sizeText = Text(formatSize(node.size, isDir: node.isDirectory))
                .font(.system(size: 11, design: .monospaced))

            (isHidden ? sizeText.italic() : sizeText)
                .foregroundColor((isSelected || isMultiSelected) ? theme.selectionTextColor.opacity(0.85) : theme.subtleTextColor)
                .frame(width: 78, alignment: .trailing)
                .opacity(isHidden ? 0.6 : 1.0)

            let dateText = Text(formatDate(node.modificationDate))
                .font(.system(size: 11, design: .monospaced))

            (isHidden ? dateText.italic() : dateText)
                .foregroundColor((isSelected || isMultiSelected) ? theme.selectionTextColor.opacity(0.7) : theme.subtleTextColor)
                .frame(width: 100, alignment: .trailing)
                .padding(.trailing, 8)
                .opacity(isHidden ? 0.6 : 1.0)
        }
        .frame(height: state.showPreviews ? state.previewSize + 14 : 26)
        .background(rowBackground(isSelected: isSelected, isMultiSelected: isMultiSelected, isHovered: isHovered))
        .contentShape(Rectangle())
        .onTapGesture {
            let clickCount = NSApp.currentEvent?.clickCount ?? 1
            if clickCount == 2 {
                state.selectedIndex = idx
                state.selectedIndices = []
                Task {
                    let handled = await state.openSelected()
                    if !handled && node.name != ".." {
                        NotificationCenter.default.post(name: NSNotification.Name("hNavigator.OpenViewer"), object: node.path)
                    }
                }
            } else {
                handleTap(idx: idx)
            }
        }
        .onHover { hovering in hoveredIndex = hovering ? idx : nil }
        .contextMenu {
            fileContextMenu(node: node, idx: idx)
        }
        .onDrag {
            let url = URL(fileURLWithPath: node.path)
            return NSItemProvider(object: url as NSURL)
        }
        .animation(.easeOut(duration: 0.08), value: isSelected)
        .animation(.easeOut(duration: 0.08), value: isMultiSelected)
        .animation(.easeOut(duration: 0.08), value: isHovered)
    }

    private func handleTap(idx: Int) {
        // Read modifier keys directly from last NSEvent
        let nsEvent = NSApp.currentEvent
        let isCmd   = nsEvent?.modifierFlags.contains(.command) ?? false
        let isShift = nsEvent?.modifierFlags.contains(.shift) ?? false

        onFocus?()

        if isCmd {
            state.toggleSelection(idx: idx)
            state.selectedIndex = idx
            state.selectionAnchor = idx
        } else if isShift {
            let anchor = state.selectionAnchor ?? state.selectedIndex
            state.selectedIndices = []
            state.rangeSelect(from: anchor, to: idx)
            state.selectedIndex = idx
        } else {
            state.selectedIndices = []
            state.selectedIndex = idx
            state.selectionAnchor = idx
        }
    }

    private func startRowRename(idx: Int, node: VFSNode) {
        renameFieldText = node.name
        renamingIdx = idx
        renameFieldFocused = true
    }

    private func commitRowRename(node: VFSNode) {
        let newName = renameFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != node.name else {
            cancelRowRename(); return
        }
        let destPath = ((node.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(newName)
        Task {
            do {
                try await state.provider.moveItem(from: node.path, to: destPath)
                await state.loadDirectory()
            } catch {
                print("Rename failed: \(error.localizedDescription)")
            }
        }
        renamingIdx = nil
    }

    private func cancelRowRename() {
        renamingIdx = nil
        renameFieldText = ""
    }

    @ViewBuilder
    private func fileContextMenu(node: VFSNode, idx: Int) -> some View {
        if node.name != ".." {
            Button("Rename") {
                state.selectedIndex = idx
                state.selectedIndices = []
                startRowRename(idx: idx, node: node)
            }
            Button("Open in Finder") {
                state.selectedIndex = idx
                state.selectedIndices = []
                onOpenInFinder?(node.isDirectory ? node.path : (node.path as NSString).deletingLastPathComponent)
            }
            if !node.isDirectory {
                Button("Open in Default App") {
                    state.selectedIndex = idx
                    state.selectedIndices = []
                    NSWorkspace.shared.open(URL(fileURLWithPath: node.path))
                }
            }
            Divider()
            Button("Create ZIP from Selected") {
                if !state.selectedIndices.contains(idx) {
                    state.selectedIndex = idx
                    state.selectedIndices = [idx]
                }
                onZip?()
            }
            Divider()
            Button("Open Terminal Here") {
                state.selectedIndex = idx
                state.selectedIndices = []
                onOpenInTerminal?(node.isDirectory ? node.path : (node.path as NSString).deletingLastPathComponent)
            }
        }
    }

    @ViewBuilder
    private func rowBackground(isSelected: Bool, isMultiSelected: Bool, isHovered: Bool) -> some View {
        if isSelected {
            if isActive {
                Rectangle().fill(theme.accentGradient).opacity(0.75)
            } else {
                Rectangle()
                    .stroke(theme.borderColor.opacity(0.45), lineWidth: 1.5)
            }
        } else if isMultiSelected {
            Rectangle().fill(theme.glowColor.opacity(0.22))
        } else if isHovered {
            Rectangle().fill(theme.glowColor.opacity(0.08))
        } else {
            Color.clear
        }
    }

    // MARK: - Drag & Drop handler
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadObject(ofClass: NSURL.self) { item, _ in
                guard let url = item as? URL else { return }
                Task { @MainActor in
                    let path = url.path
                    let dest = (state.currentPath as NSString).appendingPathComponent((path as NSString).lastPathComponent)
                    do {
                        try await state.provider.copyItem(from: path, to: dest, progress: nil)
                        await state.loadDirectory()
                    } catch {
                        print("Drop copy failed: \(error.localizedDescription)")
                    }
                }
            }
        }
        return true
    }

    // MARK: - Footer
    private var footerBar: some View {
        let displayFiles = state.filteredFiles
        let dirCount  = displayFiles.filter { $0.isDirectory && $0.name != ".." }.count
        let fileCount = displayFiles.filter { !$0.isDirectory }.count
        let totalSize = displayFiles.reduce(0) { $0 + ($1.isDirectory ? 0 : $1.size) }

        let selectedCount = state.selectedIndices.count
        let diskFree  = state.diskFreeBytes
        let diskTotal = state.diskTotalBytes

        return VStack(spacing: 0) {
            // Selected info row (only when multi-selected)
            if selectedCount > 1 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(theme.glowColor)
                    Text("\(selectedCount) selected")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.glowColor)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(theme.glowColor.opacity(0.08))
            }

            HStack {
                Label("\(dirCount) folders", systemImage: "folder")
                    .font(.system(size: 10))
                    .foregroundColor(theme.subtleTextColor)

                Text("·")
                    .foregroundColor(theme.subtleTextColor.opacity(0.4))

                Label("\(fileCount) files", systemImage: "doc")
                    .font(.system(size: 10))
                    .foregroundColor(theme.subtleTextColor)

                Spacer()

                // Disk space indicator
                if diskTotal > 0 {
                    HStack(spacing: 4) {
                        // Mini disk gauge
                        let usedRatio = max(0, min(1, Double(diskTotal - diskFree) / Double(diskTotal)))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(theme.borderColor.opacity(0.3))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(usedRatio > 0.85 ? Color.red.opacity(0.7) : theme.glowColor.opacity(0.6))
                                    .frame(width: geo.size.width * usedRatio)
                            }
                        }
                        .frame(width: 40, height: 5)

                        Text("\(formatSize(diskFree, isDir: false)) free")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(theme.subtleTextColor)
                    }
                } else {
                    Text(formatSize(totalSize, isDir: false))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.subtleTextColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Rectangle().fill(theme.borderColor.opacity(0.10)))
        .overlay(Rectangle().fill(theme.borderColor.opacity(0.3)).frame(height: 1), alignment: .top)
    }
}

// MARK: - Bookmark Drop Delegate
struct BookmarkDropDelegate: DropDelegate {
    let item: Bookmark
    let state: PanelState

    func performDrop(info: DropInfo) -> Bool {
        state.draggedBookmark = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = state.draggedBookmark else { return }
        if draggedItem != item {
            guard let from = state.bookmarks.firstIndex(of: draggedItem),
                  let to = state.bookmarks.firstIndex(of: item) else { return }
            
            if from != to {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.moveBookmark(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }
}

// MARK: - Retro File Preview View
struct RetroFilePreviewView: View {
    let node: VFSNode
    let theme: AppTheme
    let size: Double
    
    @State private var thumbnail: NSImage? = nil
    @State private var hasAttempted = false
    
    var body: some View {
        ZStack {
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                // Bordered empty cell / subtle placeholder
                Color.black.opacity(0.15)
            }
        }
        .frame(width: size + 4, height: size + 4)
        .border(theme.borderColor.opacity(0.4), width: 1)
        .background(Color.black.opacity(0.2))
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard !hasAttempted else { return }
        hasAttempted = true
        
        let path = node.path
        // Only generate for local files
        guard !path.hasPrefix("archive://") &&
              !path.hasPrefix("sftp://") &&
              !path.hasPrefix("ftp://") &&
              !path.hasPrefix("webdav://") &&
              !path.hasPrefix("smb://") &&
              !node.isDirectory else {
            return
        }
        
        let ext = (path as NSString).pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "bmp", "raf", "cr2", "nef"]
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "3gp"]
        
        guard imageExtensions.contains(ext) || videoExtensions.contains(ext) else {
            return
        }
        
        let url = URL(fileURLWithPath: path)
        let requestSize = CGSize(width: 80, height: 80)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: requestSize,
            scale: scale,
            representationTypes: .thumbnail
        )
        
        QLThumbnailGenerator.shared.generateRepresentations(for: request) { reply, type, error in
            if let reply = reply {
                Task { @MainActor in
                    self.thumbnail = reply.nsImage
                }
            }
        }
    }
}

// MARK: - Tooltip State Management
public class TooltipState: ObservableObject {
    @Published public var text: String = ""
    @Published public var position: CGPoint = .zero
    @Published public var isVisible: Bool = false
    @Published public var edge: VerticalEdge = .bottom
    
    public init() {}
}

public struct TooltipStateKey: EnvironmentKey {
    public static let defaultValue: TooltipState? = nil
}

extension EnvironmentValues {
    public var tooltipState: TooltipState? {
        get { self[TooltipStateKey.self] }
        set { self[TooltipStateKey.self] = newValue }
    }
}

struct RetroTooltipModifier: ViewModifier {
    let text: String
    let theme: AppTheme
    var edge: VerticalEdge = .bottom
    
    @Environment(\.tooltipState) private var tooltipState
    @State private var localFrame: CGRect = .zero
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            localFrame = geo.frame(in: .named("windowSpace"))
                        }
                        .onChange(of: geo.frame(in: .named("windowSpace"))) {
                            localFrame = geo.frame(in: .named("windowSpace"))
                        }
                }
            )
            .onHover { hovering in
                guard let tooltipState = tooltipState else { return }
                if hovering && !text.isEmpty {
                    let x = localFrame.midX
                    let y = edge == .bottom ? localFrame.maxY + 15 : localFrame.minY - 15
                    tooltipState.text = text
                    tooltipState.position = CGPoint(x: x, y: y)
                    tooltipState.edge = edge
                    tooltipState.isVisible = true
                } else {
                    if tooltipState.text == text {
                        tooltipState.isVisible = false
                    }
                }
            }
    }
}

extension View {
    public func retroTooltip(_ text: String, theme: AppTheme, edge: VerticalEdge = .bottom) -> some View {
        self.modifier(RetroTooltipModifier(text: text, theme: theme, edge: edge))
    }
}

