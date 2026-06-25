import SwiftUI

public struct RetroViewerModal: View {
    let filePath: String
    let provider: any VFSProvider
    let theme: AppTheme
    let onClose: () -> Void
    
    @State private var isHexMode = false
    @State private var textContent = ""
    @State private var hexDump = ""
    @State private var isLoading = true
    @State private var errorText = ""
    
    @State private var offset: UInt64 = 0
    let chunkSize: Int = 65536 // 64 KB
    @State private var hasMoreData = false
    
    @FocusState private var focusedField: FocusField?
    
    enum FocusField: Hashable {
        case hexToggle
        case prevPage
        case nextPage
        case close
    }
    
    private func cycleFocus(forward: Bool) {
        let fields: [FocusField] = [.hexToggle, .prevPage, .nextPage, .close]
        guard let current = focusedField, let idx = fields.firstIndex(of: current) else {
            focusedField = .close
            return
        }
        let nextIdx = (idx + (forward ? 1 : fields.count - 1)) % fields.count
        focusedField = fields[nextIdx]
    }
    
    @MainActor
    private func loadContent() {
        isLoading = true
        Task {
            do {
                let data = try await provider.getFileContent(at: filePath, offset: offset, length: chunkSize)
                
                hasMoreData = data.count == chunkSize
                
                // Set Text Content
                if let text = String(data: data, encoding: .utf8) {
                    textContent = text
                } else {
                    textContent = "[Binary Data - Use HEX mode to view]"
                }
                
                // Generate Hex Dump
                hexDump = generateHexDump(data, baseOffset: offset)
                
            } catch {
                errorText = "Error reading file:\n\(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    private func generateHexDump(_ data: Data, baseOffset: UInt64) -> String {
        var lines: [String] = []
        let bytesPerLine = 16
        
        for i in stride(from: 0, to: data.count, by: bytesPerLine) {
            let chunk = data.subdata(in: i..<min(i + bytesPerLine, data.count))
            
            // Offset
            let offsetStr = String(format: "%08llX", baseOffset + UInt64(i))
            
            // Hex bytes
            var hexBytes: [String] = []
            for b in chunk {
                hexBytes.append(String(format: "%02X", b))
            }
            while hexBytes.count < bytesPerLine {
                hexBytes.append("  ")
            }
            let hexStr = hexBytes.joined(separator: " ")
            
            // ASCII printable
            var asciiChars = ""
            for b in chunk {
                if b >= 32 && b <= 126 {
                    asciiChars.append(Character(UnicodeScalar(b)))
                } else {
                    asciiChars.append(".")
                }
            }
            
            lines.append("\(offsetStr)  \(hexStr)  |\(asciiChars)|")
        }
        
        return lines.isEmpty ? "Empty file" : lines.joined(separator: "\n")
    }
    
    public var body: some View {
        RetroBox(title: "F3 Viewer: \((filePath as NSString).lastPathComponent)", theme: theme, isActive: true, doubleLine: true) {
            VStack(spacing: 8) {
                // Header Toolbar
                HStack {
                    Button(action: { isHexMode.toggle() }) {
                        Text(isHexMode ? "Switch to Text Mode" : "Switch to Hex Mode")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .hexToggle, type: .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .hexToggle)
                    .retroTooltip("Toggle Hex/Text viewer mode", theme: theme)
                    
                    Spacer()
                    
                    Button(action: {
                        if offset >= UInt64(chunkSize) {
                            offset -= UInt64(chunkSize)
                            loadContent()
                        }
                    }) {
                        Text("Prev Page")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .prevPage, type: .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(offset == 0)
                    .focusable()
                    .focused($focusedField, equals: .prevPage)
                    
                    Button(action: {
                        if hasMoreData {
                            offset += UInt64(chunkSize)
                            loadContent()
                        }
                    }) {
                        Text("Next Page")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .nextPage, type: .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!hasMoreData)
                    .focusable()
                    .focused($focusedField, equals: .nextPage)
                    
                    Spacer()
                    
                    Text("Esc to Close")
                        .font(theme.font(size: 12))
                        .foregroundColor(theme.borderColor)
                }
                
                Divider().background(theme.borderColor)
                
                // File Content
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if !errorText.isEmpty {
                    Spacer()
                    Text(errorText)
                        .foregroundColor(.red)
                        .font(theme.font(size: 14))
                        .multilineTextAlignment(.center)
                    Spacer()
                } else {
                    ScrollView {
                        Text(isHexMode ? hexDump : textContent)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(theme.textColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .padding(4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
                }
                
                Divider().background(theme.borderColor)
                
                // Bottom control help
                HStack {
                    Button(action: onClose) {
                        Text("Close [Esc]")
                            .retroButtonStyle(theme: theme, isFocused: focusedField == .close, type: .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable()
                    .focused($focusedField, equals: .close)
                    .retroTooltip("Close viewer (Esc)", theme: theme)
                }
            }
        }
        .frame(width: 800, height: 500)
        .onAppear {
            focusedField = .close
            loadContent()
        }
        .onKeyPress { press in
            if press.key == .tab {
                cycleFocus(forward: true)
                return .handled
            } else if press.key == .leftArrow || press.key == .upArrow || press.key == .rightArrow || press.key == .downArrow {
                cycleFocus(forward: true)
                return .handled
            } else if press.key == .return {
                if focusedField == .hexToggle {
                    isHexMode.toggle()
                } else if focusedField == .prevPage {
                    if offset >= UInt64(chunkSize) { offset -= UInt64(chunkSize); loadContent() }
                } else if focusedField == .nextPage {
                    if hasMoreData { offset += UInt64(chunkSize); loadContent() }
                } else {
                    onClose()
                }
                return .handled
            } else if press.key == .escape {
                onClose()
                return .handled
            }
            return .ignored
        }
    }
}
