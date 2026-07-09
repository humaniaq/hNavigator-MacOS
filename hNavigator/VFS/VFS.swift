import Foundation

public struct VFSNode: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let path: String
    public let size: Int64
    public let isDirectory: Bool
    public let creationDate: Date
    public let modificationDate: Date
    public let isSimulated: Bool
    
    public init(id: UUID = UUID(), name: String, path: String, size: Int64, isDirectory: Bool, creationDate: Date = Date(), modificationDate: Date = Date(), isSimulated: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.isSimulated = isSimulated
    }
}

public protocol VFSProvider: Sendable {
    var name: String { get }
    func listDirectory(at path: String) async throws -> [VFSNode]
    func copyItem(from src: String, to dst: String, progress: ((Double, Int64) -> Void)?) async throws
    func moveItem(from src: String, to dst: String) async throws
    func deleteItem(at path: String) async throws
    func createDirectory(at path: String) async throws
    func exists(at path: String) async throws -> Bool
    func getFileContent(at path: String) async throws -> Data
    func getFileContent(at path: String, offset: UInt64, length: Int) async throws -> Data
    func writeFileContent(at path: String, data: Data) async throws
}

extension VFSProvider {
    public func getFileContent(at path: String, offset: UInt64, length: Int) async throws -> Data {
        let fullData = try await getFileContent(at: path)
        let end = min(Int(offset) + length, fullData.count)
        guard Int(offset) < end else { return Data() }
        return fullData.subdata(in: Int(offset)..<end)
    }
}
