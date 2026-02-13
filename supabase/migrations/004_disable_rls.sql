-- ============================================================================
-- Disable RLS on all tables for anon-key-only access
-- ============================================================================
-- The app uses Supabase URL + anon key without user authentication.
-- RLS requires auth.uid() which is NULL without a session, blocking all operations.
-- This migration disables RLS so the anon key can read/write directly.
-- ============================================================================

-- Disable RLS on all tables
alter table public.profiles disable row level security;
alter table public.characters disable row level security;
alter table public.knowledge_files disable row level security;
alter table public.character_versions disable row level security;
alter table public.system_prompts disable row level security;

-- Drop all existing RLS policies (they're no longer needed)

-- Characters policies (from migration 003)
drop policy if exists "Users can view own characters" on public.characters;
drop policy if exists "Users can create characters" on public.characters;
drop policy if exists "Users can update own characters" on public.characters;
drop policy if exists "Users can delete own characters" on public.characters;

-- Knowledge files policies (from migration 003)
drop policy if exists "Users can view own knowledge files" on public.knowledge_files;
drop policy if exists "Users can add knowledge files" on public.knowledge_files;
drop policy if exists "Users can update own knowledge files" on public.knowledge_files;
drop policy if exists "Users can delete own knowledge files" on public.knowledge_files;

-- Character versions policies (from migration 003)
drop policy if exists "Users can view own character versions" on public.character_versions;
drop policy if exists "Users can create character versions" on public.character_versions;

-- Profiles policies (from migration 001)
drop policy if exists "Users can view their own profile" on public.profiles;
drop policy if exists "Users can update their own profile" on public.profiles;
drop policy if exists "Public profiles are viewable by everyone" on public.profiles;

-- System prompts policies (from migration 002)
drop policy if exists "Authenticated users can view system prompts" on public.system_prompts;
drop policy if exists "Only admins can modify system prompts" on public.system_prompts;

-- Make owner_id nullable so we can insert without authentication
-- Use a default UUID for records created without auth
alter table public.characters alter column owner_id drop not null;

-- Remove the foreign key constraint on owner_id -> profiles
-- so we don't need a profiles entry to create characters
alter table public.characters drop constraint if exists characters_owner_id_fkey;

-- Drop the unique constraint on (owner_id, slug) since owner_id can be null
alter table public.characters drop constraint if exists unique_owner_slug;

-- Add a simpler unique constraint on just the slug
-- (since we're single-user without auth, slug alone should be unique)
alter table public.characters add constraint unique_slug unique (slug);
