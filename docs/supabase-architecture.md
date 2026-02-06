# Supabase Architecture for KnowledgeTool

## Overview

This document describes the Supabase backend architecture for sharing characters, personas, and knowledge bases across multiple users.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              macOS App                                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │ LocalCharacter  │  │ SupabaseCharacter│  │ CharacterService │◄── Facade  │
│  │ Repository      │  │ Repository       │  │ (Protocol-based) │             │
│  └────────┬────────┘  └────────┬─────────┘  └────────┬─────────┘             │
│           │                    │                     │                       │
│           └────────────────────┼─────────────────────┘                       │
│                                │                                             │
└────────────────────────────────┼─────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Supabase                                        │
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │   Supabase      │  │    Postgres     │  │    Storage      │              │
│  │     Auth        │  │    Database     │  │    Buckets      │              │
│  │                 │  │                 │  │                 │              │
│  │  - Email/Pass   │  │  - profiles     │  │  - personas     │              │
│  │  - Magic Link   │  │  - characters   │  │  - knowledge    │              │
│  │  - OAuth        │  │  - knowledge_   │  │                 │              │
│  │                 │  │    files        │  │                 │              │
│  │                 │  │  - character_   │  │                 │              │
│  │                 │  │    shares       │  │                 │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
│                                │                                             │
│                                ▼                                             │
│                       ┌─────────────────┐                                    │
│                       │  Row Level      │                                    │
│                       │  Security (RLS) │                                    │
│                       │                 │                                    │
│                       │  - Owner access │                                    │
│                       │  - Public chars │                                    │
│                       │  - Shared access│                                    │
│                       └─────────────────┘                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
                       ┌─────────────────┐
                       │    Pinecone     │
                       │  (Vectors/RAG)  │
                       │                 │
                       │  Namespace per  │
                       │  character_id   │
                       └─────────────────┘
```

## Data Model

### Entity Relationship Diagram

```
┌─────────────┐       ┌─────────────────┐       ┌─────────────────┐
│   profiles  │       │   characters    │       │ knowledge_files │
├─────────────┤       ├─────────────────┤       ├─────────────────┤
│ id (PK)     │──┐    │ id (PK)         │──┐    │ id (PK)         │
│ email       │  │    │ owner_id (FK)───│──┘    │ character_id(FK)│───┐
│ display_name│  └───▶│ name            │       │ file_name       │   │
│ avatar_url  │       │ is_public       │       │ file_type       │   │
│ created_at  │       │ visibility      │       │ storage_path    │   │
└─────────────┘       │ system_prompt_  │       │ word_count      │   │
                      │   type          │       │ created_at      │   │
                      │ version         │       │ updated_at      │   │
                      │ persona_storage │       └─────────────────┘   │
                      │   _path         │                             │
                      │ created_at      │◄────────────────────────────┘
                      │ updated_at      │
                      └─────────────────┘
                              │
                              ▼
                      ┌─────────────────┐
                      │ character_shares│
                      ├─────────────────┤
                      │ id (PK)         │
                      │ character_id(FK)│
                      │ shared_with (FK)│
                      │ permission      │
                      │ created_at      │
                      └─────────────────┘
```

## Visibility & Sharing Model

Characters can have three visibility levels:

| Visibility | Description |
|------------|-------------|
| `private` | Only the owner can see/edit |
| `shared` | Owner + explicitly shared users can see |
| `public` | Anyone can see (read-only for non-owners) |

### Permission Levels for Shared Characters

| Permission | Can View | Can Edit | Can Delete | Can Re-share |
|------------|----------|----------|------------|--------------|
| `viewer` | ✅ | ❌ | ❌ | ❌ |
| `editor` | ✅ | ✅ | ❌ | ❌ |
| `admin` | ✅ | ✅ | ✅ | ✅ |

## Storage Structure

```
supabase-storage/
├── personas/
│   └── {user_id}/
│       └── {character_id}/
│           └── persona.md
│
└── knowledge/
    └── {user_id}/
        └── {character_id}/
            ├── transcript_video1.txt
            ├── transcript_video2.txt
            ├── knowledge_video1.jsonl
            ├── knowledge_video2.jsonl
            ├── all_transcripts_combined.txt
            ├── all_knowledge_combined.jsonl
            └── dialogue_examples.txt
```

## API Patterns

### Character Operations

```swift
// Fetch all accessible characters (owned + shared + public)
let characters = try await supabase
    .from("characters")
    .select("*, knowledge_files(*), profiles!owner_id(display_name)")
    .execute()

// Create a character
let character = try await supabase
    .from("characters")
    .insert(newCharacter)
    .select()
    .single()
    .execute()

// Update a character
let updated = try await supabase
    .from("characters")
    .update(["name": newName])
    .eq("id", characterId)
    .execute()

// Share a character
let share = try await supabase
    .from("character_shares")
    .insert([
        "character_id": characterId,
        "shared_with": userId,
        "permission": "editor"
    ])
    .execute()
```

### Storage Operations

```swift
// Upload persona file
let data = personaMarkdown.data(using: .utf8)!
try await supabase.storage
    .from("personas")
    .upload(
        path: "\(userId)/\(characterId)/persona.md",
        file: data,
        options: FileOptions(contentType: "text/markdown")
    )

// Download knowledge file
let data = try await supabase.storage
    .from("knowledge")
    .download(path: "\(userId)/\(characterId)/\(fileName)")
```

### Real-time Subscriptions

```swift
// Subscribe to character updates
let channel = supabase.channel("characters")
    .onPostgresChange(
        event: .all,
        schema: "public",
        table: "characters",
        filter: "owner_id=eq.\(userId)"
    ) { payload in
        // Handle update
    }
    .subscribe()
```

## Sync Strategy

### Conflict Resolution

When both local and remote changes exist:

1. **Last-write-wins** for simple fields (name, visibility)
2. **Merge** for knowledge files (union of files, latest content wins)
3. **Version tracking** for personas (create new version on conflict)

### Offline Support

1. App writes to local storage first
2. Changes queued for sync when online
3. On reconnect, sync queue processes in order
4. Conflicts resolved per above strategy

## Migration from Local-Only

For existing users with local characters:

1. On first Supabase connection, prompt to import local characters
2. Upload each character with `is_local_import: true` flag
3. Maintain local copies as backup
4. Future changes sync to Supabase

## Security Considerations

### Row Level Security Policies

All tables have RLS enabled. Key policies:

- Users can only modify their own characters
- Users can view public characters
- Users can view characters shared with them
- Storage paths include user_id to prevent path traversal

### API Key Management

- Supabase anon key stored in app (public, safe)
- Service role key NEVER in client app
- User JWT tokens for authenticated requests
- Refresh tokens stored in Keychain

## Performance Optimizations

1. **Pagination**: Characters and knowledge files paginated (50 per page)
2. **Lazy Loading**: Knowledge file content loaded on demand
3. **Caching**: Characters cached locally with 5-minute TTL
4. **Compression**: Large knowledge files compressed before upload
5. **Batch Operations**: Multiple knowledge files uploaded in parallel
