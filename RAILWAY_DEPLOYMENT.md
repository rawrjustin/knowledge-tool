# Railway Deployment Guide

This guide will help you deploy the Knowledge Tool web app to Railway in just a few minutes.

## Prerequisites

1. A Railway account (sign up at [railway.app](https://railway.app))
2. AssemblyAI API key (get from [assemblyai.com](https://www.assemblyai.com/))
3. OpenAI API key (get from [platform.openai.com](https://platform.openai.com/api-keys))
4. Your code pushed to GitHub

## Step-by-Step Deployment

### Step 1: Push Code to GitHub

```bash
git add .
git commit -m "Add Knowledge Tool web app"
git push origin main
```

### Step 2: Create New Railway Project

1. Go to [railway.app](https://railway.app) and log in
2. Click **"New Project"**
3. Select **"Deploy from GitHub repo"**
4. Choose your repository from the list
5. Railway will automatically detect the configuration

### Step 3: Configure Environment Variables

In the Railway dashboard:

1. Click on your deployed service
2. Go to the **"Variables"** tab
3. Add the following variables:

| Variable Name | Value | Where to Get It |
|--------------|-------|-----------------|
| `ASSEMBLYAI_API_KEY` | Your AssemblyAI key | [assemblyai.com](https://www.assemblyai.com/) |
| `OPENAI_API_KEY` | Your OpenAI key | [platform.openai.com](https://platform.openai.com/api-keys) |
| `SECRET_KEY` | Any random string | Generate with `python -c "import secrets; print(secrets.token_hex(32))"` |

### Step 4: Deploy

Railway will automatically:
- Install dependencies from `requirements.txt`
- Use the configuration from `railway.toml`
- Start your app with Gunicorn
- Assign a public URL

### Step 5: Verify Deployment

1. Click on **"Deployments"** in the Railway dashboard
2. Wait for the deployment to complete (usually 2-3 minutes)
3. Click on the **"View Logs"** button to see deployment progress
4. Once deployed, click on the generated URL to access your app

## What Railway Does Automatically

✅ Installs Python 3.11
✅ Installs FFmpeg (required for YouTube audio extraction)
✅ Installs all Python dependencies
✅ Starts the app with Gunicorn
✅ Provides HTTPS
✅ Auto-restarts on failures
✅ Health checks via `/health` endpoint

## Configuration Files

Railway uses these files for deployment:

- **`requirements.txt`**: Python dependencies
- **`runtime.txt`**: Python version
- **`Procfile`**: Process to run (backup for railway.toml)
- **`railway.toml`**: Railway-specific configuration

## Monitoring Your App

### View Logs

```bash
# Install Railway CLI
npm install -g @railway/cli

# Login
railway login

# Link to your project
railway link

# View logs
railway logs
```

### Health Check

Your app has a health check endpoint at `/health`. Railway monitors this automatically.

Test it manually:
```bash
curl https://your-app-url.railway.app/health
```

Expected response:
```json
{"status": "healthy"}
```

## Updating Your App

To deploy updates:

```bash
git add .
git commit -m "Your update message"
git push
```

Railway automatically detects the push and redeploys.

## Cost Estimates

Railway offers:
- **Hobby Plan**: $5/month for 512MB RAM, $5 usage credit
- **Pro Plan**: $20/month for more resources

Typical usage:
- Each video processing: ~2-3 minutes of compute time
- Memory: ~300-400MB per request
- Estimated: ~200-300 videos/month on hobby plan

**Note**: AI API costs (AssemblyAI + OpenAI) are separate and billed by those services.

## Troubleshooting

### Deployment Failed

Check the logs in Railway dashboard:
1. Click on your service
2. Go to "Deployments"
3. Click on the failed deployment
4. View logs for error messages

### App Not Starting

Common issues:
- **Missing environment variables**: Verify `ASSEMBLYAI_API_KEY` and `OPENAI_API_KEY` are set
- **Port binding**: Railway sets `PORT` automatically, don't hardcode it
- **FFmpeg missing**: Should be auto-installed by Nixpacks, check logs

### "API key not configured" Error

In Railway dashboard:
1. Go to "Variables" tab
2. Verify `ASSEMBLYAI_API_KEY` and `OPENAI_API_KEY` are set
3. Click "Redeploy" after adding variables

### Out of Memory

If you see memory errors:
1. Upgrade to a larger Railway plan
2. Reduce `--workers` in `Procfile` (default is 2)
3. Process shorter videos

### Timeout Errors

For long videos (>30 minutes):
1. Increase `--timeout` in `Procfile` (currently 300 seconds)
2. Or use the Python CLI for very long videos

## Alternative: Railway CLI Deployment

If you prefer the command line:

```bash
# Install CLI
npm install -g @railway/cli

# Login
railway login

# Initialize project
railway init

# Set environment variables
railway variables set ASSEMBLYAI_API_KEY=your_key
railway variables set OPENAI_API_KEY=your_key
railway variables set SECRET_KEY=your_secret

# Deploy
railway up

# Open in browser
railway open
```

## Custom Domain

To use your own domain:

1. In Railway dashboard, go to "Settings"
2. Click "Generate Domain" or "Add Custom Domain"
3. Follow Railway's instructions to configure DNS

## Support

- **Railway Docs**: [docs.railway.app](https://docs.railway.app/)
- **Railway Discord**: [discord.gg/railway](https://discord.gg/railway)
- **This Project**: See [WEB_APP_README.md](./WEB_APP_README.md)

## Next Steps

After deployment:
1. Test with a YouTube video
2. Test with a news article
3. Monitor your API usage (AssemblyAI + OpenAI dashboards)
4. Share your app URL with others!

---

**Need help?** Check the logs first, then refer to the troubleshooting section above.
