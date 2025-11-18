# YouTube Transcript Summarizer

A Python script that downloads YouTube videos, extracts transcripts using AssemblyAI, and generates summaries using OpenAI's GPT models.

## Features

- Download audio from YouTube videos using yt-dlp
- Transcribe audio using AssemblyAI's powerful speech recognition
- Summarize transcripts using OpenAI's GPT models (GPT-4o, GPT-4, etc.)
- Save transcripts and summaries to files
- Command-line interface for easy usage

## Prerequisites

- Python 3.7 or higher
- FFmpeg (required by yt-dlp for audio extraction)

### Installing FFmpeg

**macOS:**
```bash
brew install ffmpeg
```

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install ffmpeg
```

**Windows:**
Download from [ffmpeg.org](https://ffmpeg.org/download.html) or use chocolatey:
```bash
choco install ffmpeg
```

## Installation

1. Clone this repository:
```bash
git clone <repository-url>
cd knowledge-tool
```

2. Install Python dependencies:
```bash
pip install -r requirements.txt
```

3. Set up your API keys:

Copy the `.env.example` file to `.env`:
```bash
cp .env.example .env
```

Edit `.env` and add your API keys:
- **AssemblyAI API Key**: Sign up at [assemblyai.com](https://www.assemblyai.com/) to get your free API key
- **OpenAI API Key**: Get your key from [platform.openai.com](https://platform.openai.com/api-keys)

Alternatively, you can pass API keys as command-line arguments.

## Usage

### Basic Usage

```bash
python youtube_transcript_summarizer.py "https://www.youtube.com/watch?v=VIDEO_ID"
```

This will:
1. Download the audio from the YouTube video
2. Transcribe it using AssemblyAI
3. Generate a summary using GPT-4o
4. Display both the transcript and summary in the terminal

### Using Environment Variables

Set your API keys as environment variables:

```bash
export ASSEMBLYAI_API_KEY="your_assemblyai_api_key"
export OPENAI_API_KEY="your_openai_api_key"

python youtube_transcript_summarizer.py "https://www.youtube.com/watch?v=VIDEO_ID"
```

### Using Command-Line Arguments

```bash
python youtube_transcript_summarizer.py \
  "https://www.youtube.com/watch?v=VIDEO_ID" \
  --assemblyai-key "your_assemblyai_key" \
  --openai-key "your_openai_key"
```

### Advanced Options

**Use a different OpenAI model:**
```bash
python youtube_transcript_summarizer.py \
  "https://www.youtube.com/watch?v=VIDEO_ID" \
  --model "gpt-4"
```

**Save transcript and summary to files:**
```bash
python youtube_transcript_summarizer.py \
  "https://www.youtube.com/watch?v=VIDEO_ID" \
  --save-transcript "transcript.txt" \
  --save-summary "summary.txt"
```

**Keep the downloaded audio file:**
```bash
python youtube_transcript_summarizer.py \
  "https://www.youtube.com/watch?v=VIDEO_ID" \
  --keep-audio
```

**Specify output directory:**
```bash
python youtube_transcript_summarizer.py \
  "https://www.youtube.com/watch?v=VIDEO_ID" \
  --output-dir "./downloads"
```

### Full Command-Line Options

```
usage: youtube_transcript_summarizer.py [-h] [--assemblyai-key ASSEMBLYAI_KEY]
                                        [--openai-key OPENAI_KEY] [--model MODEL]
                                        [--keep-audio] [--output-dir OUTPUT_DIR]
                                        [--save-transcript SAVE_TRANSCRIPT]
                                        [--save-summary SAVE_SUMMARY]
                                        video_url

Download YouTube videos, extract transcripts, and summarize them using AI

positional arguments:
  video_url             YouTube video URL

optional arguments:
  -h, --help            show this help message and exit
  --assemblyai-key ASSEMBLYAI_KEY
                        AssemblyAI API key (or set ASSEMBLYAI_API_KEY env var)
  --openai-key OPENAI_KEY
                        OpenAI API key (or set OPENAI_API_KEY env var)
  --model MODEL         OpenAI model to use (default: gpt-4o)
  --keep-audio          Keep the downloaded audio file
  --output-dir OUTPUT_DIR
                        Directory for output files (default: temp directory)
  --save-transcript SAVE_TRANSCRIPT
                        Save transcript to a file
  --save-summary SAVE_SUMMARY
                        Save summary to a file
```

## Example

```bash
# Set your API keys
export ASSEMBLYAI_API_KEY="your_key_here"
export OPENAI_API_KEY="your_key_here"

# Process a YouTube video
python youtube_transcript_summarizer.py \
  "https://www.youtube.com/watch?v=dQw4w9WgXcQ" \
  --save-transcript "transcript.txt" \
  --save-summary "summary.txt"
```

Output:
```
Downloading audio from: https://www.youtube.com/watch?v=dQw4w9WgXcQ
Audio downloaded to: /tmp/dQw4w9WgXcQ.m4a
Transcribing audio file: /tmp/dQw4w9WgXcQ.m4a
Transcription completed successfully
Summarizing transcript using gpt-4o...
Summary generated successfully

================================================================================
TRANSCRIPT
================================================================================
[Full transcript text here...]

================================================================================
SUMMARY
================================================================================
[AI-generated summary here...]
================================================================================

Transcript saved to: transcript.txt
Summary saved to: summary.txt
```

## Available OpenAI Models

- `gpt-4o` (default) - Latest and most capable model
- `gpt-4o-mini` - Smaller, faster version of GPT-4o
- `gpt-4-turbo` - Previous flagship model
- `gpt-4` - Original GPT-4 model
- `gpt-3.5-turbo` - Faster and cheaper option

Note: GPT-5 is not yet available. The script defaults to GPT-4o, which is the latest model as of now.

## Cost Considerations

- **AssemblyAI**: Offers free tier with limited minutes. Check [pricing](https://www.assemblyai.com/pricing) for details.
- **OpenAI**: Charges per token. GPT-4o is more expensive than GPT-3.5-turbo but provides better summaries. Check [pricing](https://openai.com/pricing) for current rates.

## Troubleshooting

**Error: FFmpeg not found**
- Make sure FFmpeg is installed and available in your system PATH

**Error: API key is required**
- Set your API keys as environment variables or pass them via command-line arguments

**Transcription failed**
- Check your AssemblyAI API key and quota
- Ensure the video URL is valid and accessible

**Summary generation failed**
- Check your OpenAI API key and account credits
- Try using a different model (e.g., gpt-3.5-turbo)

## License

MIT License

## Acknowledgments

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) for YouTube video downloading
- [AssemblyAI](https://www.assemblyai.com/) for speech recognition
- [OpenAI](https://openai.com/) for GPT models
