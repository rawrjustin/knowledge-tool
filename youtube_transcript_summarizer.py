#!/usr/bin/env python3
"""
YouTube Transcript Summarizer

This script downloads YouTube videos, extracts transcripts using AssemblyAI,
and summarizes them using OpenAI's GPT models.
"""

import os
import sys
import argparse
import tempfile
from pathlib import Path

from typing import Optional, Sequence

import yt_dlp
import assemblyai as aai
from dotenv import load_dotenv
from openai import OpenAI


# Load environment variables from a .env file if present
load_dotenv()


def sanitize_filename(name: str) -> str:
    """
    Create a filesystem-friendly filename slug from a string.
    """
    sanitized = ''.join(
        c if c.isalnum() or c in ('-', '_') else '_'
        for c in name.strip()
    )
    sanitized = sanitized.strip('_')
    return sanitized or "youtube_video"


def format_timestamp(ms: Optional[int]) -> str:
    """
    Convert millisecond timestamps to HH:MM:SS (or MM:SS) strings.
    """
    if ms is None:
        return ""

    total_seconds = max(int(ms / 1000), 0)
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)

    if hours:
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
    return f"{minutes:02d}:{seconds:02d}"


def format_speaker_labeled_transcript(transcript_obj: aai.Transcript) -> str:
    """
    Build a human-readable transcript with speaker labels from utterances.
    """
    utterances = getattr(transcript_obj, "utterances", None) or []
    if not utterances:
        return transcript_obj.text

    formatted_lines = []
    for utterance in utterances:
        speaker = getattr(utterance, "speaker", "Unknown")
        text = (getattr(utterance, "text", "") or "").strip()
        start = format_timestamp(getattr(utterance, "start", None))
        end = format_timestamp(getattr(utterance, "end", None))

        if start and end:
            timestamp = f"[{start} - {end}] "
        elif start:
            timestamp = f"[{start}] "
        else:
            timestamp = ""

        formatted_lines.append(f"{timestamp}Speaker {speaker}: {text}")

    return "\n".join(formatted_lines)


def download_youtube_audio(
    video_url: str,
    output_dir: str = None,
    remote_components: Optional[Sequence[str] | str] = "ejs:github"
) -> tuple[str, dict]:
    """
    Download audio from a YouTube video.

    Args:
        video_url: YouTube video URL
        output_dir: Directory to save the audio file (defaults to temp directory)
        remote_components: yt-dlp remote components spec (e.g., "ejs:github")

    Returns:
        Tuple containing the downloaded audio file path and the extracted metadata
    """
    if output_dir is None:
        output_dir = tempfile.gettempdir()

    output_template = os.path.join(output_dir, '%(id)s.%(ext)s')

    ydl_opts = {
        'format': 'm4a/bestaudio/best',
        'outtmpl': output_template,
        'postprocessors': [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': 'm4a',
        }],
        'quiet': False,
        'no_warnings': False,
    }

    if remote_components:
        if isinstance(remote_components, str):
            components = [comp.strip() for comp in remote_components.split(",") if comp.strip()]
        else:
            components = [comp for comp in remote_components if comp]
        if components:
            ydl_opts['remote_components'] = components

    print(f"Downloading audio from: {video_url}")

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(video_url, download=True)
        video_id = info['id']
        audio_file = os.path.join(output_dir, f"{video_id}.m4a")

    print(f"Audio downloaded to: {audio_file}")
    return audio_file, info


def transcribe_audio(audio_file: str, assemblyai_api_key: str) -> dict:
    """
    Transcribe audio file using AssemblyAI.

    Args:
        audio_file: Path to the audio file
        assemblyai_api_key: AssemblyAI API key

    Returns:
        Dictionary with raw transcript text, speaker-labeled transcript, and utterances
    """
    print(f"Transcribing audio file: {audio_file}")

    aai.settings.api_key = assemblyai_api_key
    transcriber = aai.Transcriber()
    config = aai.TranscriptionConfig(speaker_labels=True)

    transcript = transcriber.transcribe(audio_file, config=config)

    if transcript.status == aai.TranscriptStatus.error:
        raise Exception(f"Transcription failed: {transcript.error}")

    print("Transcription completed successfully")
    speaker_formatted = format_speaker_labeled_transcript(transcript)
    return {
        "raw_text": transcript.text,
        "speaker_transcript": speaker_formatted,
        "utterances": getattr(transcript, "utterances", None) or []
    }


def summarize_transcript(transcript: str, openai_api_key: str, model: str = "gpt-5") -> str:
    """
    Summarize transcript using OpenAI's GPT models.

    Args:
        transcript: The transcript text to summarize
        openai_api_key: OpenAI API key
    model: OpenAI model to use (default: gpt-5, can also use other GPT series models)

    Returns:
        Summary text
    """
    print(f"Summarizing transcript using {model}...")

    client = OpenAI(api_key=openai_api_key)

    response = client.chat.completions.create(
        model=model,
        messages=[
            {
                "role": "system",
                "content": "You are a helpful assistant that creates informative summaries of video transcripts. Try not to leave too much information out and capture as much vivid detail and useful information as possible. The more unique detail, the better as this detail will be surfaced later on."
            },
            {
                "role": "user",
                "content": f"Please provide a comprehensive summary of the following video transcript formatted in a way that's optimied for Retrieval-Augmented Generation (RAG) systems to retain context and user information:\n\n{transcript}"
            }
        ],
    )

    summary = response.choices[0].message.content
    print("Summary generated successfully")
    return summary


def process_youtube_video(
    video_url: str,
    assemblyai_api_key: str,
    openai_api_key: str,
    model: str = "gpt-5",
    keep_audio: bool = False,
    output_dir: str = None,
    remote_components: Optional[Sequence[str] | str] = "ejs:github"
) -> dict:
    """
    Process a YouTube video: download, transcribe, and summarize.

    Args:
        video_url: YouTube video URL
        assemblyai_api_key: AssemblyAI API key
        openai_api_key: OpenAI API key
        model: OpenAI model to use for summarization
        keep_audio: Whether to keep the downloaded audio file
        output_dir: Directory for temporary files
        remote_components: yt-dlp remote components spec or None to disable

    Returns:
        Dictionary with transcript and summary
    """
    audio_file = None
    video_metadata = {}

    try:
        # Download audio
        audio_file, video_metadata = download_youtube_audio(
            video_url,
            output_dir,
            remote_components=remote_components
        )

        # Transcribe
        transcript_data = transcribe_audio(audio_file, assemblyai_api_key)

        # Summarize
        summary = summarize_transcript(transcript_data["speaker_transcript"], openai_api_key, model)

        return {
            "video_url": video_url,
            "video_title": video_metadata.get("title", "Unknown Title"),
            "transcript": transcript_data["speaker_transcript"],
            "transcript_raw": transcript_data["raw_text"],
            "utterances": transcript_data["utterances"],
            "summary": summary,
            "audio_file": audio_file if keep_audio else None
        }

    finally:
        # Clean up audio file if not keeping it
        if audio_file and not keep_audio and os.path.exists(audio_file):
            try:
                os.remove(audio_file)
                print(f"Cleaned up audio file: {audio_file}")
            except Exception as e:
                print(f"Warning: Could not remove audio file: {e}")


def write_output_file(path: Path, title: str, url: str, heading: str, content: str) -> None:
    """
    Write a formatted text file containing the video title, URL, and content.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(f"Title: {title}\n")
        f.write(f"Original URL: {url}\n\n")
        f.write(f"{heading}\n")
        f.write("=" * len(heading) + "\n\n")
        f.write(content)


def main():
    parser = argparse.ArgumentParser(
        description="Download YouTube videos, extract transcripts, and summarize them using AI"
    )
    parser.add_argument(
        "video_url",
        help="YouTube video URL"
    )
    parser.add_argument(
        "--assemblyai-key",
        help="AssemblyAI API key (or set ASSEMBLYAI_API_KEY env var)",
        default=os.getenv("ASSEMBLYAI_API_KEY")
    )
    parser.add_argument(
        "--openai-key",
        help="OpenAI API key (or set OPENAI_API_KEY env var)",
        default=os.getenv("OPENAI_API_KEY")
    )
    parser.add_argument(
        "--model",
        help="OpenAI model to use (default: gpt-5)",
        default="gpt-5"
    )
    parser.add_argument(
        "--keep-audio",
        action="store_true",
        help="Keep the downloaded audio file"
    )
    parser.add_argument(
        "--output-dir",
        help="Directory for output files (default: temp directory)",
        default=None
    )
    parser.add_argument(
        "--remote-components",
        help="Comma-separated yt-dlp remote components specs (set to '' to disable; default: ejs:github)",
        default="ejs:github"
    )
    parser.add_argument(
        "--save-transcript",
        help="Save transcript to a file",
        default=None
    )
    parser.add_argument(
        "--save-summary",
        help="Save summary to a file",
        default=None
    )

    args = parser.parse_args()

    # Validate API keys
    if not args.assemblyai_key:
        print("Error: AssemblyAI API key is required. Set ASSEMBLYAI_API_KEY env var or use --assemblyai-key")
        sys.exit(1)

    if not args.openai_key:
        print("Error: OpenAI API key is required. Set OPENAI_API_KEY env var or use --openai-key")
        sys.exit(1)

    # Process video
    try:
        result = process_youtube_video(
            video_url=args.video_url,
            assemblyai_api_key=args.assemblyai_key,
            openai_api_key=args.openai_key,
            model=args.model,
            keep_audio=args.keep_audio,
            output_dir=args.output_dir,
            remote_components=(args.remote_components or None)
        )

        # Display results
        print("\n" + "=" * 80)
        print("VIDEO")
        print("=" * 80)
        print(f"Title: {result['video_title']}")
        print(f"Original URL: {result['video_url']}")
        print("\n" + "=" * 80)
        print("SUMMARY")
        print("=" * 80)
        print(result["summary"])
        print("\n" + "=" * 80)
        print("TRANSCRIPT")
        print("=" * 80)
        print(result["transcript"])
        print("=" * 80)

        # Determine output locations
        script_dir = Path(__file__).resolve().parent
        base_name = sanitize_filename(result["video_title"])
        summary_path = Path(args.save_summary) if args.save_summary else script_dir / f"{base_name}_summary.txt"
        transcript_path = Path(args.save_transcript) if args.save_transcript else script_dir / f"{base_name}_transcript.txt"

        # Save summary and transcript files (always generate .txt files)
        write_output_file(summary_path, result["video_title"], result["video_url"], "Summary", result["summary"])
        print(f"\nSummary saved to: {summary_path}")

        write_output_file(transcript_path, result["video_title"], result["video_url"], "Transcript", result["transcript"])
        print(f"Transcript saved to: {transcript_path}")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
