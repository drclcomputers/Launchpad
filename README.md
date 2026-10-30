# <div align="center">

#  Launchpad

**A reimplementation of the classic Launchpad for macOS Tahoe and Golden Gate.**

Fast, familiar, and native: your apps, one keystroke away.

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey?logo=apple)
![Swift](https://img.shields.io/badge/Swift-FA7343?logo=swift&logoColor=white)
![License](https://img.shields.io/github/license/drclcomputers/Launchpad)
![Stars](https://img.shields.io/github/stars/drclcomputers/Launchpad?style=social)

<img src="docs/screenshots/1.png" alt="Launchpad main grid" width="800">
<img src="docs/screenshots/2.png" alt="Launchpad main grid" width="800">

</div>

---

## Why?

Apple removed Launchpad from recent versions of macOS in favor of the Apps view (which is kinda buggy). This project brings back the grid-of-apps experience you know, rebuilt from scratch for modern macOS.

## Screenshots

| Main grid | Search |
|:---:|:---:|
| <img src="docs/screenshots/3.png" width="400" alt="App grid"> | <img src="docs/screenshots/5.png" width="400" alt="Search"> |
| *Your apps, paginated and sorted* | *Type to filter instantly* |

## Features

- 🔲 **App grid**: all your installed apps in a paginated grid
- 🔍 **Instant search**: start typing to filter
- ⌨️ **Keyboard friendly**: arrow keys to navigate, Return to launch, Esc to close
- 🪟 **Native look**: built to match the macOS Liquid Glass design language

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26+ (only if building from source)

## Installation

### Download

Grab the latest build from the [Releases](https://github.com/drclcomputers/Launchpad/releases) page, unzip it, and drag **Launchpad.app** into your `/Applications` folder.

> On first launch, right-click the app and choose **Open** if macOS warns about an unidentified developer.

### Build from source

```bash
git clone https://github.com/drclcomputers/Launchpad.git
cd Launchpad
open Launchpad.xcodeproj
```

Then select the **Launchpad** scheme and press <kbd>⌘</kbd> + <kbd>R</kbd>.

## Usage

| Action | Shortcut |
|---|---|
| Open / close Launchpad | `[your shortcut]` |
| Search | Just start typing |
| Next / previous page | <kbd>→</kbd> / <kbd>←</kbd> or trackpad swipe |
| Launch selected app | <kbd>Return</kbd> |
| Close | <kbd>Esc</kbd> |

## Project structure

```
Launchpad/
├── Launchpad/              # App source code
├── Launchpad.xcodeproj/    # Xcode project
├── Launchpad.entitlements  # App entitlements
└── LICENSE
```

## License

Released under the [MIT License](LICENSE).

## Acknowledgements

Inspired by Apple's original Launchpad. This project is not affiliated with or endorsed by Apple Inc.
