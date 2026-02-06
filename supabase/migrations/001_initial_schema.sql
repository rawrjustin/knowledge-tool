-- KnowledgeTool Supabase Schema
-- Migration: 001_initial_schema
-- Description: Initial schema for shared characters and knowledge bases

-- Enable required extensions
create extension if not exists "uuid-ossp";

-- ============================================================================
-- PROFILES TABLE
-- Extended user profile (supplements auth.users)
-- ============================================================================

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    email text unique,
    display_name text,
    avatar_url text,
    created_at timestamptz default now() not null,
    updated_at timestamptz default now() not null
);

-- Auto-create profile on user signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (id, email, display_name)
    values (
        new.id,
        new.email,
        coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
    );
    return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ============================================================================
-- CHARACTERS TABLE
-- Main character/persona storage
-- ============================================================================

-- Enum for visibility levels
create type character_visibility as enum ('private', 'shared', 'public');

-- Enum for system prompt types (matches Swift SystemPromptType)
create type system_prompt_type as enum ('ASP', 'CSP', 'RSP');

create table public.characters (
    id uuid primary key default uuid_generate_v4(),

    -- Ownership
    owner_id uuid not null references public.profiles(id) on delete cascade,

    -- Character metadata
    name text not null,
    slug text not null, -- URL-safe name (e.g., "jake-paul")
    description text, -- Optional short description

    -- Visibility & sharing
    visibility character_visibility default 'private' not null,

    -- Persona content
    persona_storage_path text, -- Path in Supabase Storage (e.g., "user_id/char_id/persona.md")
    persona_content text, -- Optional: store small personas directly in DB

    -- Character settings
    system_prompt_type system_prompt_type default 'CSP' not null,
    version integer default 1 not null,

    -- Source tracking
    source_type text, -- 'youtube', 'wikipedia', 'original', 'import'
    source_urls text[], -- Array of source URLs used to create this character

    -- Vector database reference
    pinecone_namespace text, -- Namespace in Pinecone for this character's vectors

    -- Timestamps
    created_at timestamptz default now() not null,
    updated_at timestamptz default now() not null,

    -- Constraints
    constraint unique_owner_slug unique (owner_id, slug)
);

-- Index for common queries
create index idx_characters_owner on public.characters(owner_id);
create index idx_characters_visibility on public.characters(visibility);
create index idx_characters_name on public.characters(name);

-- ============================================================================
-- KNOWLEDGE FILES TABLE
-- Knowledge base files for each character
-- ============================================================================

-- Enum for knowledge file types
create type knowledge_file_type as enum (
    'transcript',      -- Raw transcript with timestamps
    'knowledge',       -- Structured JSONL knowledge base
    'dialogue',        -- Dialogue examples
    'combined',        -- Combined/merged files
    'custom'           -- User-uploaded custom knowledge
);

create table public.knowledge_files (
    id uuid primary key default uuid_generate_v4(),

    -- Parent character
    character_id uuid not null references public.characters(id) on delete cascade,

    -- File metadata
    file_name text not null,
    file_type knowledge_file_type default 'custom' not null,
    mime_type text default 'text/plain',

    -- Storage reference
    storage_path text not null, -- Path in Supabase Storage

    -- Optional: store small files directly in DB
    content text,

    -- Stats
    file_size_bytes integer,
    word_count integer,

    -- Source tracking (for transcripts)
    source_url text,
    source_title text,

    -- Timestamps
    created_at timestamptz default now() not null,
    updated_at timestamptz default now() not null,

    -- Constraints
    constraint unique_character_file unique (character_id, file_name)
);

-- Index for queries
create index idx_knowledge_files_character on public.knowledge_files(character_id);
create index idx_knowledge_files_type on public.knowledge_files(file_type);

-- ============================================================================
-- CHARACTER SHARES TABLE
-- Explicit sharing between users
-- ============================================================================

-- Enum for permission levels
create type share_permission as enum ('viewer', 'editor', 'admin');

create table public.character_shares (
    id uuid primary key default uuid_generate_v4(),

    -- The character being shared
    character_id uuid not null references public.characters(id) on delete cascade,

    -- Who it's shared with
    shared_with uuid not null references public.profiles(id) on delete cascade,

    -- Permission level
    permission share_permission default 'viewer' not null,

    -- Who created the share
    shared_by uuid not null references public.profiles(id),

    -- Timestamps
    created_at timestamptz default now() not null,

    -- Constraints
    constraint unique_share unique (character_id, shared_with)
);

-- Index for queries
create index idx_shares_character on public.character_shares(character_id);
create index idx_shares_user on public.character_shares(shared_with);

-- ============================================================================
-- CHARACTER VERSIONS TABLE (Optional - for version history)
-- Tracks persona version history
-- ============================================================================

create table public.character_versions (
    id uuid primary key default uuid_generate_v4(),

    -- Parent character
    character_id uuid not null references public.characters(id) on delete cascade,

    -- Version info
    version_number integer not null,

    -- Content snapshot
    persona_content text,
    persona_storage_path text,

    -- Change metadata
    change_summary text,
    created_by uuid references public.profiles(id),

    -- Timestamps
    created_at timestamptz default now() not null,

    -- Constraints
    constraint unique_version unique (character_id, version_number)
);

create index idx_versions_character on public.character_versions(character_id);

-- ============================================================================
-- UPDATED_AT TRIGGER
-- Automatically update updated_at timestamp
-- ============================================================================

create or replace function public.update_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create trigger update_profiles_updated_at
    before update on public.profiles
    for each row execute function public.update_updated_at();

create trigger update_characters_updated_at
    before update on public.characters
    for each row execute function public.update_updated_at();

create trigger update_knowledge_files_updated_at
    before update on public.knowledge_files
    for each row execute function public.update_updated_at();

-- ============================================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================================

-- Enable RLS on all tables
alter table public.profiles enable row level security;
alter table public.characters enable row level security;
alter table public.knowledge_files enable row level security;
alter table public.character_shares enable row level security;
alter table public.character_versions enable row level security;

-- PROFILES POLICIES
-- Users can view any profile (for display names)
create policy "Profiles are viewable by everyone"
    on public.profiles for select
    using (true);

-- Users can only update their own profile
create policy "Users can update own profile"
    on public.profiles for update
    using (auth.uid() = id);

-- CHARACTERS POLICIES
-- Helper function to check if user has access to a character
create or replace function public.has_character_access(char_id uuid, required_permission share_permission default 'viewer')
returns boolean as $$
declare
    char_record record;
    share_record record;
begin
    -- Get the character
    select * into char_record from public.characters where id = char_id;

    if not found then
        return false;
    end if;

    -- Owner has full access
    if char_record.owner_id = auth.uid() then
        return true;
    end if;

    -- Public characters are viewable by all
    if char_record.visibility = 'public' and required_permission = 'viewer' then
        return true;
    end if;

    -- Check explicit shares
    select * into share_record
    from public.character_shares
    where character_id = char_id
      and shared_with = auth.uid();

    if found then
        -- Check permission level
        if required_permission = 'viewer' then
            return true;
        elsif required_permission = 'editor' and share_record.permission in ('editor', 'admin') then
            return true;
        elsif required_permission = 'admin' and share_record.permission = 'admin' then
            return true;
        end if;
    end if;

    return false;
end;
$$ language plpgsql security definer;

-- Select: owner, public, or shared with user
create policy "Users can view accessible characters"
    on public.characters for select
    using (
        owner_id = auth.uid()
        or visibility = 'public'
        or exists (
            select 1 from public.character_shares
            where character_id = id and shared_with = auth.uid()
        )
    );

-- Insert: authenticated users can create characters
create policy "Authenticated users can create characters"
    on public.characters for insert
    with check (auth.uid() = owner_id);

-- Update: owner or editor/admin share
create policy "Owners and editors can update characters"
    on public.characters for update
    using (
        owner_id = auth.uid()
        or exists (
            select 1 from public.character_shares
            where character_id = id
              and shared_with = auth.uid()
              and permission in ('editor', 'admin')
        )
    );

-- Delete: owner only
create policy "Only owners can delete characters"
    on public.characters for delete
    using (owner_id = auth.uid());

-- KNOWLEDGE FILES POLICIES
-- Select: if user can view the parent character
create policy "Users can view knowledge files of accessible characters"
    on public.knowledge_files for select
    using (
        exists (
            select 1 from public.characters c
            where c.id = character_id
              and (
                  c.owner_id = auth.uid()
                  or c.visibility = 'public'
                  or exists (
                      select 1 from public.character_shares cs
                      where cs.character_id = c.id and cs.shared_with = auth.uid()
                  )
              )
        )
    );

-- Insert: if user can edit the parent character
create policy "Users can add knowledge files to editable characters"
    on public.knowledge_files for insert
    with check (
        exists (
            select 1 from public.characters c
            where c.id = character_id
              and (
                  c.owner_id = auth.uid()
                  or exists (
                      select 1 from public.character_shares cs
                      where cs.character_id = c.id
                        and cs.shared_with = auth.uid()
                        and cs.permission in ('editor', 'admin')
                  )
              )
        )
    );

-- Update: if user can edit the parent character
create policy "Users can update knowledge files of editable characters"
    on public.knowledge_files for update
    using (
        exists (
            select 1 from public.characters c
            where c.id = character_id
              and (
                  c.owner_id = auth.uid()
                  or exists (
                      select 1 from public.character_shares cs
                      where cs.character_id = c.id
                        and cs.shared_with = auth.uid()
                        and cs.permission in ('editor', 'admin')
                  )
              )
        )
    );

-- Delete: if user can edit the parent character
create policy "Users can delete knowledge files of editable characters"
    on public.knowledge_files for delete
    using (
        exists (
            select 1 from public.characters c
            where c.id = character_id
              and (
                  c.owner_id = auth.uid()
                  or exists (
                      select 1 from public.character_shares cs
                      where cs.character_id = c.id
                        and cs.shared_with = auth.uid()
                        and cs.permission in ('editor', 'admin')
                  )
              )
        )
    );

-- CHARACTER SHARES POLICIES
-- Select: character owner or the person it's shared with
create policy "Users can view shares they're involved in"
    on public.character_shares for select
    using (
        shared_with = auth.uid()
        or exists (
            select 1 from public.characters c
            where c.id = character_id and c.owner_id = auth.uid()
        )
    );

-- Insert: character owner or admin
create policy "Owners and admins can create shares"
    on public.character_shares for insert
    with check (
        exists (
            select 1 from public.characters c
            where c.id = character_id and c.owner_id = auth.uid()
        )
        or exists (
            select 1 from public.character_shares cs
            where cs.character_id = character_id
              and cs.shared_with = auth.uid()
              and cs.permission = 'admin'
        )
    );

-- Delete: character owner or admin
create policy "Owners and admins can delete shares"
    on public.character_shares for delete
    using (
        exists (
            select 1 from public.characters c
            where c.id = character_id and c.owner_id = auth.uid()
        )
        or exists (
            select 1 from public.character_shares cs
            where cs.character_id = character_id
              and cs.shared_with = auth.uid()
              and cs.permission = 'admin'
        )
    );

-- CHARACTER VERSIONS POLICIES
-- Same access as parent character
create policy "Users can view versions of accessible characters"
    on public.character_versions for select
    using (
        exists (
            select 1 from public.characters c
            where c.id = character_id
              and (
                  c.owner_id = auth.uid()
                  or c.visibility = 'public'
                  or exists (
                      select 1 from public.character_shares cs
                      where cs.character_id = c.id and cs.shared_with = auth.uid()
                  )
              )
        )
    );

create policy "Users can create versions of editable characters"
    on public.character_versions for insert
    with check (
        exists (
            select 1 from public.characters c
            where c.id = character_id
              and (
                  c.owner_id = auth.uid()
                  or exists (
                      select 1 from public.character_shares cs
                      where cs.character_id = c.id
                        and cs.shared_with = auth.uid()
                        and cs.permission in ('editor', 'admin')
                  )
              )
        )
    );

-- ============================================================================
-- STORAGE BUCKET POLICIES
-- Run these in the Supabase Dashboard under Storage
-- ============================================================================

-- Note: These need to be run via the Supabase Dashboard or API
-- as storage policies have a different syntax

/*
-- Create buckets
insert into storage.buckets (id, name, public)
values
    ('personas', 'personas', false),
    ('knowledge', 'knowledge', false);

-- Personas bucket policy: users can access their own files
create policy "Users can access own persona files"
    on storage.objects for all
    using (
        bucket_id = 'personas'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

-- Knowledge bucket policy: users can access their own files
create policy "Users can access own knowledge files"
    on storage.objects for all
    using (
        bucket_id = 'knowledge'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

-- Allow reading public character files
create policy "Users can read public character files"
    on storage.objects for select
    using (
        bucket_id in ('personas', 'knowledge')
        and exists (
            select 1 from public.characters c
            where c.visibility = 'public'
              and c.owner_id::text = (storage.foldername(name))[1]
              and c.id::text = (storage.foldername(name))[2]
        )
    );

-- Allow reading shared character files
create policy "Users can read shared character files"
    on storage.objects for select
    using (
        bucket_id in ('personas', 'knowledge')
        and exists (
            select 1 from public.characters c
            join public.character_shares cs on cs.character_id = c.id
            where cs.shared_with = auth.uid()
              and c.owner_id::text = (storage.foldername(name))[1]
              and c.id::text = (storage.foldername(name))[2]
        )
    );
*/
