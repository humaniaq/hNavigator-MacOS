import Foundation

public final class NetworkVFSProvider: VFSProvider, @unchecked Sendable {
    public let name = "Remote Server VFS"
    
    public init() {}
    
    // Path structure: sftp://[host]/[inner_path]
    // e.g. sftp://ftp.apple.com/pub/developer
    
    private func createTempConfig(url: String) -> URL? {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".curl")
        let escapedURL = url.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let content = "url = \"\(escapedURL)\"\n"
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            var attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            attrs[.posixPermissions] = 0o600
            try FileManager.default.setAttributes(attrs, ofItemAtPath: fileURL.path)
            return fileURL
        } catch {
            print("Failed to write secure curl config: \(error)")
            return nil
        }
    }

    private func executeCurl(arguments: [String], url: String? = nil, progress: ((Double) -> Void)? = nil) async throws -> Data {
        let task = Process()
        task.launchPath = "/usr/bin/curl"
        var args = arguments
        
        var tempConfigFile: URL? = nil
        if let url = url {
            if let configURL = createTempConfig(url: url) {
                tempConfigFile = configURL
                args.append(contentsOf: ["-K", configURL.path])
            } else {
                args.append(contentsOf: ["--", url])
            }
        }
        
        defer {
            if let temp = tempConfigFile {
                try? FileManager.default.removeItem(at: temp)
            }
        }
        
        if progress != nil {
            args.insert("-#", at: 0)
            args.removeAll { $0 == "-s" }
        } else if !args.contains("-s") {
            args.insert("-s", at: 0)
        }
        args.insert(contentsOf: ["--connect-timeout", "10", "-m", "120"], at: 0)
        
        task.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        
        try task.run()
        
        if let progress = progress {
            Task.detached {
                let handle = errPipe.fileHandleForReading
                var buffer = Data()
                do {
                    for try await byte in handle.bytes {
                        if byte == 13 || byte == 10 { // \r or \n
                            if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                                if let percentStr = line.components(separatedBy: CharacterSet.whitespaces).last(where: { $0.hasSuffix("%") }) {
                                    let clean = percentStr.replacingOccurrences(of: "%", with: "")
                                    if let val = Double(clean) {
                                        progress(val / 100.0)
                                    }
                                }
                            }
                            buffer.removeAll()
                        } else {
                            buffer.append(byte)
                        }
                    }
                } catch {
                    print("Error reading progress: \(error)")
                }
            }
        }
        
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            throw NSError(domain: "NetworkVFSProvider", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Network error (curl code \(task.terminationStatus))"])
        }
        return data
    }

    public func listDirectory(at path: String) async throws -> [VFSNode] {
        guard path.hasPrefix("sftp://") || path.hasPrefix("ftp://") || path.hasPrefix("webdav://") || path.hasPrefix("smb://") else {
            throw NSError(domain: "NetworkVFSProvider", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid network VFS path: \(path)"])
        }
        
        let listPath = path.hasSuffix("/") ? path : path + "/"
        var nodes: [VFSNode] = []
        
        let protocolScheme = path.components(separatedBy: "://").first ?? "sftp"
        let withoutScheme = path.replacingOccurrences(of: "\(protocolScheme)://", with: "")
        let components = withoutScheme.components(separatedBy: "/")
        let host = components.first ?? "remote.server"
        let innerPath = components.dropFirst().joined(separator: "/")
        
        if innerPath.isEmpty {
            nodes.append(VFSNode(
                name: ".. [Disconnect]",
                path: NSHomeDirectory(),
                size: 0,
                isDirectory: true,
                isSimulated: false
            ))
        } else {
            let parentInner = (innerPath as NSString).deletingLastPathComponent
            let parentPath = "\(protocolScheme)://\(host)/\(parentInner)"
            nodes.append(VFSNode(
                name: "..",
                path: parentInner.isEmpty ? "\(protocolScheme)://\(host)" : parentPath,
                size: 0,
                isDirectory: true,
                isSimulated: true
            ))
        }
        
        let data = try await executeCurl(arguments: [], url: listPath)
        if let output = String(data: data, encoding: .utf8) {
            let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            
            for line in lines {
                let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
                if parts.count >= 9 {
                    let perms = String(parts[0])
                    let nameStr = String(parts[8])
                    
                    let isDir = perms.hasPrefix("d")
                    let size = Int64(parts[4]) ?? 0
                    let isSymlink = perms.hasPrefix("l")
                    
                    if nameStr == "." || nameStr == ".." { continue }
                    
                    let finalName = isSymlink ? String(nameStr.split(separator: " -> ").first ?? "") : nameStr
                    if finalName.isEmpty { continue }
                    
                    let nodePath = path.hasSuffix("/") ? "\(path)\(finalName)" : "\(path)/\(finalName)"
                    nodes.append(VFSNode(
                        name: finalName,
                        path: nodePath,
                        size: size,
                        isDirectory: isDir,
                        isSimulated: true
                    ))
                } else if parts.count == 1 {
                    let nameStr = String(parts[0])
                    if nameStr == "." || nameStr == ".." { continue }
                    let isDir = !nameStr.contains(".") // Crude heuristic
                    let nodePath = path.hasSuffix("/") ? "\(path)\(nameStr)" : "\(path)/\(nameStr)"
                    nodes.append(VFSNode(
                        name: nameStr,
                        path: nodePath,
                        size: 0,
                        isDirectory: isDir,
                        isSimulated: true
                    ))
                }
            }
        }
        
        return nodes
    }
    
    public func copyItem(from src: String, to dst: String, progress: ((Double) -> Void)?) async throws {
        var finalDst = dst
        if dst.hasPrefix("/") {
            let srcName = src.components(separatedBy: "/").last ?? "downloaded_file"
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dst, isDirectory: &isDir), isDir.boolValue {
                finalDst = (dst as NSString).appendingPathComponent(srcName)
            }
            
            // Check if source is a directory by trying to list it
            var isSrcDir = src.hasSuffix("/")
            if !isSrcDir {
                if let _ = try? await listDirectory(at: src) {
                    isSrcDir = true
                }
            }
            if isSrcDir {
                try? FileManager.default.createDirectory(atPath: finalDst, withIntermediateDirectories: true)
                let nodes = try await listDirectory(at: src)
                for node in nodes where node.name != ".." && !node.name.hasPrefix(".. ") {
                    try await copyItem(from: node.path, to: finalDst, progress: progress)
                }
            } else {
                _ = try await executeCurl(arguments: ["-o", finalDst], url: src, progress: progress)
            }
        } else if src.hasPrefix("/") {
            var isSrcDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: src, isDirectory: &isSrcDir), isSrcDir.boolValue {
                let srcName = (src as NSString).lastPathComponent
                let newDst = dst.hasSuffix("/") ? dst + srcName : dst + "/" + srcName
                // curl cannot easily mkdir on FTP without a custom command. 
                // We'll just try to upload the contents to the new path.
                let contents = try FileManager.default.contentsOfDirectory(atPath: src)
                for item in contents {
                    let s = (src as NSString).appendingPathComponent(item)
                    try await copyItem(from: s, to: newDst, progress: progress)
                }
            } else {
                _ = try await executeCurl(arguments: ["-T", src], url: dst, progress: progress)
            }
        } else {
            throw NSError(domain: "NetworkVFSProvider", code: 400, userInfo: [NSLocalizedDescriptionKey: "Remote to remote copy not supported via curl wrapper"])
        }
    }
    
    public func moveItem(from src: String, to dst: String) async throws {
        throw NSError(domain: "NetworkVFSProvider", code: 405, userInfo: [NSLocalizedDescriptionKey: "Remote move not supported via curl wrapper"])
    }
    
    public func deleteItem(at path: String) async throws {
        throw NSError(domain: "NetworkVFSProvider", code: 405, userInfo: [NSLocalizedDescriptionKey: "Remote delete not supported via curl wrapper"])
    }
    
    public func createDirectory(at path: String) async throws {
        throw NSError(domain: "NetworkVFSProvider", code: 405, userInfo: [NSLocalizedDescriptionKey: "Remote mkdir not supported via curl wrapper"])
    }
    
    public func exists(at path: String) async throws -> Bool {
        return true
    }
    
    public func getFileContent(at path: String) async throws -> Data {
        return try await executeCurl(arguments: ["-s"], url: path)
    }
    
    public func writeFileContent(at path: String, data: Data) async throws {
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try data.write(to: tempUrl)
        defer { try? FileManager.default.removeItem(at: tempUrl) }
        _ = try await executeCurl(arguments: ["-s", "-T", tempUrl.path], url: path)
    }
}
