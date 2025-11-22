# Knowledge Tool Web App

A web application for transcribing YouTube videos and summarizing news articles using AI.

## Features

- **YouTube Video Processing**: Download audio, transcribe using AssemblyAI, and summarize with OpenAI
- **News Article Summarization**: Extract and summarize articles from any news website
- **Auto-detection**: Automatically detects whether input is a YouTube URL or article
- **Multiple AI Models**: Choose from GPT-4o, GPT-4o Mini, or GPT-4 for summarization
- **Beautiful UI**: Modern, responsive web interface
- **Railway Ready**: Configured for one-click deployment on Railway

## Quick Start (Local Development)

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Set Up Environment Variables

Create a `.env` file:

```bash
cp .env.example .env
```

Edit `.env` and add your API keys:
- **AssemblyAI API Key**: Get from [assemblyai.com](https://www.assemblyai.com/)
- **OpenAI API Key**: Get from [platform.openai.com](https://platform.openai.com/api-keys)

### 3. Install FFmpeg

FFmpeg is required for audio extraction from YouTube videos.

**macOS:**
```bash
brew install ffmpeg
```

**Ubuntu/Debian:**
```bash
sudo apt update && sudo apt install ffmpeg
```

**Windows:**
Download from [ffmpeg.org](https://ffmpeg.org/download.html) or use chocolatey:
```bash
choco install ffmpeg
```

### 4. Run the Application

```bash
python app.py
```

Visit `http://localhost:5000` in your browser.

## Deploying to Railway

Railway makes deployment incredibly simple.

### Method 1: Deploy from GitHub (Recommended)

1. **Push your code to GitHub**
   ```bash
   git add .
   git commit -m "Add web app"
   git push
   ```

2. **Create a new project on Railway**
   - Go to [railway.app](https://railway.app)
   - Click "New Project"
   - Select "Deploy from GitHub repo"
   - Choose your repository

3. **Add Environment Variables**
   In the Railway dashboard, add these variables:
   - `ASSEMBLYAI_API_KEY` - Your AssemblyAI API key
   - `OPENAI_API_KEY` - Your OpenAI API key
   - `SECRET_KEY` - A random string for Flask sessions

4. **Deploy**
   Railway will automatically detect the configuration and deploy your app!

### Method 2: Railway CLI

1. **Install Railway CLI**
   ```bash
   npm install -g @railway/cli
   ```

2. **Login to Railway**
   ```bash
   railway login
   ```

3. **Initialize Project**
   ```bash
   railway init
   ```

4. **Add Environment Variables**
   ```bash
   railway variables set ASSEMBLYAI_API_KEY=your_key_here
   railway variables set OPENAI_API_KEY=your_key_here
   railway variables set SECRET_KEY=your_secret_key_here
   ```

5. **Deploy**
   ```bash
   railway up
   ```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `ASSEMBLYAI_API_KEY` | AssemblyAI API key for transcription | Yes |
| `OPENAI_API_KEY` | OpenAI API key for summarization | Yes |
| `SECRET_KEY` | Flask secret key for sessions | No (auto-generated in dev) |
| `PORT` | Port to run the server on | No (Railway sets this automatically) |

### Supported AI Models

- **gpt-4o-mini** (Default): Fast and affordable, great for most use cases
- **gpt-4o**: Best quality, more expensive
- **gpt-4**: Previous generation flagship model

## API Endpoints

### `POST /process`

Process a YouTube video or news article.

**Request Body:**
```json
{
  "url": "https://www.youtube.com/watch?v=...",
  "type": "auto",  // "auto", "youtube", or "article"
  "model": "gpt-4o-mini"
}
```

**Response:**
```json
{
  "success": true,
  "type": "youtube",
  "title": "Video Title",
  "url": "https://...",
  "transcript": "Full transcript...",
  "summary": "AI-generated summary..."
}
```

### `GET /health`

Health check endpoint for Railway.

**Response:**
```json
{
  "status": "healthy"
}
```

## Architecture

```
┌─────────────────┐
│   Web Browser   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Flask Web App  │
│   (app.py)      │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌─────────┐ ┌──────────────┐
│YouTube  │ │News Article  │
│Processor│ │Extractor     │
└────┬────┘ └──────┬───────┘
     │             │
     ▼             ▼
┌─────────────────────────┐
│  AI Services            │
│  - AssemblyAI (Audio)   │
│  - OpenAI (Summary)     │
└─────────────────────────┘
```

## Cost Considerations

- **AssemblyAI**: ~$0.00025/second of audio (free tier available)
- **OpenAI**:
  - GPT-4o Mini: ~$0.15/$0.60 per 1M tokens (input/output)
  - GPT-4o: ~$2.50/$10.00 per 1M tokens
  - GPT-4: ~$30/$60 per 1M tokens

Typical costs:
- 10-minute YouTube video: ~$0.15 (AssemblyAI) + ~$0.02 (GPT-4o Mini) = ~$0.17
- News article: ~$0.01 (GPT-4o Mini)

## Troubleshooting

### "AssemblyAI API key not configured"
Make sure you've set the `ASSEMBLYAI_API_KEY` environment variable in Railway or your `.env` file.

### "OpenAI API key not configured"
Make sure you've set the `OPENAI_API_KEY` environment variable in Railway or your `.env` file.

### "FFmpeg not found" (Local development)
Install FFmpeg using the instructions in the Quick Start section.

### Railway deployment fails
- Check that all environment variables are set correctly
- Make sure your `requirements.txt` is up to date
- Check Railway logs for specific error messages

## Support

For issues and questions:
- Check the main [README.md](./README.md) for the Python CLI tool
- Review Railway's [deployment documentation](https://docs.railway.app/)
- Check [AssemblyAI docs](https://www.assemblyai.com/docs)
- Review [OpenAI docs](https://platform.openai.com/docs)

## License

MIT License
