import XCTest
@testable import hNavigator

final class ThemeManagerTests: XCTestCase {
    func testAppThemeCount() throws {
        XCTAssertEqual(AppTheme.allCases.count, 6)
    }
    
    func testThemeColors() throws {
        let classicTheme = AppTheme.classicBlue
        XCTAssertEqual(classicTheme.rawValue, "Classic Blue")
        XCTAssertEqual(classicTheme.fontName, "Courier")
        XCTAssertEqual(classicTheme.usesBlur, false)
        
        let glassProTheme = AppTheme.glassPro
        XCTAssertEqual(glassProTheme.usesBlur, true)
    }

    func testThemeManagerSelection() throws {
        let manager = ThemeManager()
        manager.selectTheme(.arctic)
        XCTAssertEqual(manager.currentTheme, .arctic)
        manager.selectTheme(.retroDark)
        XCTAssertEqual(manager.currentTheme, .retroDark)
    }
}

final class LocalVFSProviderTests: XCTestCase {
    var vfs: LocalVFSProvider!
    var tempDirectory: URL!

    override func setUpWithError() throws {
        vfs = LocalVFSProvider()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testCreateAndListDirectory() async throws {
        let newDirPath = tempDirectory.appendingPathComponent("TestDir").path
        try await vfs.createDirectory(at: newDirPath)
        
        let exists = try await vfs.exists(at: newDirPath)
        XCTAssertTrue(exists)
        
        let nodes = try await vfs.listDirectory(at: tempDirectory.path)
        XCTAssertTrue(nodes.contains { $0.name == "TestDir" && $0.isDirectory })
    }

    func testWriteAndReadFileContent() async throws {
        let filePath = tempDirectory.appendingPathComponent("test.txt").path
        let testString = "Hello, VFS!"
        let data = testString.data(using: .utf8)!
        
        try await vfs.writeFileContent(at: filePath, data: data)
        let exists = try await vfs.exists(at: filePath)
        XCTAssertTrue(exists)
        
        let readData = try await vfs.getFileContent(at: filePath)
        let readString = String(data: readData, encoding: .utf8)
        XCTAssertEqual(readString, testString)
    }
    
    func testCopyFile() async throws {
        let srcPath = tempDirectory.appendingPathComponent("src.txt").path
        let dstPath = tempDirectory.appendingPathComponent("dst.txt").path
        let data = "copy test".data(using: .utf8)!
        
        try await vfs.writeFileContent(at: srcPath, data: data)
        try await vfs.copyItem(from: srcPath, to: dstPath, progress: nil)
        
        let exists = try await vfs.exists(at: dstPath)
        XCTAssertTrue(exists)
        
        let readData = try await vfs.getFileContent(at: dstPath)
        XCTAssertEqual(readData, data)
    }
    
    func testMoveFile() async throws {
        let srcPath = tempDirectory.appendingPathComponent("move_src.txt").path
        let dstPath = tempDirectory.appendingPathComponent("move_dst.txt").path
        let data = "move test".data(using: .utf8)!
        
        try await vfs.writeFileContent(at: srcPath, data: data)
        try await vfs.moveItem(from: srcPath, to: dstPath)
        
        let srcExists = try await vfs.exists(at: srcPath)
        let dstExists = try await vfs.exists(at: dstPath)
        
        XCTAssertFalse(srcExists)
        XCTAssertTrue(dstExists)
    }
    
    func testDeleteFile() async throws {
        let filePath = tempDirectory.appendingPathComponent("delete.txt").path
        try await vfs.writeFileContent(at: filePath, data: "to be deleted".data(using: .utf8)!)
        
        var exists = try await vfs.exists(at: filePath)
        XCTAssertTrue(exists)
        
        try await vfs.deleteItem(at: filePath)
        
        exists = try await vfs.exists(at: filePath)
        XCTAssertFalse(exists)
    }
}

final class ArchiveVFSProviderTests: XCTestCase {
    var vfs: ArchiveVFSProvider!
    var tempDirectory: URL!
    var zipFileURL: URL!

    override func setUpWithError() throws {
        vfs = ArchiveVFSProvider()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create a dummy file
        let dummyFileURL = tempDirectory.appendingPathComponent("dummy.txt")
        try "test data".write(to: dummyFileURL, atomically: true, encoding: .utf8)
        
        // Create a zip archive using Process
        zipFileURL = tempDirectory.appendingPathComponent("archive.zip")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        task.currentDirectoryURL = tempDirectory
        task.arguments = ["-r", zipFileURL.path, "dummy.txt"]
        try task.run()
        task.waitUntilExit()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testListDirectory() async throws {
        let path = "archive://\(zipFileURL.path)::/"
        let nodes = try await vfs.listDirectory(at: path)
        
        XCTAssertTrue(nodes.contains { $0.name == "dummy.txt" })
    }

    func testGetFileContent() async throws {
        let path = "archive://\(zipFileURL.path)::/dummy.txt"
        let data = try await vfs.getFileContent(at: path)
        let str = String(data: data, encoding: .utf8)
        XCTAssertEqual(str, "test data")
    }
}

final class NetworkVFSProviderTests: XCTestCase {
    var vfs: NetworkVFSProvider!

    override func setUpWithError() throws {
        vfs = NetworkVFSProvider()
    }

    func testInvalidPath() async {
        do {
            _ = try await vfs.listDirectory(at: "invalid://server")
            XCTFail("Should throw error for invalid path")
        } catch {
            XCTAssertTrue(error is NSError)
        }
    }
}

@MainActor
final class PanelStateTests: XCTestCase {
    func testPanelStateInitialization() {
        let panel = PanelState(initialPath: "/tmp", key: "testPanel")
        XCTAssertEqual(panel.files.count, 0)
        XCTAssertEqual(panel.selectedIndices.count, 0)
    }
    
    func testFilterFiles() {
        let panel = PanelState(initialPath: "/", key: "testPanel")
        
        let node1 = VFSNode(name: "FileA.txt", path: "/FileA.txt", size: 100, isDirectory: false)
        let node2 = VFSNode(name: "FileB.txt", path: "/FileB.txt", size: 100, isDirectory: false)
        let node3 = VFSNode(name: "FolderC", path: "/FolderC", size: 0, isDirectory: true)
        
        panel.files = [node1, node2, node3]
        panel.showHiddenFiles = true
        panel.isFilterActive = true
        panel.filterText = "File"
        
        let filtered = panel.filteredFiles
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.name == "FileA.txt" })
        XCTAssertTrue(filtered.contains { $0.name == "FileB.txt" })
        
        panel.filterText = "Folder"
        let filteredFolder = panel.filteredFiles
        XCTAssertEqual(filteredFolder.count, 1)
        XCTAssertEqual(filteredFolder.first?.name, "FolderC")
    }
}
