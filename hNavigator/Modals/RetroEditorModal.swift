import SwiftUI

public struct RetroEditorModal: View {
    let filePath: String
    let provider: any VFSProvider
    let theme: AppTheme
    let onClose: () -> Void
    let onSave: () -> Void
    
    @State private var text = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorText = ""
    @State private var successText = ""
    
    // Find & Replace additions
    @State private var showSearchReplace = false
    @State private var searchPattern = ""
    @State private var replacePattern = ""
    @State private var selectedMatchIndex = -1
    
    @FocusState private var focusedField: FocusField?
    
    enum FocusField: Hashable {
        case textEditor
        case searchField
        case replaceField
    }
    
    private var searchMatches: [Range<String.Index>] {
        guard !searchPattern.isEmpty else { return [] }
        var matches: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: searchPattern, options: .caseInsensitive, range: start..<text.endIndex) {
            matches.append(range)
            if range.lowerBound == range.upperBound {
                start = text.index(after: start)
            } else {
                start = range.upperBound
            }
        }
        return matches
    }
    
    private func findNext() {
        let matches = searchMatches
        guard !matches.isEmpty else {
            selectedMatchIndex = -1
            return
        }
        selectedMatchIndex = (selectedMatchIndex + 1) % matches.count
    }
    
    private func replaceCurrent() {
        let matches = searchMatches
        guard !matches.isEmpty else { return }
        if selectedMatchIndex < 0 || selectedMatchIndex >= matches.count {
            selectedMatchIndex = 0
        }
        let range = matches[selectedMatchIndex]
        text.replaceSubrange(range, with: replacePattern)
        
        // Recalculate matches
        let nextMatches = searchMatches
        if nextMatches.isEmpty {
            selectedMatchIndex = -1
        } else {
            selectedMatchIndex = min(selectedMatchIndex, nextMatches.count - 1)
        }
    }
    
    private func replaceAll() {
        text = text.replacingOccurrences(of: searchPattern, with: replacePattern, options: .caseInsensitive)
        selectedMatchIndex = -1
    }
    
    @MainActor
    private func loadContent() {
        isLoading = true
        Task {
            do {
                if try await provider.exists(at: filePath) {
                    let data = try await provider.getFileContent(at: filePath)
                    if let fileText = String(data: data, encoding: .utf8) {
                        text = fileText
                    } else {
                        text = ""
                        errorText = "File format could not be read as text."
                    }
                } else {
                    text = "" // New file creation
                }
            } catch {
                text = ""
                // Might be new file, let it go
            }
            isLoading = false
            focusedField = .textEditor
        }
    }
    
    @MainActor
    private func saveContent() {
        isSaving = true
        successText = ""
        errorText = ""
        
        Task {
            do {
                guard let data = text.data(using: .utf8) else {
                    throw NSError(domain: "RetroEditorModal", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid text characters"])
                }
                try await provider.writeFileContent(at: filePath, data: data)
                successText = "Saved successfully!"
                onSave()
                
                // Diminish status text after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    successText = ""
                }
            } catch {
                errorText = "Error saving file: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }
    
    public var body: some View {
        RetroBox(title: "F4 Editor: \((filePath as NSString).lastPathComponent)", theme: theme, isActive: true, doubleLine: true) {
            VStack(spacing: 8) {
                // Editor toolbar
                HStack {
                    Button(action: saveContent) {
                        Text("Save [Ctrl+S]")
                            .retroButtonStyle(theme: theme, isFocused: false, type: .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isSaving)
                    .keyboardShortcut("s", modifiers: .control)
                    .retroTooltip("Save file changes (Ctrl+S)", theme: theme)
                    
                    Button(action: {
                        showSearchReplace.toggle()
                        if showSearchReplace {
                            focusedField = .searchField
                        } else {
                            focusedField = .textEditor
                        }
                    }) {
                        Text("Find/Replace [Cmd+F]")
                            .retroButtonStyle(theme: theme, isFocused: false, type: .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut("f", modifiers: .command)
                    .retroTooltip("Toggle Search/Replace panel (Cmd+F)", theme: theme)
                    
                    if !successText.isEmpty {
                        Text(successText)
                            .font(theme.font(size: 12))
                            .foregroundColor(.green)
                    }
                    
                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(theme.font(size: 12))
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    Text("Esc to Exit")
                        .font(theme.font(size: 12))
                        .foregroundColor(theme.borderColor)
                }
                
                Divider().background(theme.borderColor)
                
                // Search & Replace Panel
                if showSearchReplace {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Find:")
                                .font(theme.font(size: 11))
                                .foregroundColor(theme.textColor)
                            TextField("Search pattern", text: $searchPattern)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(theme.font(size: 11))
                                .retroInputStyle(theme: theme, isFocused: focusedField == .searchField)
                                .frame(width: 150)
                                .focused($focusedField, equals: .searchField)
                            
                            Text("Replace:")
                                .font(theme.font(size: 11))
                                .foregroundColor(theme.textColor)
                            TextField("Replacement", text: $replacePattern)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(theme.font(size: 11))
                                .retroInputStyle(theme: theme, isFocused: focusedField == .replaceField)
                                .frame(width: 150)
                                .focused($focusedField, equals: .replaceField)
                            
                            Button(action: findNext) {
                                Text("Find Next")
                                    .retroButtonStyle(theme: theme, isFocused: false, type: .secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .retroTooltip("Find next match", theme: theme)
                            
                            Button(action: replaceCurrent) {
                                Text("Replace")
                                    .retroButtonStyle(theme: theme, isFocused: false, type: .secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .retroTooltip("Replace current match", theme: theme)
                            
                            Button(action: replaceAll) {
                                Text("Replace All")
                                    .retroButtonStyle(theme: theme, isFocused: false, type: .secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .retroTooltip("Replace all occurrences", theme: theme)
                            
                            Spacer()
                            
                            Button(action: { showSearchReplace = false }) {
                                Image(systemName: "xmark")
                                    .foregroundColor(theme.textColor)
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .retroTooltip("Close Search/Replace panel", theme: theme)
                        }
                        .padding(4)
                        .background(theme.borderColor.opacity(0.1))
                        
                        let matches = searchMatches
                        if !searchPattern.isEmpty {
                            HStack {
                                if matches.isEmpty {
                                    Text("No matches found")
                                        .font(theme.font(size: 10))
                                        .foregroundColor(.red)
                                } else {
                                    Text("Match \(selectedMatchIndex + 1) of \(matches.count)")
                                        .font(theme.font(size: 10))
                                        .foregroundColor(theme.glowColor)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
                
                // Text Area
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(theme.textColor)
                        .padding(4)
                        .background(Color.black.opacity(0.1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .focused($focusedField, equals: .textEditor)
                }
                
                Divider().background(theme.borderColor)
                
                // Footer details
                HStack {
                    let chars = text.count
                    let lines = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
                    let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
                    
                    Text("Lines: \(lines) | Chars: \(chars) | Words: \(words)")
                        .font(theme.font(size: 11))
                        .foregroundColor(theme.borderColor)
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: saveContent) {
                            Text("Save")
                                .retroButtonStyle(theme: theme, isFocused: false, type: .primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .retroTooltip("Save changes", theme: theme)
                        
                        Button(action: onClose) {
                            Text("Close")
                                .retroButtonStyle(theme: theme, isFocused: false, type: .secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .retroTooltip("Close editor (Esc)", theme: theme)
                    }
                }
            }
        }
        .frame(width: 800, height: 500)
        .onAppear {
            loadContent()
        }
        .onKeyPress { press in
            if press.key == .tab {
                if focusedField == .searchField {
                    focusedField = .replaceField
                    return .handled
                } else if focusedField == .replaceField {
                    focusedField = .textEditor
                    return .handled
                }
            } else if press.key == .escape {
                onClose()
                return .handled
            }
            return .ignored
        }
    }
}
