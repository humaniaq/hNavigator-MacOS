# 🍎 hNavigator

A fast, modern, dual-panel file manager for macOS built completely with **SwiftUI**. 
Inspired by the legendary Norton Commander and Far Manager, but designed with the power of modern macOS APIs.

![App Screenshot](https://raw.githubusercontent.com/pinskiy/hNavigator/main/.github/screenshot.png)

## ✨ Features

- **Dual-Panel Interface**: Classic two-pane view for blazing fast file operations.
- **Native SwiftUI**: Extremely lightweight, fast, and responsive. Built with 100% native macOS components.
- **VFS (Virtual File System) Support**:
  - Local Filesystem navigation.
  - Network drives (SMB/AFP) support.
  - Archive browsing (read/extract ZIP, TAR directly from the interface).
- **Full Disk Access**: Unsandboxed for complete control over your file system (just like Finder).
- **Keyboard-Driven**: Designed for power users. Navigate, copy, move, and edit without touching the mouse.
- **Built-in Editor & Viewer**: Preview files instantly or edit text files with the retro-style built-in editor.

## 🚀 Installation

The easiest way to get hNavigator is to download the latest `.dmg` from the Releases page.

1. Go to the [Releases](../../releases/latest) page.
2. Download the `hNavigator.dmg` file.
3. Open the DMG and drag **hNavigator.app** to your `Applications` folder.

> **Note**: This app is distributed outside the Mac App Store to allow full file system access. You may need to grant it Full Disk Access in System Settings -> Privacy & Security -> Full Disk Access for it to function correctly in all system directories.

## 🛠 Building from Source

If you prefer to build the app yourself:

1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR-USERNAME/hNavigator.git
   ```
2. Open `Apple Navigator.xcodeproj` in Xcode 15+.
3. Select the `hNavigator` scheme.
4. Hit `Cmd + R` to build and run.

## 🤝 Contributing
Pull requests are welcome! If you're missing a feature or found a bug, feel free to open an issue.

## 📄 License
This project is open-source and available under the MIT License.
