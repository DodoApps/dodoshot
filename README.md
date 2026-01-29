<p align="center">
  <img src="https://img.icons8.com/fluency/96/camera.png" alt="DodoShot Logo" width="80" height="80">
</p>

<h1 align="center">DodoShot</h1>

<p align="center">
  <strong>A beautiful, open-source screenshot tool for macOS</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#keyboard-shortcuts">Shortcuts</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square" alt="Swift">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
</p>

---

## About

DodoShot is a lightweight, native macOS screenshot application built with SwiftUI. Inspired by CleanShot X, it provides a beautiful and intuitive interface for capturing, annotating, and managing screenshots — completely free and open source.

## Features

### Capture modes
- **Area capture** — Select any region of your screen
- **Window capture** — Capture specific application windows
- **Fullscreen capture** — Capture your entire screen
- **Scrolling capture** — Capture long pages by automatically scrolling and stitching

### Quick overlay
- Stacking overlays for multiple captures
- Swipe to dismiss
- Quick actions: copy, save, annotate, pin
- Expandable preview with metadata

### Annotation tools
- Arrows, rectangles, ellipses, and lines
- Text annotations
- Blur sensitive areas
- Highlight important content
- Freehand drawing
- Color picker with 9 preset colors
- Adjustable stroke width

### Measurement tools
- Pixel ruler for measuring on-screen elements
- Color picker to sample any color on screen

### Productivity features
- Pin screenshots as floating windows
- Auto-copy to clipboard
- Capture history with grid/list views
- Hide desktop icons during capture
- Global keyboard shortcuts

### AI-powered (optional)
- OCR text extraction
- Smart image descriptions
- Supports Anthropic and OpenAI providers

### Design
- Native macOS look and feel
- Dark mode support (System/Light/Dark)
- Vibrancy and blur effects
- Smooth animations throughout

## Installation

### Requirements
- macOS 14.0 (Sonoma) or later
- Screen Recording permission
- Accessibility permission (for global hotkeys)

### Homebrew (Recommended)
```bash
brew tap bluewave-labs/tap
brew install --cask dodoshot
```

The Homebrew installation automatically handles the quarantine flag removal.

### Download DMG
1. Download the latest DMG from [Releases](https://github.com/bluewave-labs/DodoShot/releases)
2. Open the DMG and drag DodoShot to Applications
3. **Important:** Run this command in Terminal to remove the quarantine flag:
   ```bash
   xattr -cr /Applications/DodoShot.app
   ```
4. Launch DodoShot from Applications

> **Note:** The `xattr` command is required because the app is not signed with an Apple Developer certificate. This is safe for open-source software where you can verify the source code.

### Build from source
1. Clone the repository:
   ```bash
   git clone https://github.com/bluewave-labs/DodoShot.git
   cd DodoShot
   ```

2. Open in Xcode:
   ```bash
   open DodoShot.xcodeproj
   ```

3. Build and run (⌘R)

## Usage

1. Launch DodoShot — it runs in your menu bar
2. Click the menu bar icon or use keyboard shortcuts
3. Select a capture mode
4. After capture, use the quick overlay to:
   - Copy to clipboard
   - Save to file
   - Open annotation editor
   - Pin as floating window
5. Access capture history from the menu bar

## Keyboard shortcuts

| Action | Default shortcut |
|--------|-----------------|
| Area capture | ⌘⇧4 |
| Window capture | ⌘⇧5 |
| Fullscreen capture | ⌘⇧3 |

Shortcuts can be customized in Settings → Hotkeys.

## Project structure

```
DodoShot/
├── DodoShotApp.swift          # App entry point
├── Models/
│   └── Screenshot.swift       # Data models
├── Views/
│   ├── MenuBarView.swift      # Menu bar interface
│   ├── Capture/               # Capture selection views
│   ├── Overlay/               # Quick overlay after capture
│   ├── History/               # Capture history panel
│   ├── Annotation/            # Annotation editor
│   ├── Settings/              # Settings window
│   └── Permissions/           # Permission request views
├── Services/
│   ├── ScreenCaptureService.swift
│   ├── ScrollingCaptureService.swift
│   ├── FloatingWindowService.swift
│   ├── MeasurementService.swift
│   ├── SettingsManager.swift
│   ├── HotkeyManager.swift
│   ├── OCRService.swift
│   └── LLMService.swift
└── Resources/
    └── Assets.xcassets
```

## Contributing

Contributions are welcome! Here's how you can help:

1. **Report bugs** — Open an issue describing the problem
2. **Suggest features** — Open an issue with your idea
3. **Submit PRs** — Fork, create a branch, and submit a pull request

### Development setup
1. Fork and clone the repository
2. Open in Xcode 15+
3. Build and run
4. Make your changes
5. Test thoroughly
6. Submit a PR

### Code style
- Follow Swift API Design Guidelines
- Use SwiftUI for all new views
- Keep views small and composable
- Add MARK comments for organization

## Roadmap

- [ ] Video/GIF recording
- [ ] Cloud sync
- [ ] Custom templates
- [ ] Watermarks
- [ ] Direct sharing to apps
- [ ] Browser extension
- [ ] Command-line interface

## Acknowledgments

- Inspired by [CleanShot X](https://cleanshot.com)
- Built with SwiftUI and ScreenCaptureKit
- Icons from SF Symbols

## License

DodoShot is released under the MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/bluewave-labs">Bluewave Labs</a>
</p>
