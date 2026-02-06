# KnowledgeTool Development Guidelines

## Build System Overview

This project uses **Xcode** for builds:

1. **Xcode Project** (`KnowledgeTool.xcodeproj/project.pbxproj`) - for IDE and command-line builds
2. **Build Script** (`build-app.sh`) - convenience wrapper around `xcodebuild`

The build script uses `xcodebuild` internally, so both methods use the same Xcode project and automatically resolve SPM dependencies (like Supabase).

---

## Adding New Swift Files

### Step 1: Create the file

Place the file in the appropriate directory under `KnowledgeTool/`:
- `App/` - Main app entry point
- `Views/` - SwiftUI views (organized by feature in subdirectories)
- `ViewModels/` - View models
- `Models/` - Data models
- `Services/` - API services and business logic
- `Utilities/` - Helper utilities
- `Resources/` - Assets, templates, bundled binaries

### Step 2: Update project.pbxproj

Add entries to **four sections** in `KnowledgeTool.xcodeproj/project.pbxproj`:

#### 1. PBXBuildFile section
```
AXXX /* YourNewFile.swift in Sources */ = {isa = PBXBuildFile; fileRef = BXXX /* YourNewFile.swift */; };
```

#### 2. PBXFileReference section
```
BXXX /* YourNewFile.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = YourNewFile.swift; sourceTree = "<group>"; };
```

#### 3. PBXGroup section (add to appropriate group's children)
Find the correct group (e.g., Views group is `F104`) and add:
```
BXXX /* YourNewFile.swift */,
```

#### 4. PBXSourcesBuildPhase section
```
AXXX /* YourNewFile.swift in Sources */,
```

**ID Convention:** Use unique 4-character IDs. Check existing IDs to avoid collisions.

---

## Design System

All UI components should use the centralized design system in `KnowledgeTool/Views/DesignSystem.swift`:

### Design Tokens
```swift
DesignSystem.CornerRadius.small    // 6pt
DesignSystem.CornerRadius.medium   // 8pt
DesignSystem.CornerRadius.large    // 12pt
DesignSystem.CornerRadius.xl       // 16pt

DesignSystem.Spacing.xs            // 4pt
DesignSystem.Spacing.sm            // 8pt
DesignSystem.Spacing.md            // 12pt
DesignSystem.Spacing.lg            // 16pt
DesignSystem.Spacing.xl            // 20pt

DesignSystem.Animation.quick       // 0.15s
DesignSystem.Animation.standard    // 0.25s
DesignSystem.Animation.smooth      // 0.35s
DesignSystem.Animation.spring      // spring animation
```

### Reusable Components
- `CharacterAvatar` - Character avatar with initials fallback
- `StatusBadge` - Colored status indicators
- `KeyboardShortcutHint` - Keyboard shortcut display
- `SectionHeader` - Section headers with optional actions
- `HelperText` - Subtle helper/hint text
- `ActivityDot` - Pulsing activity indicator
- `InlineLoader` - Inline loading spinner
- `AnimatedTypingIndicator` - Chat typing indicator

### View Modifiers
```swift
.cardStyle()           // Standard card with shadow
.subtleCardStyle()     // Lighter card style
.interactiveCardStyle(isHovered: Bool)  // Hover-responsive card
```

---

## Keyboard Shortcuts

Global shortcuts are defined in `KnowledgeToolApp.swift`:

| Shortcut | Action |
|----------|--------|
| `Cmd+1` | Navigate to Editor |
| `Cmd+2` | Navigate to Chat |
| `Cmd+3` | Navigate to Videos |
| `Cmd+4` | Navigate to Knowledge Base |
| `Cmd+5` | Navigate to Prompt Testing |
| `Cmd+K` | Quick Switch Character |
| `Cmd+R` | Refresh Characters |
| `Cmd+N` | New Character |
| `Cmd+,` | Settings |

Use `KeyboardShortcutHint` component to display shortcuts in the UI.

---

## Notification-Based Navigation

Views communicate via NotificationCenter:

```swift
// Post navigation
NotificationCenter.default.post(name: .navigateToSection, object: sectionIndex)

// Receive in view
.onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { notification in
    if let section = notification.object as? Int {
        selectedSection = section
    }
}
```

Available notifications (defined in `KnowledgeToolApp.swift`):
- `.openSettings`
- `.newCharacter`
- `.navigateToSection`
- `.quickSwitchCharacter`
- `.refreshCharacters`

---

## Bundled Binaries

The app bundles these executables in `KnowledgeTool/Resources/bin/`:
- `yt-dlp` - YouTube video/audio downloading
- `ffmpeg` - Media processing
- `ffprobe` - Media analysis
- `node` - Node.js runtime

These are copied to the app bundle during build and accessed via `Bundle.main.resourceURL`.

---

## Testing Builds

### Xcode Build
Open `KnowledgeTool.xcodeproj` and build normally (Cmd+B).

### Script Build
```bash
./build-app.sh
```

The built app will be at `build/KnowledgeTool.app`.

**Note:** The build script requires Xcode (not just Command Line Tools). If you get an error about Command Line Tools, run:
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

---

## Common Issues

### "Cannot find [Type] in scope"
The file containing that type isn't in the Xcode project. Check that it's properly added to `project.pbxproj` (all 4 sections).

### "no such module 'Supabase'" or other SPM errors
The build script uses xcodebuild which resolves SPM dependencies automatically. Make sure:
1. Xcode (not Command Line Tools) is selected: `xcode-select -p` should show `/Applications/Xcode.app/Contents/Developer`
2. Run `xcodebuild -resolvePackageDependencies -project KnowledgeTool.xcodeproj` to manually resolve dependencies

### Build script shows "Command Line Tools is selected"
Run: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

---

## Releasing

See `RELEASING.md` for full release instructions. Quick version:

```bash
# Build, sign, and create release
./scripts/release.sh 1.2.0 "Release notes here"

# Push appcast and create GitHub release
git add appcast.xml && git commit -m "Update appcast for v1.2.0" && git push geniesinc HEAD:main
gh release create v1.2.0 build/KnowledgeTool-1.2.0.zip --repo geniesinc/knowledgetool --title "v1.2.0" --notes "Release notes"
```
