# Supabase Setup Guide for KnowledgeTool

This guide walks through setting up Supabase for shared characters and knowledge bases.

## Prerequisites

- A Supabase account (free tier works)
- Xcode 15+ with Swift 6 support

## Step 1: Create Supabase Project

1. Go to [supabase.com](https://supabase.com) and sign in
2. Click "New Project"
3. Choose your organization
4. Enter project details:
   - **Name**: `knowledgetool` (or your preferred name)
   - **Database Password**: Generate a strong password and save it
   - **Region**: Choose closest to your users
5. Click "Create new project" and wait for provisioning (~2 minutes)

## Step 2: Get Your API Keys

1. In your Supabase dashboard, go to **Settings** → **API**
2. Copy these values (you'll need them for the app):
   - **Project URL**: `https://xxxxxxxxxxxx.supabase.co`
   - **anon public key**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`

**Important**: The `anon` key is safe to include in client apps. Never expose the `service_role` key.

## Step 3: Run Database Migration

1. In Supabase dashboard, go to **SQL Editor**
2. Click "New query"
3. Copy the entire contents of `supabase/migrations/001_initial_schema.sql`
4. Paste into the SQL editor
5. Click "Run" (or Cmd+Enter)
6. Verify no errors appear

This creates:
- `profiles` table (extended user data)
- `characters` table (personas)
- `knowledge_files` table (transcripts, knowledge bases)
- `character_shares` table (sharing between users)
- `character_versions` table (version history)
- Row Level Security policies
- Triggers for auto-updating timestamps

## Step 4: Create Storage Buckets

1. Go to **Storage** in the sidebar
2. Click "New bucket"
3. Create bucket named `personas`:
   - **Name**: `personas`
   - **Public bucket**: OFF
   - Click "Create bucket"
4. Create bucket named `knowledge`:
   - **Name**: `knowledge`
   - **Public bucket**: OFF
   - Click "Create bucket"

## Step 5: Set Up Storage Policies

1. Click on the `personas` bucket
2. Go to **Policies** tab
3. Click "New Policy" → "For full customization"
4. Create policy for authenticated users:

```sql
-- Policy name: Users can access own persona files
-- Allowed operations: SELECT, INSERT, UPDATE, DELETE
-- Policy definition:
(bucket_id = 'personas' AND auth.uid()::text = (storage.foldername(name))[1])
```

5. Repeat for the `knowledge` bucket with the same policy

Alternatively, run this in SQL Editor:

```sql
-- Create storage policies
create policy "Users can access own persona files"
on storage.objects for all
using (
    bucket_id = 'personas'
    and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "Users can access own knowledge files"
on storage.objects for all
using (
    bucket_id = 'knowledge'
    and auth.uid()::text = (storage.foldername(name))[1]
);
```

## Step 6: Enable Authentication

1. Go to **Authentication** → **Providers**
2. Email is enabled by default
3. (Optional) Enable additional providers:
   - **Apple**: Recommended for macOS app
   - **Google**: Popular option

For Apple Sign-In:
1. You'll need an Apple Developer account
2. Create a Service ID in Apple Developer Console
3. Add the credentials to Supabase

## Step 7: Configure the App

Add your Supabase credentials to the app:

### Option A: Environment Variables (Recommended for development)

Create a `.env` file in the project root (add to .gitignore):

```
SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Option B: Settings UI

The app will have a Settings section where you can enter:
- Supabase URL
- Supabase Anon Key

### Option C: APIKeyManager (Current pattern)

Add to `APIKeyManager.swift`:

```swift
static var supabaseURL: String? {
    get { keychain.get("supabase_url") }
    set {
        if let value = newValue {
            keychain.set(value, forKey: "supabase_url")
        } else {
            keychain.delete("supabase_url")
        }
    }
}

static var supabaseAnonKey: String? {
    get { keychain.get("supabase_anon_key") }
    set {
        if let value = newValue {
            keychain.set(value, forKey: "supabase_anon_key")
        } else {
            keychain.delete("supabase_anon_key")
        }
    }
}
```

## Step 8: Add Swift Package Dependency

### For Xcode Project:

1. Open `KnowledgeTool.xcodeproj` in Xcode
2. Go to **File** → **Add Package Dependencies...**
3. Enter: `https://github.com/supabase/supabase-swift`
4. Select version: `2.0.0` or later
5. Click "Add Package"
6. Select the `Supabase` product
7. Click "Add Package"

### For Package.swift (already done):

The Package.swift has been updated to include:

```swift
dependencies: [
    .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
],
```

## Step 9: Test the Connection

Run this test code to verify connectivity:

```swift
import Supabase

let client = SupabaseClient(
    supabaseURL: URL(string: "YOUR_SUPABASE_URL")!,
    supabaseKey: "YOUR_ANON_KEY"
)

// Test: List characters (should return empty array for new setup)
Task {
    do {
        let response: [SupabaseCharacter] = try await client
            .from("characters")
            .select("*")
            .execute()
            .value
        print("Connected! Found \(response.count) characters")
    } catch {
        print("Connection failed: \(error)")
    }
}
```

## Step 10: Enable Realtime (Optional)

For live updates when other users modify shared characters:

1. Go to **Database** → **Replication**
2. Enable replication for:
   - `characters`
   - `knowledge_files`
   - `character_shares`

## Troubleshooting

### "Permission denied" errors
- Check Row Level Security policies
- Verify user is authenticated
- Check the storage bucket policies

### "relation does not exist" errors
- Run the migration SQL again
- Check for typos in table names

### Package resolution fails
- Clear SPM cache: `rm -rf ~/Library/Caches/org.swift.swiftpm`
- Reset package dependencies in Xcode: File → Packages → Reset Package Caches

### Storage upload fails
- Verify bucket exists and is named correctly
- Check storage policies allow the operation
- Ensure file path follows the `userId/characterId/filename` pattern

## Next Steps

1. Implement authentication UI (sign in/up forms)
2. Add sync toggle in settings (local vs cloud)
3. Build character sharing UI
4. Add offline support with local caching
5. Implement conflict resolution for simultaneous edits
