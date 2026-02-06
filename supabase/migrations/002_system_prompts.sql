-- KnowledgeTool Supabase Schema
-- Migration: 002_system_prompts
-- Description: Add system prompts table for centralized prompt template management

-- ============================================================================
-- SYSTEM PROMPTS TABLE
-- Stores versioned system prompt templates (ASP, CSP, RSP)
-- ============================================================================

create table public.system_prompts (
    id uuid primary key default uuid_generate_v4(),

    -- Prompt identification
    prompt_type system_prompt_type not null,  -- Uses existing enum: 'ASP', 'CSP', 'RSP'
    version integer not null default 1,

    -- Content
    template_content text not null,

    -- Metadata
    name text not null,
    description text,
    is_active boolean default true not null,

    -- Timestamps
    created_at timestamptz default now() not null,
    updated_at timestamptz default now() not null,

    -- Constraints: only one prompt per type/version combination
    constraint unique_prompt_version unique (prompt_type, version)
);

-- Index for common queries
create index idx_system_prompts_type on public.system_prompts(prompt_type);
create index idx_system_prompts_active on public.system_prompts(is_active);

-- Add updated_at trigger
create trigger update_system_prompts_updated_at
    before update on public.system_prompts
    for each row execute function public.update_updated_at();

-- ============================================================================
-- ROW LEVEL SECURITY
-- System prompts are readable by all authenticated users
-- Only admins can modify (via service role key)
-- ============================================================================

alter table public.system_prompts enable row level security;

-- All authenticated users can read system prompts
create policy "System prompts viewable by authenticated users"
    on public.system_prompts for select
    using (auth.uid() is not null);

-- Note: Insert/Update/Delete operations should be done via service role key
-- or by adding an admin role check if needed in the future
