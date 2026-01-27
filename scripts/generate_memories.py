#!/usr/bin/env python3
"""
Generate retrieval-optimized memory JSONL from character persona documents.

This script takes a character's persona markdown file and generates a JSONL
knowledge base optimized for RAG retrieval.

Usage:
    python generate_memories.py --character "Jake Paul"
    python generate_memories.py --character "Jake Paul" --output memories.jsonl
"""

import os
import json
import argparse
from pathlib import Path
from openai import OpenAI

# =========================
# Config
# =========================

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "sk-...")
DEFAULT_BASE_PATH = "/Users/justin-genies/Code/CharacterPrompts/Personas"
MODEL = "gpt-4o"


def get_memory_generation_prompt(character_name: str) -> str:
    """Generate the prompt for creating memories from a persona document."""
    return f'''You are building a **retrieval-augmented knowledge base for the character {character_name}** using the provided document.

Your task is to **process the document into multiple independent knowledge base entries**, where **each entry represents a single retrievable unit** suitable for semantic + keyword search.

---

### **Core Requirements**

#### **1. Output Format**

* Output must be a **JSONL file** (one valid JSON object per line).
* Each line represents **one knowledge base entry**.
* Do **not** wrap the output in markdown or code fences.

#### **2. Sectioning**

* Break the document into **logical sections** that should exist as **standalone retrievable entries** (e.g., overview, personality, leadership style, relationships, values, fears, habits, hobbies, skills, appearance, media appearances, etc.).
* Prefer **fine-grained, concept-focused entries** over large, mixed sections.
* Each entry should answer **one clear retrieval intent**.

#### **3. Narrative Voice**

* Rewrite every entry as a **single coherent paragraph**.
* Write **from {character_name}'s point of view in third person**.
* Use constructions such as:

  * *"{character_name} is…"*
  * *"{character_name} has…"*
  * *"{character_name} believes…"*
  * *"{character_name} often…"*
* Do **not** quote or reference the original document directly.

#### **4. Content Fidelity**

* Preserve factual accuracy from the document.
* Do **not** invent traits, events, or motivations not supported by the text.
* You may **synthesize and rephrase**, but must remain grounded in the source.

---

### **Keyword Optimization (Critical for Retrieval)**

Each entry must include a **carefully curated `keywords` array** designed to maximize retrieval quality.

When generating keywords:

* Include **explicit terms** present in the document (names, titles, places, roles).
* Add **implicit or inferred search terms** that users are likely to query even if the document does not use those exact words.

  * Example:

    * Leadership described → include `"leadership"`, `"team leader"`, `"authority"`
    * Enjoyment or recurring activities → include `"hobbies"`, `"interests"`
    * Protective or loyal behavior → include `"loyalty"`, `"protective"`, `"friendship"`
* Include **user-centric phrasing**, not just canonical labels:

  * `"{character_name} personality"`
  * `"how {character_name} acts"`
  * `"what {character_name} cares about"`
* Prefer **searchable, human-likely phrases** over abstract tags.

Aim for **5–12 keywords per entry**, ordered by importance.

---

### **Schema**

Each JSONL entry must follow this structure:

```json
{{
  "id": "<stable_snake_case_identifier>",
  "section": "<Human-readable section title>",
  "content": "<Single paragraph written in third-person from {character_name}'s POV>",
  "keywords": ["keyword1", "keyword2", "..."]
}}
```

* `id`: concise, stable, snake_case, suitable for indexing.
* `section`: short, descriptive title.
* `content`: exactly one paragraph.
* `keywords`: retrieval-optimized as described above.

---

### **Expected Output Example (Illustrative Only)**

```json
{{"id":"overview","section":"Overview","content":"{character_name} is a central figure known for their distinctive personality and approach to life. They value authenticity, hard work, and standing up for what they believe in.","keywords":["{character_name}","overview","main character","personality","{character_name} personality"]}}
```

Now process the following document and generate the JSONL knowledge base:
'''


def find_persona_file(character_name: str, base_path: str = DEFAULT_BASE_PATH) -> Path | None:
    """Find the latest persona markdown file for a character."""
    character_path = Path(base_path) / character_name

    if not character_path.exists():
        print(f"Character directory not found: {character_path}")
        return None

    # Find all markdown files
    md_files = list(character_path.glob("*.md"))

    if not md_files:
        print(f"No persona files found for: {character_name}")
        return None

    # Sort by version number (v2, v3, etc.) and return latest
    def get_version(path: Path) -> int:
        name = path.stem.lower()
        if 'v' in name:
            try:
                return int(name.split('v')[-1])
            except ValueError:
                return 1
        return 1

    md_files.sort(key=get_version, reverse=True)
    return md_files[0]


def generate_memories(
    character_name: str,
    base_path: str = DEFAULT_BASE_PATH,
    output_file: str | None = None,
    dry_run: bool = False
) -> str | None:
    """Generate memory JSONL from a character's persona document."""

    # Find persona file
    persona_file = find_persona_file(character_name, base_path)
    if not persona_file:
        return None

    print(f"Using persona file: {persona_file}")

    # Read persona content
    with open(persona_file, 'r', encoding='utf-8') as f:
        persona_content = f.read()

    print(f"Persona content: {len(persona_content)} characters")

    if dry_run:
        print(f"\n=== DRY RUN ===")
        print(f"Would generate memories from: {persona_file}")
        print(f"Character: {character_name}")
        print(f"Content preview:\n{persona_content[:500]}...")
        return None

    # Initialize OpenAI client
    client = OpenAI(api_key=OPENAI_API_KEY)

    # Generate memories
    print(f"Generating memories for {character_name}...")

    prompt = get_memory_generation_prompt(character_name)

    response = client.chat.completions.create(
        model=MODEL,
        messages=[
            {"role": "system", "content": prompt},
            {"role": "user", "content": persona_content}
        ],
        temperature=0.3,
        max_tokens=8000
    )

    memories_jsonl = response.choices[0].message.content

    # Clean up response (remove any markdown code fences if present)
    if memories_jsonl.startswith("```"):
        lines = memories_jsonl.split('\n')
        # Remove first and last lines if they're code fences
        if lines[0].startswith("```"):
            lines = lines[1:]
        if lines[-1].startswith("```"):
            lines = lines[:-1]
        memories_jsonl = '\n'.join(lines)

    # Validate JSONL
    valid_lines = []
    for i, line in enumerate(memories_jsonl.strip().split('\n'), 1):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            valid_lines.append(json.dumps(entry))  # Re-serialize to ensure consistent formatting
        except json.JSONDecodeError as e:
            print(f"Warning: Invalid JSON on line {i}: {e}")
            continue

    if not valid_lines:
        print("Error: No valid JSONL entries generated")
        return None

    memories_jsonl = '\n'.join(valid_lines)
    print(f"Generated {len(valid_lines)} memory entries")

    # Determine output path
    if output_file:
        output_path = Path(output_file)
    else:
        knowledge_dir = Path(base_path) / character_name / "Knowledge"
        knowledge_dir.mkdir(exist_ok=True)
        output_path = knowledge_dir / "character_memories.jsonl"

    # Write output
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(memories_jsonl)

    print(f"Saved memories to: {output_path}")
    return str(output_path)


def list_available_characters(base_path: str = DEFAULT_BASE_PATH) -> list[tuple[str, bool]]:
    """List all characters and whether they have existing memories."""
    base = Path(base_path)
    characters = []

    for char_dir in base.iterdir():
        if char_dir.is_dir():
            # Check for persona files
            md_files = list(char_dir.glob("*.md"))
            if md_files:
                # Check for existing memories
                knowledge_dir = char_dir / "Knowledge"
                has_memories = (knowledge_dir / "character_memories.jsonl").exists()
                characters.append((char_dir.name, has_memories))

    return characters


def main():
    parser = argparse.ArgumentParser(
        description="Generate retrieval-optimized memories from character persona",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate memories for Jake Paul
  python generate_memories.py --character "Jake Paul"

  # Generate with custom output file
  python generate_memories.py --character "Jake Paul" --output jake_memories.jsonl

  # Dry run to see what would be processed
  python generate_memories.py --character "Jake Paul" --dry-run

  # List available characters
  python generate_memories.py --list-characters

Environment Variables:
  OPENAI_API_KEY - OpenAI API key for GPT-4
        """
    )

    parser.add_argument(
        "--character", "-c",
        type=str,
        help="Character name (folder name in Personas directory)"
    )

    parser.add_argument(
        "--base-path", "-p",
        type=str,
        default=DEFAULT_BASE_PATH,
        help=f"Base path to Personas directory (default: {DEFAULT_BASE_PATH})"
    )

    parser.add_argument(
        "--output", "-o",
        type=str,
        help="Output file path (default: Knowledge/character_memories.jsonl)"
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be processed without generating"
    )

    parser.add_argument(
        "--list-characters",
        action="store_true",
        help="List all characters with persona files"
    )

    args = parser.parse_args()

    # Handle list-characters
    if args.list_characters:
        print(f"\nCharacters in: {args.base_path}\n")
        characters = list_available_characters(args.base_path)
        if characters:
            for name, has_memories in sorted(characters):
                status = "[has memories]" if has_memories else ""
                print(f"  {name} {status}")
        else:
            print("  No characters found")
        return

    # Validate required args
    if not args.character:
        parser.error("--character is required")

    # Run generation
    generate_memories(
        character_name=args.character,
        base_path=args.base_path,
        output_file=args.output,
        dry_run=args.dry_run
    )


if __name__ == "__main__":
    main()
