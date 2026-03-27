# Murmur — macOS Voice Dictation App

## Build
```bash
swift build                  # Debug build
scripts/build.sh             # Creates Murmur.app bundle
scripts/build.sh --release   # Release build
```

## Architecture
- Swift 5.9+ / SwiftUI menu bar app (no Xcode — SPM only)
- Apple Speech Framework for on-device STT (free)
- Claude Haiku API for transcript cleanup
- macOS Accessibility API for text insertion at cursor
- NSEvent global monitor for hotkey

## Pipeline
Hold Option → AVAudioEngine captures mic → release → SFSpeechRecognizer transcribes → Claude Haiku cleans → AXUIElement inserts text at cursor

## Key Files
- `MurmurApp.swift` — AppDelegate, NSStatusItem menu bar
- `DictationPipeline.swift` — Orchestrates record→transcribe→enhance→insert
- `Core/SpeechEngine.swift` — AVAudioEngine + SFSpeechRecognizer
- `Core/TextEnhancer.swift` — Claude Haiku API call
- `Core/TextInserter.swift` — AXUIElement insertion + clipboard fallback
- `Core/HotkeyManager.swift` — Global hotkey management
- `Views/MenuBarView.swift` — Popover UI
- `Views/SettingsView.swift` — API key, hotkey config, permissions
