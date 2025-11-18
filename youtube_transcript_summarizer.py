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

import yt_dlp
import assemblyai as aai
from openai import OpenAI


def download_youtube_audio(video_url: str, output_dir: str = None) -> str:
    """
    Download audio from a YouTube video.

    Args:
        video_url: YouTube video URL
        output_dir: Directory to save the audio file (defaults to temp directory)

    Returns:
        Path to the downloaded audio file
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

    print(f"Downloading audio from: {video_url}")

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(video_url, download=True)
        video_id = info['id']
        audio_file = os.path.join(output_dir, f"{video_id}.m4a")

    print(f"Audio downloaded to: {audio_file}")
    return audio_file


def transcribe_audio(audio_file: str, assemblyai_api_key: str) -> str:
    """
    Transcribe audio file using AssemblyAI.

    Args:
        audio_file: Path to the audio file
        assemblyai_api_key: AssemblyAI API key

    Returns:
        Transcript text
    """
    print(f"Transcribing audio file: {audio_file}")

    aai.settings.api_key = assemblyai_api_key
    transcriber = aai.Transcriber()

    transcript = transcriber.transcribe(audio_file)

    if transcript.status == aai.TranscriptStatus.error:
        raise Exception(f"Transcription failed: {transcript.error}")

    print("Transcription completed successfully")
    return transcript.text


def summarize_transcript(transcript: str, openai_api_key: str, model: str = "gpt-4o") -> str:
    """
    Summarize transcript using OpenAI's GPT models.

    Args:
        transcript: The transcript text to summarize
        openai_api_key: OpenAI API key
        model: OpenAI model to use (default: gpt-4o, can also use gpt-4, gpt-3.5-turbo, etc.)

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
                "content": "You are a helpful assistant that creates concise and informative summaries of video transcripts."
            },
            {
                "role": "user",
                "content": f"Please provide a comprehensive summary of the following video transcript:\n\n{transcript}"
            }
        ],
        temperature=0.7,
    )

    summary = response.choices[0].message.content
    print("Summary generated successfully")
    return summary


def process_youtube_video(
    video_url: str,
    assemblyai_api_key: str,
    openai_api_key: str,
    model: str = "gpt-4o",
    keep_audio: bool = False,
    output_dir: str = None
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

    Returns:
        Dictionary with transcript and summary
    """
    audio_file = None

    try:
        # Download audio
        audio_file = download_youtube_audio(video_url, output_dir)

        # Transcribe
        transcript = transcribe_audio(audio_file, assemblyai_api_key)

        # Summarize
        summary = summarize_transcript(transcript, openai_api_key, model)

        return {
            "video_url": video_url,
            "transcript": transcript,
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
        help="OpenAI model to use (default: gpt-4o)",
        default="gpt-4o"
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
            output_dir=args.output_dir
        )

        # Display results
        print("\n" + "=" * 80)
        print("TRANSCRIPT")
        print("=" * 80)
        print(result["transcript"])
        print("\n" + "=" * 80)
        print("SUMMARY")
        print("=" * 80)
        print(result["summary"])
        print("=" * 80)

        # Save to files if requested
        if args.save_transcript:
            with open(args.save_transcript, 'w') as f:
                f.write(result["transcript"])
            print(f"\nTranscript saved to: {args.save_transcript}")

        if args.save_summary:
            with open(args.save_summary, 'w') as f:
                f.write(result["summary"])
            print(f"Summary saved to: {args.save_summary}")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
