-- ============================================================================
-- Remove character_shares and simplify RLS to owner-only access
-- ============================================================================
-- The app only needs users to save and sync their own characters/documents.
-- character_shares and visibility were unused, and the cross-table RLS
-- references between characters and character_shares caused infinite recursion.
-- ============================================================================

-- ============================================================================
-- Drop all policies that reference character_shares or visibility
-- ============================================================================

-- Characters
drop policy if exists "Users can view accessible characters" on public.characters;
drop policy if exists "Owners and editors can update characters" on public.characters;
drop policy if exists "Authenticated users can create characters" on public.characters;
drop policy if exists "Only owners can delete characters" on public.characters;

-- Knowledge files
drop policy if exists "Users can view knowledge files of accessible characters" on public.knowledge_files;
drop policy if exists "Users can add knowledge files to editable characters" on public.knowledge_files;
drop policy if exists "Users can update knowledge files of editable characters" on public.knowledge_files;
drop policy if exists "Users can delete knowledge files of editable characters" on public.knowledge_files;

-- Character shares
drop policy if exists "Users can view shares they're involved in" on public.character_shares;
drop policy if exists "Owners and admins can create shares" on public.character_shares;
drop policy if exists "Owners and admins can delete shares" on public.character_shares;

-- Character versions
drop policy if exists "Users can view versions of accessible characters" on public.character_versions;
drop policy if exists "Users can create versions of editable characters" on public.character_versions;

-- ============================================================================
-- Drop the sharing infrastructure
-- ============================================================================

drop function if exists public.has_character_access cascade;
drop table if exists public.character_shares;
drop type if exists share_permission cascade;

-- Drop visibility column and type (everything is owner-only now)
alter table public.characters drop column if exists visibility;
drop type if exists character_visibility;

-- ============================================================================
-- Recreate simple owner-only policies
-- ============================================================================

-- CHARACTERS: users can only access their own
create policy "Users can view own characters"
    on public.characters for select
    using (owner_id = auth.uid());

create policy "Users can create characters"
    on public.characters for insert
    with check (owner_id = auth.uid());

create policy "Users can update own characters"
    on public.characters for update
    using (owner_id = auth.uid());

create policy "Users can delete own characters"
    on public.characters for delete
    using (owner_id = auth.uid());

-- KNOWLEDGE FILES: users can access files for their own characters
create policy "Users can view own knowledge files"
    on public.knowledge_files for select
    using (
        exists (
            select 1 from public.characters c
            where c.id = character_id and c.owner_id = auth.uid()
        )
    );

create policy "Users can add knowledge files"
    on public.knowledge_files for insert
    with check (
        exists (
            select 1 from public.characters c
            where c.id = character_id and c.owner_id = auth.uid()
        )
    );

create policy "Users can update own knowledge files"
    on public.knowledge_files for update
    using (
        exists (
            select 1 from public.characters c
            where c.id = character_id and c.owner_id = auth.uid()
        )
    );

create policy "Users can delete own knowledge files"
    on public.knowledge_files for delete
    using (
        exists (
            select 1 from public.characters c
            where c.id = character_id and c.owner_id = auth.uid()
        )
    );

-- CHARACTER VERSIONS: users can access versions of their own characters
create policy "Users can view own character versions"
    on public.character_versions for select
    using (
        exists (
            select 1 from public.characters c
            where c.id = character_id and c.owner_id = auth.uid()
        )
    );

create policy "Users can create character versions"
    on public.character_versions for insert
    with check (
        exists (
            select 1 from public.characters c
            where c.id = character_id and c.owner_id = auth.uid()
        )
    );
