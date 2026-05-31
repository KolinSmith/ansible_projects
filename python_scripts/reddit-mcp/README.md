# Reddit MCP Server

Read-only Reddit MCP server for Claude Code using application-only OAuth. Works with Reddit "installed app" registrations — no client secret required.

## Setup

### 1. Install dependencies

```bash
pip3 install -r requirements.txt
```

### 2. Set environment variable

Add your Reddit app's client ID to Claude Code's global settings (`~/.claude/settings.json`):

```json
{
  "env": {
    "REDDIT_CLIENT_ID": "your_client_id_here"
  }
}
```

The client ID is the string shown under your app name at https://www.reddit.com/prefs/apps. For an "installed app" type, there is no client secret.

Optionally override the user agent:
```json
{
  "env": {
    "REDDIT_CLIENT_ID": "your_client_id_here",
    "REDDIT_USER_AGENT": "linux:claude-reddit-mcp:1.0 (by /u/YourUsername)"
  }
}
```

### 3. Register with Claude Code

```bash
claude mcp add --scope user reddit-read -- python3 /path/to/python_scripts/reddit-mcp/server.py
```

## Tools

| Tool | Description |
|---|---|
| `get_subreddit_posts` | Fetch posts from a subreddit (new/hot/top/rising) |
| `get_post` | Fetch a post and its top comments by ID |
| `search_subreddit` | Search posts within a subreddit |

## Primary use case

Monitoring `r/GrowthStockInvesting` for wpr101's latest portfolio commentary between monthly Motley Fool summaries.
