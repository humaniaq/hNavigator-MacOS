import Foundation
import Dispatch

public final class FileSystemWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.humaniaq.hNavigator.fswatcher", attributes: .concurrent)
    
    public var onChange: (() -> Void)?
    
    public init() {}
    
    public func start(url: URL) {
        stop()
        
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }
        
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .link, .rename, .delete, .extend, .attrib],
            queue: queue
        )
        
        source?.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        
        let fd = fileDescriptor
        source?.setCancelHandler { [weak self] in
            close(fd)
            self?.fileDescriptor = -1
        }
        
        source?.resume()
    }
    
    public func stop() {
        if let source = source {
            source.cancel()
            self.source = nil
        }
    }
    
    deinit {
        stop()
    }
}
