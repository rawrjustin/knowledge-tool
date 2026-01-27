# KnowledgeTool Development Guidelines

## Build System Overview

This project has **two parallel build mechanisms** that must stay synchronized:

1. **Xcode Project** (`KnowledgeTool.xcodeproj/project.pbxproj`) - for IDE builds
2. **Build Script** (`build-app.sh`) - for command-line builds without Xcode

**Both must be updated when adding new Swift files.**

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

### Step 2: Update build-app.sh

Add the file path to the `SOURCE_FILES` array (around line 68):

```bash
SOURCE_FILES=(
    KnowledgeTool/App/KnowledgeToolApp.swift
    KnowledgeTool/Views/DesignSystem.swift
    KnowledgeTool/Views/ContentView.swift
    # ... add your new file here in the appropriate section
    KnowledgeTool/Views/YourNewView.swift
)
```

**Important:** Maintain alphabetical order within each directory group for readability.

### Step 3: Update project.pbxproj

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

### Verify Both
Always test both build methods after adding files to catch synchronization issues early.

---

## Common Issues

### "Cannot find [Type] in scope"
The file containing that type isn't included in the build. Check:
1. Is it in `build-app.sh` SOURCE_FILES?
2. Is it in `project.pbxproj` (all 4 sections)?

### Build script fails but Xcode works
File is in Xcode project but not in `build-app.sh` SOURCE_FILES array.

### Xcode fails but build script works
File is in `build-app.sh` but not properly added to `project.pbxproj`.

### #Preview macro errors in build script
The build script automatically strips `#Preview` blocks using perl regex since the Preview macro requires Xcode's macro system. If you still get Preview-related errors:
1. Ensure your Preview block follows standard format: `#Preview { ... }` or `#Preview("name") { ... }`
2. For complex cases, consider removing the Preview from the source file entirely

---

## SwiftUI Previews

SwiftUI `#Preview` blocks work in Xcode but **not** in the command-line build. The build script strips them automatically. If adding previews:

- Keep preview code simple and self-contained
- Don't put production code inside preview blocks
- Previews are optional - the build will work without them
