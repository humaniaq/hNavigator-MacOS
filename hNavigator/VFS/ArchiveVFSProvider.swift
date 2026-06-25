import Foundation
import ZIPFoundation

public final class ArchiveVFSProvider: VFSProvider, @unchecked Sendable {
    public let name = "Archive Browser"
    
    public init() {}
    
    public func listDirectory(at path: String) async throws -> [VFSNode] {
        guard path.hasPrefix("archive://") else {
            throw NSError(domain: "ArchiveVFSProvider", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid archive VFS path: \(path)"])
        }
        
        let components = path.replacingOccurrences(of: "archive://", with: "").components(separatedBy: "::/")
        guard !components.isEmpty else {
            throw NSError(domain: "ArchiveVFSProvider", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid archive path format"])
        }
        
        let archiveLocalPath = components[0]
        let innerPath = components.count > 1 ? components[1] : ""
        let innerPathPrefix = innerPath.isEmpty ? "" : innerPath + (innerPath.hasSuffix("/") ? "" : "/")
        
        guard let archive = Archive(url: URL(fileURLWithPath: archiveLocalPath), accessMode: .read) else {
            throw NSError(domain: "ArchiveVFSProvider", code: 404, userInfo: [NSLocalizedDescriptionKey: "Archive not found or invalid"])
        }
        
        var nodes: [VFSNode] = []
        
        if innerPath.isEmpty {
            let parentLocalFolder = (archiveLocalPath as NSString).deletingLastPathComponent
            nodes.append(VFSNode(
                name: ".. [Exit Archive]",
                path: parentLocalFolder.isEmpty ? "/" : parentLocalFolder,
                size: 0,
                isDirectory: true,
                isSimulated: false
            ))
        } else {
            let innerParent = (innerPath as NSString).deletingLastPathComponent
            let parentVFSPath = "archive://\(archiveLocalPath)::/\(innerParent)"
            nodes.append(VFSNode(
                name: "..",
                path: parentVFSPath == "archive://\(archiveLocalPath)::/" ? "archive://\(archiveLocalPath)" : parentVFSPath,
                size: 0,
                isDirectory: true,
                isSimulated: true
            ))
        }
        
        var children = Set<String>()
        var directoryNames = Set<String>()
        var fileSizes: [String: Int64] = [:]
        
        for entry in archive {
            let p = entry.path
            if p.hasPrefix(innerPathPrefix) {
                let remainder = p.dropFirst(innerPathPrefix.count)
                if !remainder.isEmpty {
                    let parts = remainder.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                    if let firstPart = parts.first {
                        let name = String(firstPart)
                        if !name.isEmpty {
                            children.insert(name)
                            if parts.count > 1 || entry.type == .directory {
                                directoryNames.insert(name)
                            }
                            if entry.type == .file && parts.count == 1 {
                                fileSizes[name] = Int64(entry.uncompressedSize)
                            }
                        }
                    }
                }
            }
        }
        
        for name in Array(children).sorted() {
            let isDir = directoryNames.contains(name)
            let nodePath = innerPath.isEmpty ? name : "\(innerPath)/\(name)"
            nodes.append(VFSNode(
                name: name,
                path: "archive://\(archiveLocalPath)::/\(nodePath)",
                size: fileSizes[name] ?? 0,
                isDirectory: isDir,
                isSimulated: true
            ))
        }
        
        return nodes
    }
    
    public func copyItem(from src: String, to dst: String, progress: ((Double) -> Void)?) async throws {
        if dst.hasPrefix("/") {
            let components = src.replacingOccurrences(of: "archive://", with: "").components(separatedBy: "::/")
            guard components.count > 1 else { return }
            let innerPath = components[1]
            
            let srcName = innerPath.components(separatedBy: "/").last ?? "extracted_file"
            let finalDst = (dst as NSString).appendingPathComponent(srcName)
            
            let data = try await getFileContent(at: src)
            try data.write(to: URL(fileURLWithPath: finalDst), options: .atomic)
        }
    }
    
    public func moveItem(from src: String, to dst: String) async throws {
        throw NSError(domain: "ArchiveVFSProvider", code: 405, userInfo: [NSLocalizedDescriptionKey: "Archives are read-only in this version"])
    }
    
    public func deleteItem(at path: String) async throws {
        throw NSError(domain: "ArchiveVFSProvider", code: 405, userInfo: [NSLocalizedDescriptionKey: "Archives are read-only in this version"])
    }
    
    public func createDirectory(at path: String) async throws {
        throw NSError(domain: "ArchiveVFSProvider", code: 405, userInfo: [NSLocalizedDescriptionKey: "Archives are read-only in this version"])
    }
    
    public func exists(at path: String) async throws -> Bool {
        return true
    }
    
    private struct ExtractionInterruptError: Error {}

    public func getFileContent(at path: String, offset: UInt64, length: Int) async throws -> Data {
        let components = path.replacingOccurrences(of: "archive://", with: "").components(separatedBy: "::/")
        guard components.count > 1 else { return Data() }
        let archiveLocalPath = components[0]
        let innerPath = components[1]
        
        guard let archive = Archive(url: URL(fileURLWithPath: archiveLocalPath), accessMode: .read) else {
            throw NSError(domain: "ArchiveVFSProvider", code: 404, userInfo: [NSLocalizedDescriptionKey: "Archive not found"])
        }
        
        guard let entry = archive[innerPath] else {
            throw NSError(domain: "ArchiveVFSProvider", code: 404, userInfo: [NSLocalizedDescriptionKey: "Entry not found in archive"])
        }
        
        var result = Data()
        var bytesRead: UInt64 = 0
        
        do {
            _ = try archive.extract(entry, consumer: { chunk in
                let chunkStart = bytesRead
                let chunkEnd = bytesRead + UInt64(chunk.count)
                
                let targetStart = offset
                let targetEnd = offset + UInt64(length)
                
                if chunkEnd > targetStart && chunkStart < targetEnd {
                    let intersectionStart = max(chunkStart, targetStart)
                    let intersectionEnd = min(chunkEnd, targetEnd)
                    
                    let localStart = Int(intersectionStart - chunkStart)
                    let localEnd = Int(intersectionEnd - chunkStart)
                    
                    result.append(chunk.subdata(in: localStart..<localEnd))
                }
                
                bytesRead += UInt64(chunk.count)
                
                if bytesRead >= targetEnd {
                    throw ExtractionInterruptError()
                }
            })
        } catch is ExtractionInterruptError {
            // Early exit on success
        } catch {
            throw error
        }
        
        return result
    }

    public func getFileContent(at path: String) async throws -> Data {
        let components = path.replacingOccurrences(of: "archive://", with: "").components(separatedBy: "::/")
        guard components.count > 1 else { return Data() }
        let archiveLocalPath = components[0]
        let innerPath = components[1]
        
        guard let archive = Archive(url: URL(fileURLWithPath: archiveLocalPath), accessMode: .read) else {
            throw NSError(domain: "ArchiveVFSProvider", code: 404, userInfo: [NSLocalizedDescriptionKey: "Archive not found"])
        }
        
        guard let entry = archive[innerPath] else {
            throw NSError(domain: "ArchiveVFSProvider", code: 404, userInfo: [NSLocalizedDescriptionKey: "Entry not found in archive"])
        }
        
        var data = Data()
        _ = try archive.extract(entry, consumer: { chunk in
            data.append(chunk)
        })
        
        return data
    }
    
    public func writeFileContent(at path: String, data: Data) async throws {
        throw NSError(domain: "ArchiveVFSProvider", code: 405, userInfo: [NSLocalizedDescriptionKey: "Archives are read-only in this version"])
    }
}
