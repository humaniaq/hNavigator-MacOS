import Foundation

public final class LocalVFSProvider: VFSProvider, @unchecked Sendable {
    public let name = "Local Filesystem"
    private let fileManager = FileManager.default
    
    public init() {}
    
    private func cleanPath(_ path: String) -> String {
        var p = path
        if p.hasPrefix("~") {
            p = (p as NSString).expandingTildeInPath
        }
        if p.isEmpty {
            p = "/"
        }
        return (p as NSString).standardizingPath
    }
    
    public func listDirectory(at path: String) async throws -> [VFSNode] {
        let absolutePath = cleanPath(path)
        let url = URL(fileURLWithPath: absolutePath)
        
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: absolutePath, isDirectory: &isDir) else {
            throw NSError(domain: "LocalVFSProvider", code: 404, userInfo: [NSLocalizedDescriptionKey: "Directory not found: \(absolutePath)"])
        }
        
        guard isDir.boolValue else {
            throw NSError(domain: "LocalVFSProvider", code: 400, userInfo: [NSLocalizedDescriptionKey: "Path is not a directory: \(absolutePath)"])
        }
        
        var contents: [URL] = []
        do {
            contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [
                .isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey
            ], options: [])
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                let resolvedURL = await withCheckedContinuation { continuation in
                    SecurityScopedBookmarkManager.shared.requestAccess(for: url) { resolved in
                        continuation.resume(returning: resolved)
                    }
                }
                
                if let resolved = resolvedURL {
                    defer { SecurityScopedBookmarkManager.shared.stopAccess(for: resolved) }
                    contents = try fileManager.contentsOfDirectory(at: resolved, includingPropertiesForKeys: [
                        .isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey
                    ], options: [])
                } else {
                    throw NSError(domain: "LocalVFSProvider", code: 403, userInfo: [NSLocalizedDescriptionKey: "Permission Denied: Please grant 'Full Disk Access' to hNavigator or select the folder in the prompt."])
                }
            } else {
                throw error
            }
        }
        
        var nodes: [VFSNode] = []
        
        // Add special parent directory item if not at root "/"
        if absolutePath != "/" {
            let parentPath = (absolutePath as NSString).deletingLastPathComponent
            nodes.append(VFSNode(
                name: "..",
                path: parentPath.isEmpty ? "/" : parentPath,
                size: 0,
                isDirectory: true,
                isSimulated: false
            ))
        }
        
        for itemURL in contents {
            let name = itemURL.lastPathComponent
            let itemPath = itemURL.path
            
            // Skip hidden system files that clutter DOS Navigator retro look unless requested, but let's show them if they start with a dot or skip .DS_Store
            if name == ".DS_Store" { continue }
            
            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey])
            let isDirectory = resourceValues.isDirectory ?? false
            let size = Int64(resourceValues.fileSize ?? 0)
            let creation = resourceValues.creationDate ?? Date()
            let modification = resourceValues.contentModificationDate ?? Date()
            
            nodes.append(VFSNode(
                name: name,
                path: itemPath,
                size: size,
                isDirectory: isDirectory,
                creationDate: creation,
                modificationDate: modification,
                isSimulated: false
            ))
        }
        
        // Sort: directories first, then files (alphabetically)
        return nodes.sorted { (a, b) -> Bool in
            if a.name == ".." { return true }
            if b.name == ".." { return false }
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    
    public func copyItem(from src: String, to dst: String, progress: ((Double) -> Void)?) async throws {
        let srcPath = cleanPath(src)
        var dstPath = cleanPath(dst)
        
        // If destination is a directory, append the source file name
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: dstPath, isDirectory: &isDir), isDir.boolValue {
            let fileName = (srcPath as NSString).lastPathComponent
            dstPath = (dstPath as NSString).appendingPathComponent(fileName)
        }
        
        var srcIsDir: ObjCBool = false
        guard fileManager.fileExists(atPath: srcPath, isDirectory: &srcIsDir) else {
            throw CocoaError(.fileNoSuchFile)
        }
        
        if srcIsDir.boolValue {
            try fileManager.createDirectory(atPath: dstPath, withIntermediateDirectories: true)
            let contents = try fileManager.contentsOfDirectory(atPath: srcPath)
            for item in contents {
                let s = (srcPath as NSString).appendingPathComponent(item)
                let d = (dstPath as NSString).appendingPathComponent(item)
                try await copyItem(from: s, to: d, progress: progress)
            }
        } else {
            guard let attrs = try? fileManager.attributesOfItem(atPath: srcPath), let size = attrs[.size] as? UInt64, size > 0 else {
                try fileManager.copyItem(atPath: srcPath, toPath: dstPath)
                progress?(1.0)
                return
            }
            let inFile = try FileHandle(forReadingFrom: URL(fileURLWithPath: srcPath))
            fileManager.createFile(atPath: dstPath, contents: nil, attributes: nil)
            let outFile = try FileHandle(forWritingTo: URL(fileURLWithPath: dstPath))
            defer {
                try? inFile.close()
                try? outFile.close()
            }
            var copied: UInt64 = 0
            let chunkSize = 1024 * 1024 // 1 MB chunks
            while true {
                guard let data = try inFile.read(upToCount: chunkSize), !data.isEmpty else { break }
                try outFile.write(contentsOf: data)
                copied += UInt64(data.count)
                progress?(Double(copied) / Double(size))
                try await Task.sleep(nanoseconds: 10_000_000) // Yield to UI thread
            }
        }
    }
    
    public func moveItem(from src: String, to dst: String) async throws {
        let srcPath = cleanPath(src)
        var dstPath = cleanPath(dst)
        
        // If destination is a directory, append the source file name
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: dstPath, isDirectory: &isDir), isDir.boolValue {
            let fileName = (srcPath as NSString).lastPathComponent
            dstPath = (dstPath as NSString).appendingPathComponent(fileName)
        }
        
        try fileManager.moveItem(atPath: srcPath, toPath: dstPath)
    }
    
    public func deleteItem(at path: String) async throws {
        let absolutePath = cleanPath(path)
        try fileManager.removeItem(atPath: absolutePath)
    }
    
    public func createDirectory(at path: String) async throws {
        let absolutePath = cleanPath(path)
        try fileManager.createDirectory(atPath: absolutePath, withIntermediateDirectories: true, attributes: nil)
    }
    
    public func exists(at path: String) async throws -> Bool {
        return fileManager.fileExists(atPath: cleanPath(path))
    }
    
    public func getFileContent(at path: String) async throws -> Data {
        let absolutePath = cleanPath(path)
        return try Data(contentsOf: URL(fileURLWithPath: absolutePath))
    }
    
    public func getFileContent(at path: String, offset: UInt64, length: Int) async throws -> Data {
        let absolutePath = cleanPath(path)
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: absolutePath))
        defer { try? handle.close() }
        
        try handle.seek(toOffset: offset)
        if let data = try handle.read(upToCount: length) {
            return data
        }
        return Data()
    }
    
    public func writeFileContent(at path: String, data: Data) async throws {
        let absolutePath = cleanPath(path)
        try data.write(to: URL(fileURLWithPath: absolutePath), options: .atomic)
    }
}
