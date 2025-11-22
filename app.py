#!/usr/bin/env python3
"""
Knowledge Tool Web App

A web application for processing YouTube videos and news articles.
Downloads, transcribes, and summarizes content using AI.
"""

import os
import tempfile
from pathlib import Path
from flask import Flask, render_template, request, jsonify, send_file
from werkzeug.utils import secure_filename
import logging

# Import from existing script
from youtube_transcript_summarizer import (
    process_youtube_video,
    sanitize_filename
)

# Import for news article processing
import requests
from bs4 import BeautifulSoup
from openai import OpenAI

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 500 * 1024 * 1024  # 500MB max file size
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-production')

# API Keys from environment variables
ASSEMBLYAI_API_KEY = os.environ.get('ASSEMBLYAI_API_KEY')
OPENAI_API_KEY = os.environ.get('OPENAI_API_KEY')


def extract_article_text(url: str) -> dict:
    """
    Extract article text from a news URL.

    Args:
        url: URL of the news article

    Returns:
        Dictionary with article title and text
    """
    logger.info(f"Extracting article from: {url}")

    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    }

    response = requests.get(url, headers=headers, timeout=30)
    response.raise_for_status()

    soup = BeautifulSoup(response.content, 'html.parser')

    # Try to extract title
    title = None
    if soup.find('h1'):
        title = soup.find('h1').get_text().strip()
    elif soup.find('title'):
        title = soup.find('title').get_text().strip()
    else:
        title = "Unknown Title"

    # Remove script and style elements
    for script in soup(["script", "style", "nav", "footer", "header"]):
        script.decompose()

    # Try common article content selectors
    article_selectors = [
        'article',
        '[role="article"]',
        '.article-content',
        '.post-content',
        '.entry-content',
        '.content',
        'main'
    ]

    article_text = ""
    for selector in article_selectors:
        article = soup.select_one(selector)
        if article:
            # Get all paragraph text
            paragraphs = article.find_all('p')
            article_text = '\n\n'.join(p.get_text().strip() for p in paragraphs if p.get_text().strip())
            if len(article_text) > 200:  # If we got substantial content, use it
                break

    # Fallback: get all paragraphs from body
    if not article_text or len(article_text) < 200:
        paragraphs = soup.find_all('p')
        article_text = '\n\n'.join(p.get_text().strip() for p in paragraphs if p.get_text().strip())

    if not article_text:
        raise Exception("Could not extract article content from URL")

    logger.info(f"Extracted article: {len(article_text)} characters")

    return {
        "title": title,
        "text": article_text,
        "url": url
    }


def summarize_article(article_text: str, openai_api_key: str, model: str = "gpt-4o-mini") -> str:
    """
    Summarize article text using OpenAI's GPT models.

    Args:
        article_text: The article text to summarize
        openai_api_key: OpenAI API key
        model: OpenAI model to use

    Returns:
        Summary text
    """
    logger.info(f"Summarizing article using {model}...")

    client = OpenAI(api_key=openai_api_key)

    response = client.chat.completions.create(
        model=model,
        messages=[
            {
                "role": "system",
                "content": "You are a helpful assistant that creates informative summaries of news articles. Try not to leave too much information out and capture as much vivid detail and useful information as possible. The more unique detail, the better as this detail will be surfaced later on."
            },
            {
                "role": "user",
                "content": f"Please provide a comprehensive summary of the following article formatted in a way that's optimized for Retrieval-Augmented Generation (RAG) systems to retain context and information:\n\n{article_text}"
            }
        ],
    )

    summary = response.choices[0].message.content
    logger.info("Summary generated successfully")
    return summary


def process_news_article(url: str, openai_api_key: str, model: str = "gpt-4o-mini") -> dict:
    """
    Process a news article: extract and summarize.

    Args:
        url: News article URL
        openai_api_key: OpenAI API key
        model: OpenAI model to use for summarization

    Returns:
        Dictionary with article text and summary
    """
    # Extract article
    article_data = extract_article_text(url)

    # Summarize
    summary = summarize_article(article_data["text"], openai_api_key, model)

    return {
        "article_url": url,
        "article_title": article_data["title"],
        "article_text": article_data["text"],
        "summary": summary
    }


@app.route('/')
def index():
    """Render the main page."""
    return render_template('index.html')


@app.route('/process', methods=['POST'])
def process():
    """Process a YouTube URL or news article URL."""
    try:
        data = request.json
        url = data.get('url', '').strip()
        content_type = data.get('type', 'auto')  # 'youtube', 'article', or 'auto'
        model = data.get('model', 'gpt-4o-mini')

        if not url:
            return jsonify({'error': 'URL is required'}), 400

        # Validate API keys
        if not ASSEMBLYAI_API_KEY:
            return jsonify({'error': 'AssemblyAI API key not configured'}), 500

        if not OPENAI_API_KEY:
            return jsonify({'error': 'OpenAI API key not configured'}), 500

        # Auto-detect content type if not specified
        if content_type == 'auto':
            if 'youtube.com' in url or 'youtu.be' in url:
                content_type = 'youtube'
            else:
                content_type = 'article'

        # Process based on content type
        if content_type == 'youtube':
            logger.info(f"Processing YouTube video: {url}")
            result = process_youtube_video(
                video_url=url,
                assemblyai_api_key=ASSEMBLYAI_API_KEY,
                openai_api_key=OPENAI_API_KEY,
                model=model,
                keep_audio=False,
                output_dir=None,
                remote_components="ejs:github"
            )

            return jsonify({
                'success': True,
                'type': 'youtube',
                'title': result['video_title'],
                'url': result['video_url'],
                'transcript': result['transcript'],
                'summary': result['summary']
            })

        elif content_type == 'article':
            logger.info(f"Processing news article: {url}")
            result = process_news_article(
                url=url,
                openai_api_key=OPENAI_API_KEY,
                model=model
            )

            return jsonify({
                'success': True,
                'type': 'article',
                'title': result['article_title'],
                'url': result['article_url'],
                'text': result['article_text'],
                'summary': result['summary']
            })

        else:
            return jsonify({'error': 'Invalid content type'}), 400

    except Exception as e:
        logger.error(f"Error processing request: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500


@app.route('/health')
def health():
    """Health check endpoint for Railway."""
    return jsonify({'status': 'healthy'}), 200


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
