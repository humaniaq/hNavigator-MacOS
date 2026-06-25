import Foundation
import AppKit

public final class SecurityScopedBookmarkManager: @unchecked Sendable {
    public static let shared = SecurityScopedBookmarkManager()
    private let userDefaultsKey = "hNavigator.securityBookmarks"
    
    private var bookmarks: [URL: Data] = [:]
    
    private init() {
        loadBookmarks()
    }
    
    private func loadBookmarks() {
        if let data = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Data] {
            var loaded: [URL: Data] = [:]
            for (key, value) in data {
                if let url = URL(string: key) {
                    loaded[url] = value
                }
            }
            bookmarks = loaded
        }
    }
    
    private func saveBookmarks() {
        var dict: [String: Data] = [:]
        for (url, data) in bookmarks {
            dict[url.absoluteString] = data
        }
        UserDefaults.standard.set(dict, forKey: userDefaultsKey)
    }
    
    public func requestAccess(for url: URL, completion: @escaping (URL?) -> Void) {
        if let bookmarkData = bookmarks[url] {
            var isStale = false
            do {
                let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale {
                    storeBookmark(for: resolvedURL)
                }
                if resolvedURL.startAccessingSecurityScopedResource() {
                    completion(resolvedURL)
                    return
                }
            } catch {
                print("Failed to resolve bookmark: \(error)")
            }
        }
        
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.message = "Please grant access to \(url.lastPathComponent) to continue."
            panel.directoryURL = url
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            
            panel.begin { response in
                if response == .OK, let selectedURL = panel.url {
                    self.storeBookmark(for: selectedURL)
                    if selectedURL.startAccessingSecurityScopedResource() {
                        completion(selectedURL)
                    } else {
                        completion(nil)
                    }
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    private func storeBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            bookmarks[url] = data
            saveBookmarks()
        } catch {
            print("Failed to create security-scoped bookmark: \(error)")
        }
    }
    
    public func stopAccess(for url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
