# Knowledge Tool

A powerful macOS application for transcribing videos, summarizing articles, and analyzing text snippets using AI.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-green.svg)

## Features

### 🎥 Video Transcription
- **URL Support**: Download and transcribe videos from YouTube, Vimeo, and other platforms
- **File Upload**: Drag & drop or browse for local video files
- **Speaker Diarization**: Automatically identify and label different speakers
- **Timestamps**: Get precise timestamps for each utterance
- **AI Summarization**: Generate comprehensive summaries of video content

### 📰 Article Summarization
- **Web Scraping**: Extract content from any article or blog post
- **Smart Parsing**: Automatically identifies main content and filters out navigation/ads
- **Metadata Extraction**: Captures title, publish date, and word count
- **AI Summarization**: Creates detailed summaries optimized for knowledge retention

### 📝 Text Snippet Analysis
- **Paste Anywhere**: Quick paste from clipboard
- **Statistics**: Detailed text statistics (characters, words, sentences, paragraphs)
- **AI Analysis**: Extract key insights and main ideas
- **Export Options**: Save analysis results for future reference

## Requirements

### System Requirements
- macOS 14.0 (Sonoma) or later
- Xcode 16.0 or later (for building)
- Active internet connection for API calls

### Dependencies
Install the following via [Homebrew](https://brew.sh):

```bash
# For video URL download
brew install yt-dlp

# For audio extraction from video files
brew install ffmpeg
```

### API Keys
You'll need API keys from:

- **AssemblyAI**: For audio transcription with speaker diarization
  - Sign up at: https://www.assemblyai.com/
  - Free tier includes 5 hours of transcription per month

- **OpenAI**: For AI-powered summarization and analysis
  - Get your API key at: https://platform.openai.com/api-keys
  - Uses GPT-4o model by default

## Installation

### Option 1: Build from Source

1. **Clone the repository**
   ```bash
   cd knowledge-tool/KnowledgeTool
   ```

2. **Open in Xcode**
   ```bash
   open Package.swift
   ```

   Or double-click `Package.swift` in Finder

3. **Configure signing**
   - Select the project in Xcode
   - Go to "Signing & Capabilities"
   - Select your development team

4. **Build and run**
   - Press `Cmd + R` or click the Run button
   - The app will build and launch

### Option 2: Build via Command Line

```bash
cd knowledge-tool/KnowledgeTool
swift build -c release
```

The compiled app will be in `.build/release/KnowledgeTool`

## Configuration

### Setting Up API Keys

1. Launch Knowledge Tool
2. Press `Cmd + ,` or go to **Settings** from the menu
3. Enter your API keys:
   - **AssemblyAI API Key**: Required for video transcription
   - **OpenAI API Key**: Required for summarization and text analysis
4. Click **Save**

API keys are securely stored in the macOS Keychain and never leave your device.

## Usage

### Video Transcription

1. Select **Video** from the sidebar
2. Choose your input method:
   - **URL**: Paste a YouTube, Vimeo, or other video URL
   - **File Upload**: Drag & drop or browse for a video file
3. Click **Process** and wait for:
   - Video download (if URL)
   - Audio extraction
   - Transcription with speaker labels
   - AI summarization
4. View results:
   - Video information
   - Full transcript with speaker labels and timestamps
   - Comprehensive summary
5. Export transcript or summary as text files

### Article Summarization

1. Select **Article** from the sidebar
2. Paste the URL of any article or blog post
3. Click **Process** and wait for:
   - Content extraction
   - AI summarization
4. View results:
   - Article metadata
   - Full extracted content
   - AI-generated summary
5. Export content or summary as text files

### Text Snippet Analysis

1. Select **Text Snippet** from the sidebar
2. Paste or type your text
   - Use **Paste from Clipboard** button for quick access
3. Click **Analyze** and wait for:
   - Text statistics calculation
   - AI analysis
4. View results:
   - Detailed statistics (characters, words, sentences, etc.)
   - AI-generated analysis and insights
5. Export analysis as a text file

## Architecture

### Technology Stack
- **Language**: Swift 6.0
- **UI Framework**: SwiftUI (100% native)
- **Concurrency**: Swift Concurrency (async/await, actors)
- **State Management**: @Observable macro
- **Storage**: Keychain for secure API key storage

### Project Structure
```
KnowledgeTool/
├── App/
│   └── KnowledgeToolApp.swift          # App entry point
├── Models/
│   └── Models.swift                     # Data models
├── Services/
│   ├── AssemblyAIService.swift         # Transcription service
│   ├── OpenAIService.swift             # Summarization service
│   ├── VideoService.swift              # Video download/processing
│   └── ArticleService.swift            # Web scraping service
├── ViewModels/
│   ├── VideoViewModel.swift            # Video feature logic
│   ├── ArticleViewModel.swift          # Article feature logic
│   └── TextSnippetViewModel.swift      # Text snippet logic
├── Views/
│   ├── ContentView.swift               # Main window
│   ├── Video/VideoView.swift           # Video UI
│   ├── Article/ArticleView.swift       # Article UI
│   ├── TextSnippet/TextSnippetView.swift # Text snippet UI
│   ├── Settings/SettingsView.swift     # Settings UI
│   └── Shared/SharedViews.swift        # Reusable components
├── Utilities/
│   └── APIKeyManager.swift             # Keychain management
└── Resources/
    ├── Info.plist                      # App metadata
    └── KnowledgeTool.entitlements      # App capabilities
```

### Design Principles
- **Modern Swift**: Uses Swift 6 features including strict concurrency
- **SwiftUI-First**: 100% SwiftUI, no AppKit (except where needed for platform features)
- **Actor Isolation**: Services use actors for thread-safe API calls
- **Async/Await**: All network operations use Swift concurrency
- **Observation**: Uses @Observable macro for state management
- **Human Interface Guidelines**: Follows Apple's HIG for macOS

## Keyboard Shortcuts

- `Cmd + ,` - Open Settings
- `Cmd + Return` - Process current input (video URL, article URL, or text)
- `Cmd + W` - Close window
- `Cmd + Q` - Quit application

## Troubleshooting

### "yt-dlp is not installed"
Install via Homebrew:
```bash
brew install yt-dlp
```

### "ffmpeg is not installed"
Install via Homebrew:
```bash
brew install ffmpeg
```

### "Missing API key for AssemblyAI/OpenAI"
1. Open Settings (`Cmd + ,`)
2. Enter your API keys
3. Click Save

### Video download fails
- Check your internet connection
- Verify the URL is accessible
- Some platforms may block downloads
- Update yt-dlp: `brew upgrade yt-dlp`

### Transcription is slow
- AssemblyAI processes audio in real-time
- Longer videos take more time
- Check the processing status indicator

### Article extraction returns empty content
- Some websites use dynamic loading (JavaScript)
- Try copying the article text and using Text Snippet instead
- Some sites may have anti-scraping protection

## Privacy & Security

- **API Keys**: Stored securely in macOS Keychain
- **No Data Collection**: No analytics or telemetry
- **Local Processing**: All processing happens on your device
- **API Calls**: Only sent to AssemblyAI and OpenAI
- **No Cloud Storage**: All data stays on your Mac

## Cost Considerations

### AssemblyAI
- Free tier: 5 hours/month
- Pay-as-you-go: $0.00025 per second (~$0.015/minute)
- See pricing: https://www.assemblyai.com/pricing

### OpenAI (GPT-4o)
- Input: $2.50 per 1M tokens
- Output: $10.00 per 1M tokens
- Average article summary: $0.01-0.05
- See pricing: https://openai.com/api/pricing

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is open source and available under the MIT License.

## Acknowledgments

- Built with Swift and SwiftUI
- Powered by AssemblyAI for transcription
- Powered by OpenAI for summarization
- Uses yt-dlp for video downloads
- Uses ffmpeg for audio processing

## Support

For issues, questions, or feature requests, please open an issue on GitHub.
