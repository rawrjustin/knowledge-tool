# KnowledgeTool Scripts

Scripts for managing character knowledge bases and uploading to Pinecone for RAG retrieval.

## Setup

Install required dependencies:

```bash
pip install openai pinecone langchain-openai langchain-pinecone
```

Set environment variables (or edit the scripts directly):

```bash
export OPENAI_API_KEY="sk-..."
export PINECONE_API_KEY="pcsk_..."
export PINECONE_INDEX="avatar-knowledge-te-3-large-256-dev"  # or prod
```

## Scripts

### 1. `generate_memories.py`

Generates retrieval-optimized memory JSONL from a character's persona document using GPT-4.

**What it does:**
- Reads the character's persona markdown file (e.g., `jakepaul.md`)
- Uses GPT-4 to break it into logical, retrievable sections
- Outputs JSONL with optimized keywords for semantic search
- Saves to `{Character}/Knowledge/character_memories.jsonl`

**Usage:**

```bash
# Generate memories for a character
python generate_memories.py --character "Jake Paul"

# Custom output file
python generate_memories.py --character "Jake Paul" --output custom.jsonl

# Dry run (preview without generating)
python generate_memories.py --character "Jake Paul" --dry-run

# List all characters
python generate_memories.py --list-characters
```

**Output format:**
```json
{"id":"overview","section":"Overview","content":"Jake Paul is a prominent figure in boxing and social media...","keywords":["Jake Paul","boxer","YouTuber","personality"]}
{"id":"boxing_career","section":"Boxing Career","content":"Jake Paul has transformed from a social media personality...","keywords":["boxing","career","fights","training"]}
```

### 2. `upload_to_pinecone.py`

Uploads character knowledge base JSONL files to Pinecone for RAG retrieval.

**What it does:**
- Finds all JSONL files in a character's Knowledge directory
- Parses both formats:
  - Character memories: `{"id":"...","section":"...","content":"...","keywords":[...]}`
  - Video knowledge: `{"id":"t0-10","url":"...","text":"...","tags":[...]}`
- Embeds content using OpenAI `text-embedding-3-large`
- Uploads to Pinecone with proper namespacing

**Usage:**

```bash
# Upload to a namespace
python upload_to_pinecone.py --character "Jake Paul" --namespace "CHAR_073ca002-fd77-4eaf-8745-d5381b8df005"

# Dry run (preview without uploading)
python upload_to_pinecone.py --character "Jake Paul" --namespace "CHAR_test" --dry-run

# Clear existing vectors before upload
python upload_to_pinecone.py --character "Jake Paul" --namespace "CHAR_test" --clear

# Use production index
python upload_to_pinecone.py --character "Jake Paul" --namespace "CHAR_xxx" --index avatar-knowledge-te-3-large-256-prod

# List characters with knowledge files
python upload_to_pinecone.py --list-characters

# List records in a namespace
python upload_to_pinecone.py --list-namespace "CHAR_073ca002-fd77-4eaf-8745-d5381b8df005"
```

## Workflow

### Full workflow for a new character:

1. **Create character in KnowledgeTool app** (from Wikipedia, YouTube, or original)
   - This generates the persona markdown and video knowledge JSONL

2. **Generate memories from persona:**
   ```bash
   python generate_memories.py --character "Jake Paul"
   ```

3. **Upload all knowledge to Pinecone:**
   ```bash
   python upload_to_pinecone.py --character "Jake Paul" --namespace "CHAR_xxxxx"
   ```

### For existing characters (just video knowledge):

```bash
python upload_to_pinecone.py --character "Jake Paul" --namespace "CHAR_xxxxx"
```

## Pinecone Configuration

| Environment | Index Name | API Key |
|-------------|------------|---------|
| Development | `avatar-knowledge-te-3-large-256-dev` | `pcsk_2Tq4uT_...` |
| Production | `avatar-knowledge-te-3-large-256-prod` | `pcsk_HtbEX_...` |

## File Structure

```
Personas/
├── Jake Paul/
│   ├── jakepaul.md                    # Persona document (ASP-1 format)
│   ├── jakepaulv2.md                  # Version 2
│   └── Knowledge/
│       ├── character_memories.jsonl   # Generated from persona
│       ├── structured_knowledge_base.jsonl  # From YouTube videos
│       ├── video_transcripts.txt      # Full transcripts
│       └── dialogue_examples.txt      # Characteristic quotes
```

## JSONL Formats

### Character Memories (from `generate_memories.py`):
```json
{
  "id": "stable_snake_case_id",
  "section": "Human-readable Section Title",
  "content": "Single paragraph in third-person POV about the character...",
  "keywords": ["keyword1", "keyword2", "character name", "topic"]
}
```

### Video Knowledge (from YouTube transcription):
```json
{
  "id": "t0-10",
  "url": "https://youtube.com/watch?v=...",
  "title": "Video Title",
  "chunk_summary": "Main topic of this segment",
  "background": "How this connects to the overall video",
  "text": "120-160 word summary in third-person POV...",
  "tags": ["tag1", "tag2"]
}
```
