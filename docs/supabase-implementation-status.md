# Supabase Implementation Status

## What's Been Created

### 1. Database Schema (`supabase/migrations/001_initial_schema.sql`)

**Knowledge File Types** (enum in database):
- `transcript` - Raw video transcripts with timestamps
- `knowledge` - Structured JSONL knowledge bases
- `dialogue` - Dialog examples (e.g., `dialog_examples.jsonl`)
- `combined` - Combined/merged files
- `custom` - User-uploaded custom knowledge

Complete SQL migration including:

| Table | Purpose |
|-------|---------|
| `profiles` | User profiles (extends Supabase Auth) |
| `characters` | Main character/persona storage |
| `knowledge_files` | Transcripts, JSONL knowledge, dialogue files |
| `character_shares` | Sharing between users |
| `character_versions` | Version history tracking |

**Features:**
- Enums for visibility (`private`, `shared`, `public`)
- Enums for permissions (`viewer`, `editor`, `admin`)
- Row Level Security (RLS) policies for all tables
- Auto-updating `updated_at` triggers
- Foreign key constraints with cascade delete

### 2. Swift Service Layer

**`SupabaseService.swift`** - Low-level Supabase client wrapper:
- Authentication (sign in/up/out)
- CRUD operations for characters, knowledge files, shares
- Storage operations for file upload/download
- Codable models matching the database schema

**`SupabaseCharacterRepository.swift`** - High-level repository:
- Bridges Supabase models to existing `Character` model
- Implements same patterns as `LocalCharacterRepository`
- Handles file content lazy loading from storage
- Sharing functionality (by email)
- Visibility updates

### 3. Documentation

**`docs/supabase-architecture.md`** - Architecture overview:
- System diagram
- Entity relationships
- API patterns
- Sync strategy
- Security considerations

**`docs/supabase-setup.md`** - Setup guide:
- Step-by-step Supabase project creation
- Database migration instructions
- Storage bucket setup
- Swift package integration

**`CharacterRepositoryProtocol.swift`** - Unified interface:
- Protocol for both local and Supabase repositories
- `CombinedCharacterRepository` that syncs between both
- Handles dialog examples auto-save with upsert semantics

### 4. Package.swift Update

Added Supabase Swift SDK dependency:
```swift
.package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
```

## What's Needed Next

### 1. Add Supabase Package to Xcode Project

The Package.swift is updated, but for Xcode builds you also need to:

1. Open `KnowledgeTool.xcodeproj`
2. File → Add Package Dependencies
3. Add `https://github.com/supabase/supabase-swift`
4. Select version `2.0.0` or later

### 2. Add Files to Xcode Project

The new Swift files need to be added to `project.pbxproj`:
- `SupabaseService.swift`
- `SupabaseCharacterRepository.swift`

### 3. API Key Management

Add Supabase credentials to `APIKeyManager.swift`:

```swift
// Add these computed properties
static var supabaseURL: String? {
    get { keychain.get("supabase_url") }
    set { /* ... */ }
}

static var supabaseAnonKey: String? {
    get { keychain.get("supabase_anon_key") }
    set { /* ... */ }
}
```

### 4. Settings UI

Add Supabase configuration section to `SettingsView.swift`:
- URL input field
- Anon key input field
- Connection test button
- Sign in/up UI

### 5. Character Service Protocol

Create a protocol to abstract local vs Supabase storage:

```swift
protocol CharacterRepositoryProtocol {
    func loadAllCharacters() async throws -> [Character]
    func createCharacter(name: String, markdownContent: String) async throws -> Character
    func saveCharacter(_ character: Character) async throws
    func deleteCharacter(_ character: Character) async throws
    // etc.
}
```

Then both `LocalCharacterRepository` and `SupabaseCharacterRepository` can conform.

### 6. Sync Toggle

Add a toggle in settings for:
- **Local Only** - Current behavior, files stored locally
- **Cloud Sync** - Use Supabase for storage and sharing

### 7. Authentication UI

Create views for:
- Sign in (email/password)
- Sign up (email/password + display name)
- Password reset
- (Optional) OAuth providers (Apple, Google)

### 8. Sharing UI

Create views for:
- Share character dialog (enter email, select permission)
- Manage shares (view/remove existing shares)
- View who shared a character with you

### 9. Build Script Note

The `build-app.sh` standalone build script **cannot** use Supabase because:
- It uses direct `swiftc` compilation
- External SPM dependencies require resolution
- Would need to vendor the entire Supabase SDK

**Solution**: The Supabase files are NOT added to `build-app.sh`. They only work with Xcode builds.

Files excluded from build-app.sh (require Supabase SDK):
- `SupabaseService.swift`
- `SupabaseCharacterRepository.swift`
- `CharacterRepositoryProtocol.swift` (the `CombinedCharacterRepository` part)

**For production**, use Xcode builds which can resolve SPM dependencies.

## Dialog Examples Integration

Dialog examples are now auto-saved to `dialog_examples.jsonl` in the character's Knowledge folder. The Supabase integration handles this seamlessly:

1. **File Type Detection**: `dialog_examples.jsonl` is automatically detected as type `dialogue`
2. **Upsert Semantics**: The `createKnowledgeFile` method checks if the file exists and updates it, or creates new
3. **Combined Repository**: `CombinedCharacterRepository` saves locally first, then syncs to Supabase in background

**Flow:**
```
DialogExampleViewModel.save()
    └─▶ CombinedCharacterRepository.createKnowledgeFile()
        ├─▶ LocalCharacterRepository.createKnowledgeFile()  (immediate)
        └─▶ SupabaseCharacterRepository.createKnowledgeFile()  (background)
            ├─▶ Upload to Supabase Storage
            └─▶ Upsert database record
```

## File Locations

```
knowledge-tool/
├── docs/
│   ├── supabase-architecture.md      # Architecture documentation
│   ├── supabase-setup.md             # Setup guide
│   └── supabase-implementation-status.md  # This file
├── supabase/
│   └── migrations/
│       └── 001_initial_schema.sql    # Database migration
├── KnowledgeTool/
│   ├── Package.swift                 # Updated with Supabase dependency
│   └── Services/
│       ├── SupabaseService.swift           # Low-level Supabase client
│       ├── SupabaseCharacterRepository.swift  # High-level repository
│       └── CharacterRepositoryProtocol.swift  # Protocol + combined repository
```

## Configuration Required

Before using Supabase, you need:

1. **Supabase Project URL**: `https://xxxx.supabase.co`
2. **Supabase Anon Key**: `eyJhbGciOiJIUzI1Ni...`

These will be stored securely in Keychain via `APIKeyManager`.
