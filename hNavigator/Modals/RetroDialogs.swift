import SwiftUI

// ==========================================
// 1. HELP DIALOG
// ==========================================
public struct RetroHelpDialog: View {
    let theme: AppTheme
    let onClose: () -> Void
    
    @State private var selectedTab: Int = 0
    @FocusState private var focusedField: HelpFocusField?
    
    enum HelpFocusField: Hashable {
        case tabBtn(Int)
        case ok
    }
    
    private func cycleFocus(forward: Bool) {
        let fields: [HelpFocusField] = [
            .tabBtn(0),
            .tabBtn(1),
            .tabBtn(2),
            .tabBtn(3),
            .tabBtn(4),
            .ok
        ]
        guard let current = focusedField else {
            focusedField = .ok
            return
        }
        guard let idx = fields.firstIndex(of: current) else { return }
        if forward {
            focusedField = fields[(idx + 1) % fields.count]
        } else {
            focusedField = fields[(idx - 1 + fields.count) % fields.count]
        }
    }
    
    public var body: some View {
        RetroBox(title: "hNavigator Help", theme: theme, isActive: true, doubleLine: true) {
            VStack(spacing: 12) {
                // Tab Header Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        tabButton(title: "Navigation", index: 0)
                        tabButton(title: "Selection", index: 1)
                        tabButton(title: "File Ops", index: 2)
                        tabButton(title: "Tools & Bookmarks", index: 3)
                        tabButton(title: "Compliance", index: 4)
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 30)
                
                Divider().background(theme.borderColor)
                
                // Tab Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        tabContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                }
                .frame(maxHeight: .infinity)
                
                Divider().background(theme.borderColor)
                
                // Close button
                Button(action: onClose) {
                    Text("   OK   ")
                        .retroButtonStyle(theme: theme, isFocused: focusedField == .ok, type: .primary)
                }
                .buttonStyle(PlainButtonStyle())
                .focusable()
                .focused($focusedField, equals: .ok)
                .retroTooltip("Close help screen", theme: theme)
            }
        }
        .frame(width: 520, height: 400)
        .onAppear {
            focusedField = .ok
        }
        .onKeyPress { press in
            if press.key == .tab {
                cycleFocus(forward: true)
                return .handled
            } else if press.key == .leftArrow || press.key == .upArrow {
                cycleFocus(forward: false)
                return .handled
            } else if press.key == .rightArrow || press.key == .downArrow {
                cycleFocus(forward: true)
                return .handled
            } else if press.key == .return {
                if focusedField == .ok {
                    onClose()
                } else if case .tabBtn(let idx) = focusedField {
                    selectedTab = idx
                }
                return .handled
            } else if press.key == .escape {
                onClose()
                return .handled
            }
            return .ignored
        }
    }
    
    @ViewBuilder
    private func tabButton(title: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        let isFocused = focusedField == .tabBtn(index)
        Button(action: { 
            selectedTab = index 
            focusedField = .tabBtn(index)
        }) {
            Text(title)
                .font(theme.font(size: 11, weight: .bold))
                .foregroundColor(isSelected ? .black : (isFocused ? .white : theme.textColor))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isSelected ? theme.glowColor : (isFocused ? theme.glowColor.opacity(0.5) : theme.borderColor.opacity(0.15)))
                .cornerRadius(4)
                .border(isFocused ? Color.white : Color.clear, width: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .focusable()
        .focused($focusedField, equals: .tabBtn(index))
        .retroTooltip("Switch to \(title) help tab", theme: theme)
    }
    
    @ViewBuilder
    private func shortcutRow(keys: String, desc: String) -> some View {
        HStack(alignment: .top) {
            Text(keys)
                .font(theme.monoFont(size: 11, weight: .bold))
                .foregroundColor(theme.glowColor)
                .frame(width: 140, alignment: .leading)
            
            Text(desc)
                .font(theme.font(size: 11))
                .foregroundColor(theme.textColor)
        }
        .padding(.vertical, 1)
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            VStack(alignment: .leading, spacing: 6) {
                shortcutRow(keys: "Tab", desc: "Switch active panel (Left / Right)")
                shortcutRow(keys: "Arrows ↑/↓", desc: "Move selection cursor up/down")
                shortcutRow(keys: "Enter", desc: "Open directory / archive / view file")
                shortcutRow(keys: "Backspace / Cmd+↑", desc: "Go to parent folder (Up)")
                shortcutRow(keys: "Cmd + ↓", desc: "Open selected folder or file")
                shortcutRow(keys: "Cmd + [ / ]", desc: "History Back / Forward")
                shortcutRow(keys: "Home / End", desc: "Jump to first / last file")
                shortcutRow(keys: "Page Up / Down", desc: "Scroll by 15 items")
            }
        case 1:
            VStack(alignment: .leading, spacing: 6) {
                shortcutRow(keys: "Space / Insert", desc: "Toggle selection and move cursor down")
                shortcutRow(keys: "Shift + ↑/↓", desc: "Extend selection cursor up/down")
                shortcutRow(keys: "Cmd + A", desc: "Select all items (excluding ..)")
                shortcutRow(keys: "Cmd + Shift + A", desc: "Deselect all items")
                shortcutRow(keys: "Cmd + I", desc: "Invert selection")
            }
        case 2:
            VStack(alignment: .leading, spacing: 6) {
                shortcutRow(keys: "F2", desc: "Rename selected item")
                shortcutRow(keys: "F5 / Cmd+D", desc: "Copy selected items to other panel")
                shortcutRow(keys: "F6 / Cmd+M", desc: "Move selected items to other panel")
                shortcutRow(keys: "F7 / Cmd+Shift+N", desc: "Create new folder (Make Directory)")
                shortcutRow(keys: "F8 / Cmd+Delete", desc: "Delete selected items permanently")
                shortcutRow(keys: "Cmd + Z", desc: "Create ZIP archive of selected items")
                shortcutRow(keys: "Cmd + O", desc: "Open selected item with default macOS app")
            }
        case 3:
            VStack(alignment: .leading, spacing: 6) {
                shortcutRow(keys: "F3", desc: "Quick view file (Text/Hex Mode)")
                shortcutRow(keys: "F4", desc: "Edit file in built-in Text Editor")
                shortcutRow(keys: "F9", desc: "Cycle UI theme style")
                shortcutRow(keys: "F10 / Cmd+Q", desc: "Quit application")
                shortcutRow(keys: "Cmd + F / /", desc: "Toggle Quick Live Filter bar")
                shortcutRow(keys: "Cmd + G / Alt+F7", desc: "Deep file search dialog")
                shortcutRow(keys: "Cmd + B", desc: "Bookmark current folder")
                shortcutRow(keys: "Cmd + 1...9", desc: "Trigger F1...F9 function keys")
                shortcutRow(keys: "Cmd + T", desc: "Open current folder in Terminal")
                shortcutRow(keys: "Cmd + Shift + R", desc: "Reveal current folder in Finder")
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Legal & Compliance:")
                    .font(theme.font(size: 12, weight: .bold))
                    .foregroundColor(theme.glowColor)
                    .padding(.bottom, 2)
                
                complianceLink(title: "Privacy Policy", urlString: "https://humaniaq.notion.site/Privacy-policy-38fe92b23a9080be8b8be3c164bb58d5")
                complianceLink(title: "Terms & Conditions", urlString: "https://humaniaq.notion.site/Terms-and-Conditions-3319975d885b495fac89a98f073bc2fb")
                complianceLink(title: "Support Desk", urlString: "https://humaniaq.notion.site/Support-38fe92b23a908055b69ad37cda9d3286")
            }
        }
    }
    
    @ViewBuilder
    private func complianceLink(title: String, urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                HStack {
                    Text(title)
                        .font(theme.font(size: 11, weight: .bold))
                        .foregroundColor(theme.textColor)
                    Spacer()
                    Text("Open ↗")
                        .font(theme.font(size: 9))
                        .foregroundColor(theme.glowColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(theme.borderColor.opacity(0.1))
                .cornerRadius(4)
                .border(theme.borderColor.opacity(0.3), width: 1)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}



// ==========================================
// 3. COPY / MOVE CONFIRMATION DIALOG
// ==========================================
public struct RetroCopyMoveDialog: View {
    let title: String
    let sourcePath: String
    @State var destPath: String
    let theme: AppTheme
    let onCancel: () -> Void
    let onConfirm: (String) -> Void
    
    @FocusState private var focusedField: FocusField?
    
    enum FocusField: Hashable {
        case destPath
        case ok
        case cancel
    }
    
    private func cycleFocus(forward: Bool) {
        switch focusedField {
        case .destPath:
            focusedField = forward ? .ok : .cancel
        case .ok:
            focusedField = forward ? .cancel : .destPath
        case .cancel:
            focusedField = forward ? .destPath : .ok
        case nil:
            focusedField = .destPath
        }
    }
    
    public var body: some View {
        RetroBox(title: title, theme: theme, isActive: true, doubleLine: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Source:")
                    .font(theme.font( size: 12))
                    .foregroundColor(theme.borderColor)
                Text(sourcePath)
                    .font(theme.font( size: 13))
                    .foregroundColor(theme.textColor)
                    .lineLimit(2)
                    .padding(4)
                    .background(Color.black.opacity(0.2))
                
                Text("Destination Directory / Path:")
                    .font(theme.font( size: 12))
                    .foregroundColor(theme.borderColor)
                
                TextField("", text: $destPath)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(theme.font(size: 14))
                    .retroInputStyle(theme: theme, isFocused: focusedField == .destPath)
                    .focused($focusedField, equals: .destPath)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Spacer()
                    Button(action: { onConfirm(destPath) }) {
                        Text("   OK   ")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .ok, type: .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .ok)
                    
                    Button(action: onCancel) {
                        Text(" Cancel ")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .cancel, type: .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .cancel)
                    Spacer()
                }
            }
        }
        .frame(width: 480, height: 260)
        .onAppear {
            focusedField = .destPath
        }
        .onKeyPress { press in
            if press.key == .tab {
                cycleFocus(forward: true)
                return .handled
            } else if press.key == .leftArrow || press.key == .upArrow {
                if focusedField != .destPath {
                    cycleFocus(forward: false)
                    return .handled
                }
            } else if press.key == .rightArrow || press.key == .downArrow {
                if focusedField != .destPath {
                    cycleFocus(forward: true)
                    return .handled
                }
            } else if press.key == .return {
                if focusedField == .cancel {
                    onCancel()
                } else {
                    onConfirm(destPath)
                }
                return .handled
            } else if press.key == .escape {
                onCancel()
                return .handled
            }
            return .ignored
        }
    }
}

// ==========================================
// 4. MKDIR DIALOG
// ==========================================
public struct RetroMkDirDialog: View {
    let theme: AppTheme
    let onCancel: () -> Void
    let onConfirm: (String) -> Void
    
    @State private var folderName = ""
    @FocusState private var focusedField: FocusField?
    
    enum FocusField: Hashable {
        case folderName
        case ok
        case cancel
    }
    
    private func cycleFocus(forward: Bool) {
        switch focusedField {
        case .folderName:
            focusedField = forward ? .ok : .cancel
        case .ok:
            focusedField = forward ? .cancel : .folderName
        case .cancel:
            focusedField = forward ? .folderName : .ok
        case nil:
            focusedField = .folderName
        }
    }
    
    public var body: some View {
        RetroBox(title: "F7 Make Directory", theme: theme, isActive: true, doubleLine: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter folder name:")
                    .font(theme.font( size: 13))
                    .foregroundColor(theme.textColor)
                
                TextField("", text: $folderName)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(theme.font( size: 14))
                    .retroInputStyle(theme: theme, isFocused: focusedField == .folderName)
                    .focused($focusedField, equals: .folderName)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Spacer()
                    Button(action: { onConfirm(folderName) }) {
                        Text("   OK   ")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .ok, type: .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .ok)
                    .disabled(folderName.isEmpty)
                    
                    Button(action: onCancel) {
                        Text(" Cancel ")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .cancel, type: .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .cancel)
                    Spacer()
                }
            }
        }
        .frame(width: 380, height: 180)
        .onAppear {
            focusedField = .folderName
        }
        .onKeyPress { press in
            if press.key == .tab {
                cycleFocus(forward: true)
                return .handled
            } else if press.key == .leftArrow || press.key == .upArrow {
                if focusedField != .folderName {
                    cycleFocus(forward: false)
                    return .handled
                }
            } else if press.key == .rightArrow || press.key == .downArrow {
                if focusedField != .folderName {
                    cycleFocus(forward: true)
                    return .handled
                }
            } else if press.key == .return {
                if focusedField == .cancel {
                    onCancel()
                } else if !folderName.isEmpty {
                    onConfirm(folderName)
                }
                return .handled
            } else if press.key == .escape {
                onCancel()
                return .handled
            }
            return .ignored
        }
    }
}

// ==========================================
// 5. DELETE DIALOG
// ==========================================
public struct RetroDeleteDialog: View {
    let fileName: String
    let theme: AppTheme
    let onCancel: () -> Void
    let onConfirm: () -> Void
    
    @FocusState private var focusedField: FocusField?
    
    enum FocusField: Hashable {
        case delete
        case cancel
    }
    
    public var body: some View {
        RetroBox(title: "F8 Delete Confirmation", theme: theme, isActive: true, doubleLine: true) {
            VStack(spacing: 16) {
                Text("⚠️ WARNING ⚠️")
                    .font(theme.font( size: 16))
                    .foregroundColor(.red)
                
                Text("Are you sure you want to permanently delete:\n\(fileName)?")
                    .font(theme.font( size: 13))
                    .foregroundColor(theme.textColor)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: onConfirm) {
                        Text(" DELETE ")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .delete, type: .danger)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .delete)
                    
                    Button(action: onCancel) {
                        Text(" Cancel ")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .cancel, type: .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .cancel)
                }
            }
        }
        .frame(width: 400, height: 200)
        .onAppear {
            focusedField = .cancel
        }
        .onKeyPress { press in
            if press.key == .tab {
                focusedField = (focusedField == .delete) ? .cancel : .delete
                return .handled
            } else if press.key == .leftArrow || press.key == .rightArrow || press.key == .upArrow || press.key == .downArrow {
                focusedField = (focusedField == .delete) ? .cancel : .delete
                return .handled
            } else if press.key == .return {
                if focusedField == .delete {
                    onConfirm()
                } else {
                    onCancel()
                }
                return .handled
            } else if press.key == .escape {
                onCancel()
                return .handled
            }
            return .ignored
        }
    }
}

// ==========================================
// 6. SEARCH DIALOG (Alt+F7)
// ==========================================
private func matchesWildcard(_ text: String, pattern: String, isCaseSensitive: Bool) -> Bool {
    let targetText = isCaseSensitive ? text : text.lowercased()
    let rawPattern = isCaseSensitive ? pattern : pattern.lowercased()
    
    if !rawPattern.contains("*") && !rawPattern.contains("?") {
        return targetText.contains(rawPattern)
    }
    
    var regexPattern = NSRegularExpression.escapedPattern(for: rawPattern)
    regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")
    regexPattern = regexPattern.replacingOccurrences(of: "\\?", with: ".")
    regexPattern = "^\(regexPattern)$"
    
    guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else {
        return false
    }
    let range = NSRange(location: 0, length: targetText.utf16.count)
    return regex.firstMatch(in: targetText, options: [], range: range) != nil
}

public struct RetroSearchDialog: View {
    let rootPath: String
    let theme: AppTheme
    let onCancel: () -> Void
    let onSelectFile: (String) -> Void
    
    @State private var query = ""
    @State private var contentQuery = ""
    @State private var isCaseSensitive = false
    @State private var results: [String] = []
    @State private var isSearching = false
    @State private var searchStatus = "Enter query and hit Search"
    
    @FocusState private var focusedField: FocusField?
    
    enum FocusField: Hashable {
        case query
        case contentQuery
        case caseSensitive
        case search
        case close
    }
    
    private func cycleFocus(forward: Bool) {
        let fields: [FocusField] = [.query, .contentQuery, .caseSensitive, .search, .close]
        guard let current = focusedField else {
            focusedField = .query
            return
        }
        guard let idx = fields.firstIndex(of: current) else { return }
        if forward {
            focusedField = fields[(idx + 1) % fields.count]
        } else {
            focusedField = fields[(idx - 1 + fields.count) % fields.count]
        }
    }
    
    private func startSearch() {
        isSearching = true
        searchStatus = "Scanning directories..."
        results.removeAll()
        
        let filePattern = query
        let textPattern = contentQuery
        let caseSensitive = isCaseSensitive
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: rootPath)
        
        Task.detached(priority: .userInitiated) {
            var foundPaths: [String] = []
            
            // Recurse directory
            let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            
            while let fileURL = enumerator?.nextObject() as? URL {
                if Task.isCancelled { break }
                
                let lastComponent = fileURL.lastPathComponent
                
                // Filename check
                if !filePattern.isEmpty {
                    let isMatched = matchesWildcard(lastComponent, pattern: filePattern, isCaseSensitive: caseSensitive)
                    if !isMatched {
                        continue
                    }
                }
                
                // File content check
                if !textPattern.isEmpty {
                    do {
                        let content = try String(contentsOf: fileURL, encoding: .utf8)
                        let matchContent = caseSensitive ? content : content.lowercased()
                        let matchQuery = caseSensitive ? textPattern : textPattern.lowercased()
                        if !matchContent.contains(matchQuery) {
                            continue
                        }
                    } catch {
                        continue // Skip binaries or unreadable files
                    }
                }
                
                foundPaths.append(fileURL.path)
                
                // Cap results to 50 for quick display
                if foundPaths.count >= 50 {
                    break
                }
            }
            
            let finalPaths = foundPaths
            await MainActor.run {
                self.results = finalPaths
                self.isSearching = false
                self.searchStatus = "Search complete! Found \(finalPaths.count) items."
            }
        }
    }
    
    public var body: some View {
        RetroBox(title: "Alt+F7 Find Files", theme: theme, isActive: true, doubleLine: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Search Path: \(rootPath)")
                    .font(theme.font( size: 11))
                    .foregroundColor(theme.borderColor)
                
                Text("File Name Mask (e.g. *.txt, *test*):")
                    .font(theme.font( size: 12))
                TextField("", text: $query)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(theme.font( size: 13))
                    .retroInputStyle(theme: theme, isFocused: focusedField == .query)
                    .focused($focusedField, equals: .query)
                
                Text("Containing Text (optional):")
                    .font(theme.font( size: 12))
                TextField("", text: $contentQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(theme.font( size: 13))
                    .retroInputStyle(theme: theme, isFocused: focusedField == .contentQuery)
                    .focused($focusedField, equals: .contentQuery)
                
                HStack {
                    Button(action: { isCaseSensitive.toggle() }) {
                        HStack(spacing: 6) {
                            Text(isCaseSensitive ? "[X]" : "[ ]")
                                .font(theme.monoFont(size: 13, weight: .bold))
                                .foregroundColor(theme.glowColor)
                            Text("Case-Sensitive")
                                .font(theme.font(size: 12))
                                .foregroundColor(theme.textColor)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(focusedField == .caseSensitive ? theme.borderColor.opacity(0.2) : Color.clear)
                        .border(focusedField == .caseSensitive ? Color.white : Color.clear, width: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .caseSensitive)
                    .retroTooltip("Toggle case-sensitive matching", theme: theme)
                    
                    Spacer()
                }
                
                HStack {
                    Button(action: startSearch) {
                        Text(isSearching ? "Searching..." : "  Search  ")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .search, type: .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .search)
                    .retroTooltip("Start search scan", theme: theme)
                    .disabled(isSearching || (query.isEmpty && contentQuery.isEmpty))
                    
                    Spacer()
                    Text(searchStatus)
                        .font(theme.font( size: 11))
                        .foregroundColor(theme.borderColor)
                }
                .padding(.top, 4)
                
                Divider().background(theme.borderColor)
                
                Text("Results (Limit 50):")
                    .font(theme.font( size: 12))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(results, id: \.self) { path in
                            Text((path as NSString).lastPathComponent)
                                .font(theme.font( size: 13))
                                .foregroundColor(theme.textColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(2)
                                .background(Color.black.opacity(0.1))
                                .onTapGesture {
                                    onSelectFile(path)
                                }
                        }
                    }
                }
                .frame(maxHeight: 180)
                .background(Color.black.opacity(0.2))
                
                Spacer()
                
                HStack {
                    Spacer()
                    Button(action: onCancel) {
                        Text("  Close  ")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .close, type: .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .close)
                    .retroTooltip("Cancel and close search", theme: theme)
                    Spacer()
                }
            }
        }
        .frame(width: 580, height: 480)
        .onAppear {
            focusedField = .query
        }
        .onKeyPress { press in
            if press.key == .tab {
                cycleFocus(forward: true)
                return .handled
            } else if press.key == .leftArrow || press.key == .upArrow {
                if focusedField != .query && focusedField != .contentQuery {
                    cycleFocus(forward: false)
                    return .handled
                }
            } else if press.key == .rightArrow || press.key == .downArrow {
                if focusedField != .query && focusedField != .contentQuery {
                    cycleFocus(forward: true)
                    return .handled
                }
            } else if press.key == .return {
                if focusedField == .close {
                    onCancel()
                } else {
                    startSearch()
                }
                return .handled
            } else if press.key == .escape {
                onCancel()
                return .handled
            }
            return .ignored
        }
    }
}

// ==========================================
// 7. DISK SPACE ANALYSIS DIALOG
// ==========================================
public struct DiskAnalysisItem: Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    public let size: Int64
    public let percent: Double
}

private nonisolated func diskAnalysisItems(at path: String) async throws -> [DiskAnalysisItem] {
    let fm = FileManager.default
    let url = URL(fileURLWithPath: path)
    guard let contents = try? fm.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
        options: []
    ) else { return [] }
    
    var details: [(String, Int64)] = []
    var total: Int64 = 0
    
    for item in contents {
        try Task.checkCancellation()
        await Task.yield()
        
        let name = item.lastPathComponent
        let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        let isDir = values?.isDirectory ?? false
        
        if isDir {
            let subContents = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: [.fileSizeKey], options: [])) ?? []
            var dirSize: Int64 = 0
            for sub in subContents {
                try Task.checkCancellation()
                let sz = (try? sub.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                dirSize += Int64(sz)
            }
            details.append((name, dirSize))
            total += dirSize
        } else {
            let size = Int64(values?.fileSize ?? 0)
            details.append((name, size))
            total += size
        }
    }
    
    return details.sorted { $0.1 > $1.1 }.prefix(8).map { entry in
        let pct = total > 0 ? Double(entry.1) / Double(total) : 0.0
        return DiskAnalysisItem(name: entry.0, size: entry.1, percent: pct)
    }
}

public struct RetroDiskAnalysisDialog: View {
    let currentPath: String
    let theme: AppTheme
    let onClose: () -> Void
    
    @State private var items: [DiskAnalysisItem] = []
    @State private var isLoading = true
    @State private var analysisTask: Task<Void, Never>?
    
    @FocusState private var isFocused: Bool
    
    private func analyze() {
        isLoading = true
        analysisTask = Task {
            do {
                let result = try await diskAnalysisItems(at: currentPath)
                if !Task.isCancelled {
                    items = result
                    isLoading = false
                }
            } catch {
                if !Task.isCancelled {
                    isLoading = false
                }
            }
        }
    }
    
    private func getFormattedSize(_ size: Int64) -> String {
        if size > 1024 * 1024 {
            return String(format: "%.1fM", Double(size) / (1024.0 * 1024.0))
        }
        return String(format: "%.1fK", Double(size) / 1024.0)
    }
    
    public var body: some View {
        RetroBox(title: "Disk Space Analyzer", theme: theme, isActive: true, doubleLine: true) {
            VStack(spacing: 8) {
                Text("Analyzing Folder:\n\(currentPath)")
                    .font(theme.font( size: 11))
                    .foregroundColor(theme.borderColor)
                    .multilineTextAlignment(.center)
                
                Divider().background(theme.borderColor)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if items.isEmpty {
                    Spacer()
                    Text("No files to analyze.")
                        .font(theme.font( size: 13))
                    Spacer()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(0..<items.count, id: \.self) { idx in
                            let item = items[idx]
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(item.name)
                                        .font(theme.font( size: 13))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(getFormattedSize(item.size))
                                        .font(theme.font( size: 11))
                                }
                                
                                // Retro progress bar
                                GeometryReader { geo in
                                    let fillWidth = max(2, geo.size.width * CGFloat(item.percent))
                                    ZStack(alignment: .leading) {
                                        Rectangle()
                                            .fill(Color.black.opacity(0.4))
                                        Rectangle()
                                            .fill(theme.folderColor)
                                            .frame(width: fillWidth)
                                    }
                                }
                                .frame(height: 10)
                                .border(theme.borderColor, width: 1)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Spacer()
                
                HStack {
                    if isLoading {
                        Button(action: {
                            analysisTask?.cancel()
                            onClose()
                        }) {
                            Text("Cancel")
                                .retroButtonStyle(theme: theme, isFocused: isFocused, type: .danger)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .focused($isFocused)
                    } else {
                        Button(action: onClose) {
                            Text("Close")
                                .retroButtonStyle(theme: theme, isFocused: isFocused, type: .primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .focused($isFocused)
                    }
                }
            }
        }
        .frame(width: 450, height: 420)
        .onAppear {
            isFocused = true
            analyze()
        }
        .onDisappear {
            analysisTask?.cancel()
        }
        .onKeyPress { press in
            if press.key == .escape || press.key == .return {
                if isLoading {
                    analysisTask?.cancel()
                }
                onClose()
                return .handled
            }
            return .ignored
        }
    }
}

// ==========================================
// 8. CHECKSUM CALCULATOR
// ==========================================
import CryptoKit

private nonisolated func computeChecksums(filePath: String) async -> (String, String) {
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDir) {
        if isDir.boolValue {
            return ("Directories are not supported", "Please select a file, not a directory.")
        }
    }
    let fileURL = URL(fileURLWithPath: filePath)
    guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
        return ("Error reading file", "Make sure the file exists and is readable.")
    }
    let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined().uppercased()
    let sha256 = SHA256.hash(data: data).map { String(format: "%02hhx", $0) }.joined().uppercased()
    return (md5, sha256)
}

public struct RetroChecksumDialog: View {
    let filePath: String
    let theme: AppTheme
    let onClose: () -> Void
    
    @State private var md5Str = "Calculating MD5..."
    @State private var sha256Str = "Calculating SHA256..."
    @State private var isLoading = true
    
    private func calculate() {
        isLoading = true
        Task {
            let (md5Result, sha256Result) = await computeChecksums(filePath: filePath)
            md5Str = md5Result
            sha256Str = sha256Result
            isLoading = false
        }
    }
    
    public var body: some View {
        RetroBox(title: "Checksum Hash Calculator", theme: theme, isActive: true, doubleLine: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text("File: \((filePath as NSString).lastPathComponent)")
                    .font(theme.font( size: 13))
                    .foregroundColor(theme.folderColor)
                
                Divider().background(theme.borderColor)
                
                Text("MD5 Hash:")
                    .font(theme.font( size: 12))
                    .foregroundColor(theme.borderColor)
                Text(md5Str)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(theme.textColor)
                    .padding(4)
                    .background(Color.black.opacity(0.3))
                    .textSelection(.enabled)
                
                Text("SHA-256 Hash:")
                    .font(theme.font( size: 12))
                    .foregroundColor(theme.borderColor)
                Text(sha256Str)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(theme.textColor)
                    .padding(4)
                    .background(Color.black.opacity(0.3))
                    .textSelection(.enabled)
                    .lineLimit(2)
                
                Spacer()
                
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Text("Close")
                            .font(theme.font( size: 13))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .background(Color.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Spacer()
                }
            }
        }
        .frame(width: 480, height: 280)
        .onAppear {
            calculate()
        }
    }
}

// ==========================================
// 9. COMPARE DIRECTORIES DIALOG
// ==========================================
public struct RetroCompareDirsDialog: View {
    let leftFiles: [VFSNode]
    let rightFiles: [VFSNode]
    let theme: AppTheme
    let onClose: () -> Void
    
    @State private var diffReport: [String] = []
    
    private func runComparison() {
        var report: [String] = []
        
        let leftSet = Set(leftFiles.filter { $0.name != ".." }.map { $0.name })
        let rightSet = Set(rightFiles.filter { $0.name != ".." }.map { $0.name })
        
        let onlyInLeft = leftSet.subtracting(rightSet)
        let onlyInRight = rightSet.subtracting(leftSet)
        let common = leftSet.intersection(rightSet)
        
        report.append("--- Comparison Report ---")
        
        if onlyInLeft.isEmpty && onlyInRight.isEmpty && common.isEmpty {
            report.append("Directories are completely empty.")
        } else {
            if !onlyInLeft.isEmpty {
                report.append("\nItems ONLY in Left Panel:")
                for item in onlyInLeft.sorted() {
                    report.append("  [+] \(item)")
                }
            }
            
            if !onlyInRight.isEmpty {
                report.append("\nItems ONLY in Right Panel:")
                for item in onlyInRight.sorted() {
                    report.append("  [+] \(item)")
                }
            }
            
            // Compare size of common files
            var sizeDiffs: [String] = []
            for name in common.sorted() {
                let lFile = leftFiles.first { $0.name == name }
                let rFile = rightFiles.first { $0.name == name }
                
                if let lf = lFile, let rf = rFile {
                    if lf.isDirectory != rf.isDirectory {
                        sizeDiffs.append("  [~] \(name) (Left is Dir, Right is File, or vice versa)")
                    } else if !lf.isDirectory {
                        if lf.size != rf.size {
                            sizeDiffs.append("  [~] \(name) (Size mismatch: L:\(lf.size)B vs R:\(rf.size)B)")
                        }
                    }
                }
            }
            
            if !sizeDiffs.isEmpty {
                report.append("\nSize Mismatch / Type Mismatch:")
                report.append(contentsOf: sizeDiffs)
            }
            
            if onlyInLeft.isEmpty && onlyInRight.isEmpty && sizeDiffs.isEmpty {
                report.append("\nDirectories are identical!")
            }
        }
        
        diffReport = report
    }
    
    public var body: some View {
        RetroBox(title: "Directory Compare Results", theme: theme, isActive: true, doubleLine: true) {
            VStack(spacing: 8) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(diffReport, id: \.self) { line in
                            Text(line)
                                .font(theme.font( size: 13))
                                .foregroundColor(line.contains("[+]") ? .green : (line.contains("[~]") ? .yellow : theme.textColor))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.3))
                
                Spacer()
                
                Button(action: onClose) {
                    Text("Close")
                        .font(theme.font( size: 13))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .background(Color.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(width: 500, height: 380)
        .onAppear {
            runComparison()
        }
    }
}

// ==========================================
// 9. QUIT CONFIRMATION DIALOG
// ==========================================
public struct RetroQuitConfirmationDialog: View {
    let theme: AppTheme
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @FocusState private var focusedField: FocusField?

    enum FocusField: Hashable {
        case yes
        case no
    }

    public var body: some View {
        RetroBox(title: "Quit hNavigator", theme: theme, isActive: true, doubleLine: true) {
            VStack(spacing: 16) {
                Spacer()
                Text("Are you sure you want to quit hNavigator?")
                    .font(theme.font(size: 14))
                    .foregroundColor(theme.textColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                HStack(spacing: 24) {
                    Button(action: onConfirm) {
                        Text("  [Yes]  ")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .yes, type: .danger)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .yes)
                    
                    Button(action: onCancel) {
                        Text("  [No]  ")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .no, type: .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .no)
                }
                Spacer()
            }
        }
        .frame(width: 380, height: 180)
        .onAppear {
            focusedField = .no
        }
        .onKeyPress { press in
            if press.key == .tab {
                focusedField = (focusedField == .yes) ? .no : .yes
                return .handled
            } else if press.key == .leftArrow || press.key == .rightArrow || press.key == .upArrow || press.key == .downArrow {
                focusedField = (focusedField == .yes) ? .no : .yes
                return .handled
            } else if press.key == .return {
                if focusedField == .yes {
                    onConfirm()
                } else {
                    onCancel()
                }
                return .handled
            } else if press.key == .escape {
                onCancel()
                return .handled
            }
            return .ignored
        }
    }
}

// ==========================================
// 10. CONNECT TO SERVER DIALOG
// ==========================================
public struct RetroConnectServerDialog: View {
    let theme: AppTheme
    let onCancel: () -> Void
    let onConnect: (String) -> Void
    
    @State private var selectedProtocol = "SFTP"
    @State private var serverAddress = "ftp.apple.com"
    @State private var username = "guest"
    @State private var password = ""
    @State private var port = "22"
    
    @FocusState private var focusedField: FocusField?
    
    enum FocusField: Hashable {
        case protocolBtn(String)
        case address
        case port
        case username
        case password
        case connect
        case cancel
    }
    
    private func cycleFocus(forward: Bool) {
        let fields: [FocusField] = [
            .protocolBtn("SFTP"),
            .protocolBtn("FTP"),
            .protocolBtn("WebDAV"),
            .protocolBtn("SMB"),
            .address,
            .port,
            .username,
            .password,
            .connect,
            .cancel
        ]
        
        guard let current = focusedField else {
            focusedField = .address
            return
        }
        
        guard let idx = fields.firstIndex(of: current) else { return }
        
        if forward {
            focusedField = fields[(idx + 1) % fields.count]
        } else {
            focusedField = fields[(idx - 1 + fields.count) % fields.count]
        }
    }
    
    public var body: some View {
        RetroBox(title: "Connect to Remote Server", theme: theme, isActive: true, doubleLine: true) {
            VStack(alignment: .leading, spacing: 10) {
                // Protocol selector
                Text("Protocol:")
                    .font(theme.font(size: 11))
                    .foregroundColor(theme.subtleTextColor)
                HStack(spacing: 8) {
                    ForEach(["SFTP", "FTP", "WebDAV", "SMB"], id: \.self) { proto in
                        let isSelected = selectedProtocol == proto
                        let isFocused = focusedField == .protocolBtn(proto)
                        Button(action: {
                            selectedProtocol = proto
                            if proto == "SFTP" { port = "22" }
                            else if proto == "FTP" { port = "21" }
                            else if proto == "WebDAV" { port = "80" }
                            else if proto == "SMB" { port = "445" }
                        }) {
                            Text(proto)
                                .font(theme.font(size: 11, weight: .bold))
                                .foregroundColor(isSelected ? .black : (isFocused ? .white : theme.textColor))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(isSelected ? theme.glowColor : (isFocused ? theme.glowColor.opacity(0.5) : theme.borderColor.opacity(0.15)))
                                .border(isFocused ? Color.white : Color.clear, width: 1)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .focusable()
                        .focused($focusedField, equals: .protocolBtn(proto))
                        .retroTooltip("Select \(proto) protocol", theme: theme)
                    }
                }
                
                // Server Address & Port
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server Address:")
                            .font(theme.font(size: 11))
                            .foregroundColor(theme.subtleTextColor)
                        TextField("", text: $serverAddress)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(theme.font(size: 13))
                            .retroInputStyle(theme: theme, isFocused: focusedField == .address)
                            .focused($focusedField, equals: .address)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port:")
                            .font(theme.font(size: 11))
                            .foregroundColor(theme.subtleTextColor)
                        TextField("", text: $port)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(theme.font(size: 13))
                            .retroInputStyle(theme: theme, isFocused: focusedField == .port)
                            .frame(width: 60)
                            .focused($focusedField, equals: .port)
                    }
                }
                
                // Credentials
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Username:")
                            .font(theme.font(size: 11))
                            .foregroundColor(theme.subtleTextColor)
                        TextField("", text: $username)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(theme.font(size: 13))
                            .retroInputStyle(theme: theme, isFocused: focusedField == .username)
                            .focused($focusedField, equals: .username)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password (optional):")
                            .font(theme.font(size: 11))
                            .foregroundColor(theme.subtleTextColor)
                        SecureField("", text: $password)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(theme.font(size: 13))
                            .retroInputStyle(theme: theme, isFocused: focusedField == .password)
                            .focused($focusedField, equals: .password)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    Spacer()
                    
                    Button(action: {
                        let prefix = selectedProtocol.lowercased()
                        onConnect("\(prefix)://\(serverAddress)")
                    }) {
                        Text(" Connect ")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .connect, type: .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .connect)
                    .retroTooltip("Establish connection to server", theme: theme)
                    
                    Button(action: onCancel) {
                        Text(" Cancel ")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .cancel, type: .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .cancel)
                    .retroTooltip("Cancel and close connection setup", theme: theme)
                    
                    Spacer()
                }
            }
        }
        .frame(width: 440, height: 290)
        .onAppear {
            focusedField = .address
        }
        .onKeyPress { press in
            if press.key == .tab {
                cycleFocus(forward: true)
                return .handled
            } else if press.key == .leftArrow || press.key == .upArrow {
                if focusedField != .address && focusedField != .port && focusedField != .username && focusedField != .password {
                    cycleFocus(forward: false)
                    return .handled
                }
            } else if press.key == .rightArrow || press.key == .downArrow {
                if focusedField != .address && focusedField != .port && focusedField != .username && focusedField != .password {
                    cycleFocus(forward: true)
                    return .handled
                }
            } else if press.key == .return {
                if focusedField == .cancel {
                    onCancel()
                } else {
                    let prefix = selectedProtocol.lowercased()
                    onConnect("\(prefix)://\(serverAddress)")
                }
                return .handled
            } else if press.key == .escape {
                onCancel()
                return .handled
            }
            return .ignored
        }
    }
}

// MARK: - Dialog Styling Helpers
public enum RetroButtonType {
    case primary
    case secondary
    case danger
}

extension View {
    public func retroInputStyle(theme: AppTheme, isFocused: Bool) -> some View {
        self
            .padding(6)
            .background(theme.panelBgColor)
            .foregroundColor(theme.textColor)
            .cornerRadius(theme.cornerRadius / 2)
            .border(isFocused ? theme.glowColor : theme.borderColor, width: isFocused ? 1.5 : 1.0)
    }
    
    public func retroButtonStyle(theme: AppTheme, isFocused: Bool, type: RetroButtonType = .primary) -> some View {
        let normalBg: Color
        switch type {
        case .primary:
            normalBg = theme.glowColor.opacity(0.15)
        case .secondary:
            normalBg = theme.borderColor.opacity(0.25)
        case .danger:
            normalBg = Color.red.opacity(0.2)
        }
        
        let focusedBg: Color = theme.glowColor
        let activeBg = isFocused ? focusedBg : normalBg
        
        let textColor: Color
        if isFocused {
            textColor = theme.selectionTextColor
        } else {
            switch type {
            case .primary, .danger:
                textColor = theme.textColor
            case .secondary:
                textColor = theme.subtleTextColor
            }
        }
        
        return self
            .font(theme.font(size: 13, weight: .bold))
            .foregroundColor(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(activeBg)
            .cornerRadius(theme.cornerRadius / 2)
            .border(isFocused ? theme.glowColor : theme.borderColor.opacity(0.5), width: isFocused ? 1.5 : 1.0)
    }
}

public struct RetroErrorDialog: View {
    let message: String
    let theme: AppTheme
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    public var body: some View {
        RetroBox(title: "ERROR", theme: theme, isActive: true, doubleLine: true) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 32))
                    
                    Text(message)
                        .font(theme.font(size: 13))
                        .foregroundColor(theme.textColor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                Divider().background(theme.borderColor)

                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("OK")
                            .retroButtonStyle(theme: theme, isFocused: isFocused, type: .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focused($isFocused)
                    Spacer()
                }
            }
            .padding(8)
        }
        .frame(width: 400)
        .onAppear {
            isFocused = true
        }
        .onKeyPress { press in
            if press.key == .return || press.key == .escape || press.key == .space {
                onDismiss()
                return .handled
            }
            return .ignored
        }
    }
}

// MARK: - DOS Navigator Progress UI
public struct ASCIIProgressBar: View {
    let progress: Double // 0.0 to 1.0
    let width: Int // Character width
    let theme: AppTheme
    
    public init(progress: Double, width: Int = 30, theme: AppTheme) {
        self.progress = max(0.0, min(1.0, progress))
        self.width = width
        self.theme = theme
    }
    
    public var body: some View {
        let filledCount = Int(progress * Double(width))
        let emptyCount = width - filledCount
        let filledStr = String(repeating: "█", count: filledCount)
        let emptyStr = String(repeating: "░", count: emptyCount)
        let percentStr = String(format: "%3.0f%%", progress * 100)
        
        Text("[\(filledStr)\(emptyStr)] \(percentStr)")
            .font(theme.monoFont(size: 13))
            .foregroundColor(theme.textColor)
    }
}

public struct RetroCopyProgressDialog: View {
    let currentFileName: String
    let fileProgress: Double
    let totalBytes: Int64
    let processedBytes: Int64
    let timeRemaining: String
    let theme: AppTheme
    let onCancel: () -> Void
    let onBackground: () -> Void
    
    @State private var isHoveringCancel = false
    @State private var isHoveringBackground = false
    @State private var showCancelConfirm = false
    @State private var isHoveringConfirmCancel = false
    @State private var isHoveringDenyCancel = false
    
    public init(currentFileName: String, fileProgress: Double, totalBytes: Int64, processedBytes: Int64, timeRemaining: String, theme: AppTheme, onCancel: @escaping () -> Void, onBackground: @escaping () -> Void) {
        self.currentFileName = currentFileName
        self.fileProgress = fileProgress
        self.totalBytes = totalBytes
        self.processedBytes = processedBytes
        self.timeRemaining = timeRemaining
        self.theme = theme
        self.onCancel = onCancel
        self.onBackground = onBackground
    }
    
    public var body: some View {
        RetroBox(title: "Copying Files", theme: theme, isActive: true, doubleLine: true) {
            VStack(alignment: .leading, spacing: 16) {
                // File info
                HStack {
                    Text("Copying:")
                        .font(theme.font(size: 13, weight: .bold))
                        .foregroundColor(theme.subtleTextColor)
                    Text(currentFileName.isEmpty ? "Preparing..." : currentFileName)
                        .font(theme.monoFont(size: 13))
                        .foregroundColor(theme.glowColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                
                // File Progress
                VStack(alignment: .leading, spacing: 4) {
                    Text("File Progress")
                        .font(theme.font(size: 12))
                        .foregroundColor(theme.subtleTextColor)
                    ASCIIProgressBar(progress: fileProgress, width: 35, theme: theme)
                }
                
                // Total Progress
                VStack(alignment: .leading, spacing: 4) {
                    let totalProgress = totalBytes > 0 ? Double(processedBytes) / Double(totalBytes) : 0.0
                    HStack {
                        Text("Total Progress")
                            .font(theme.font(size: 12))
                            .foregroundColor(theme.subtleTextColor)
                        Spacer()
                        if !timeRemaining.isEmpty {
                            Text("ETA: \(timeRemaining)")
                                .font(theme.monoFont(size: 11))
                                .foregroundColor(theme.textColor)
                        }
                    }
                    ASCIIProgressBar(progress: totalProgress, width: 35, theme: theme)
                }
                
                HStack(spacing: 20) {
                    Spacer()
                    if showCancelConfirm {
                        Text("Are you sure?")
                            .font(theme.font(size: 13, weight: .bold))
                            .foregroundColor(Color.red)
                        
                        Button("Yes, Cancel") {
                            onCancel()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .retroButtonStyle(theme: theme, isFocused: isHoveringConfirmCancel, type: .danger)
                        .onHover { hover in isHoveringConfirmCancel = hover }
                        
                        Button("No") {
                            showCancelConfirm = false
                        }
                        .buttonStyle(PlainButtonStyle())
                        .retroButtonStyle(theme: theme, isFocused: isHoveringDenyCancel, type: .secondary)
                        .onHover { hover in isHoveringDenyCancel = hover }
                    } else {
                        Button("Cancel") {
                            showCancelConfirm = true
                        }
                        .buttonStyle(PlainButtonStyle())
                        .retroButtonStyle(theme: theme, isFocused: isHoveringCancel, type: .danger)
                        .onHover { hover in isHoveringCancel = hover }
                        
                        Button("Background") {
                            onBackground()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .retroButtonStyle(theme: theme, isFocused: isHoveringBackground, type: .secondary)
                        .onHover { hover in isHoveringBackground = hover }
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(16)
        }
        .frame(width: 420)
    }
}

// ==========================================
// 12. ABOUT HNAVIGATOR DIALOG
// ==========================================
public struct RetroAboutDialog: View {
    let theme: AppTheme
    let onClose: () -> Void
    
    @FocusState private var isOkFocused: Bool
    
    public var body: some View {
        RetroBox(title: "About hNavigator", theme: theme, isActive: true, doubleLine: true) {
            VStack(spacing: 16) {
                // Header / Title
                VStack(spacing: 4) {
                    Text("hNavigator")
                        .font(theme.font(size: 20, weight: .bold))
                        .foregroundColor(theme.glowColor)
                    
                    Text("File Manager for macOS")
                        .font(theme.font(size: 11))
                        .foregroundColor(theme.subtleTextColor)
                }
                .padding(.top, 8)
                
                Divider().background(theme.borderColor)
                
                // Body text (3 paragraphs)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("hNavigator is a free file manager that doesn't collect information about you, doesn't track you, doesn't push you to buy a subscription, doesn't show ads, and makes no claim on your money whatsoever. The goal of this app is to give macOS users a convenient, intuitive, and free tool that makes life simpler and easier.")
                            .font(theme.font(size: 12))
                            .foregroundColor(theme.textColor)
                            .lineSpacing(4)
                        
                        Text("This app was created as part of the [humaniaq project](https://humaniaq.com), whose main goal is to return people's humanity and make life easier.")
                            .font(theme.font(size: 12))
                            .foregroundColor(theme.textColor)
                            .lineSpacing(4)
                        
                        Text("If you'd like to support the project, you can donate a symbolic $1 on [Buy Me a Coffee](https://buymeacoffee.com/humaniaq).")
                            .font(theme.font(size: 12))
                            .foregroundColor(theme.textColor)
                            .lineSpacing(4)
                        
                        Divider().background(theme.borderColor.opacity(0.3))
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Legal & Compliance:")
                                .font(theme.font(size: 10, weight: .bold))
                                .foregroundColor(theme.glowColor)
                                .padding(.bottom, 2)
                            
                            HStack(spacing: 10) {
                                if let privacyUrl = URL(string: "https://humaniaq.notion.site/Privacy-policy-38fe92b23a9080be8b8be3c164bb58d5") {
                                    Link("Privacy Policy ↗", destination: privacyUrl)
                                        .font(theme.font(size: 10, weight: .bold))
                                        .foregroundColor(theme.textColor)
                                }
                                
                                Text("|")
                                    .font(theme.font(size: 10))
                                    .foregroundColor(theme.borderColor.opacity(0.3))
                                
                                if let termsUrl = URL(string: "https://humaniaq.notion.site/Terms-and-Conditions-3319975d885b495fac89a98f073bc2fb") {
                                    Link("Terms & Conditions ↗", destination: termsUrl)
                                        .font(theme.font(size: 10, weight: .bold))
                                        .foregroundColor(theme.textColor)
                                }
                                
                                Text("|")
                                    .font(theme.font(size: 10))
                                    .foregroundColor(theme.borderColor.opacity(0.3))
                                
                                if let supportUrl = URL(string: "https://humaniaq.notion.site/Support-38fe92b23a908055b69ad37cda9d3286") {
                                    Link("Support Desk ↗", destination: supportUrl)
                                        .font(theme.font(size: 10, weight: .bold))
                                        .foregroundColor(theme.textColor)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                
                Divider().background(theme.borderColor)
                
                // Close button
                Button(action: onClose) {
                    Text("   OK   ")
                        .retroButtonStyle(theme: theme, isFocused: isOkFocused, type: .primary)
                }
                .buttonStyle(PlainButtonStyle())
                .focusable()
                .focused($isOkFocused)
                .retroTooltip("Close About dialog", theme: theme)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 12)
        }
        .frame(width: 460, height: 350)
        .onAppear {
            isOkFocused = true
        }
        .onKeyPress { press in
            if press.key == .return || press.key == .escape || press.key == .space {
                onClose()
                return .handled
            }
            return .ignored
        }
    }
}

