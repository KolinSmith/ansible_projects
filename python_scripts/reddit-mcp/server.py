#!/usr/bin/env python3
"""
Reddit MCP server using application-only OAuth.

Works with Reddit "installed app" type registrations — no client secret required.
Provides read-only access to public subreddits.
"""

import os
import praw
from fastmcp import FastMCP

CLIENT_ID = os.environ.get("REDDIT_CLIENT_ID", "")
USER_AGENT = os.environ.get(
    "REDDIT_USER_AGENT",
    "linux:claude-reddit-mcp:1.0 (by /u/Nilok337)"
)

mcp = FastMCP("reddit")


def _reddit():
    if not CLIENT_ID:
        raise ValueError("REDDIT_CLIENT_ID environment variable not set")
    return praw.Reddit(
        client_id=CLIENT_ID,
        client_secret="",  # empty string required for installed app OAuth flow
        user_agent=USER_AGENT,
    )


@mcp.tool()
def get_subreddit_posts(subreddit: str, sort: str = "new", limit: int = 25) -> str:
    """
    Fetch posts from a subreddit.

    Args:
        subreddit: Subreddit name without r/ prefix (e.g. 'GrowthStockInvesting')
        sort: Feed sort order — new, hot, top, rising (default: new)
        limit: Number of posts to return (default: 25, max: 100)
    """
    reddit = _reddit()
    sub = reddit.subreddit(subreddit)
    feed = getattr(sub, sort)(limit=min(limit, 100))
    posts = []
    for post in feed:
        posts.append(
            f"[Score: {post.score}] {post.title}\n"
            f"  Author: u/{post.author}  |  Comments: {post.num_comments}  |  ID: {post.id}\n"
            f"  URL: {post.url}"
        )
    return "\n\n".join(posts) if posts else "No posts found."


@mcp.tool()
def get_post(post_id: str, comment_limit: int = 20) -> str:
    """
    Fetch a Reddit post and its top comments by post ID.

    Args:
        post_id: Reddit post ID (e.g. '1abc123' — the part after /comments/)
        comment_limit: Max top-level comments to return (default: 20)
    """
    reddit = _reddit()
    submission = reddit.submission(id=post_id)
    submission.comments.replace_more(limit=0)

    body = submission.selftext.strip() if submission.selftext else "[link post]"
    result = (
        f"Title: {submission.title}\n"
        f"Author: u/{submission.author}  |  Score: {submission.score}  |  "
        f"Comments: {submission.num_comments}\n\n"
        f"{body}\n\n"
        f"--- Top Comments ---"
    )
    for comment in list(submission.comments)[:comment_limit]:
        if not hasattr(comment, "body"):
            continue
        result += (
            f"\n\n[{comment.score}] u/{comment.author}:\n"
            f"{comment.body[:800]}"
        )
    return result


@mcp.tool()
def search_subreddit(subreddit: str, query: str, limit: int = 15) -> str:
    """
    Search for posts within a subreddit.

    Args:
        subreddit: Subreddit name without r/ prefix
        query: Search query string
        limit: Max results to return (default: 15)
    """
    reddit = _reddit()
    sub = reddit.subreddit(subreddit)
    results = []
    for post in sub.search(query, limit=limit, sort="relevance"):
        results.append(
            f"[Score: {post.score}] {post.title}\n"
            f"  Author: u/{post.author}  |  ID: {post.id}"
        )
    return "\n\n".join(results) if results else "No results found."


if __name__ == "__main__":
    mcp.run()
