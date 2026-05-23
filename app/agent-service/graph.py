import os
import json
import asyncio
import logging
from typing import List

import httpx
from bs4 import BeautifulSoup
from newsapi import NewsApiClient
from langchain_openai import AzureChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage
from langgraph.graph import StateGraph, END
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

from state import NewsState, Article

logger = logging.getLogger("agent-service")

CATEGORY_KEYWORDS = {
    "Cloud & Infrastructure": "cloud Azure AWS GCP infrastructure Terraform",
    "Kubernetes & Containers": "Kubernetes Docker containers AKS EKS pods",
    "AI & LLMs": "AI LLM machine learning OpenAI artificial intelligence",
    "Cybersecurity": "security vulnerability CVE breach cybersecurity",
    "Programming Languages": "Python JavaScript TypeScript Rust Go programming",
}

# ---------------------------------------------------------------------------
# Client initialisation (lazy, module-level singletons)
# ---------------------------------------------------------------------------

_llm: AzureChatOpenAI | None = None
_news_client: NewsApiClient | None = None


def get_llm() -> AzureChatOpenAI:
    global _llm
    if _llm is None:
        endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
        if not endpoint:
            raise RuntimeError("AZURE_OPENAI_ENDPOINT is not set")

        api_key = os.getenv("AZURE_OPENAI_API_KEY")
        if api_key:
            # Local development — use API key
            _llm = AzureChatOpenAI(
                azure_deployment="model-router",
                azure_endpoint=endpoint,
                api_version="2024-12-01-preview",
                api_key=api_key,
                temperature=0,
            )
        else:
            # AKS — use managed identity
            token_provider = get_bearer_token_provider(
                DefaultAzureCredential(),
                "https://cognitiveservices.azure.com/.default",
            )
            _llm = AzureChatOpenAI(
                azure_deployment="model-router",
                azure_endpoint=endpoint,
                api_version="2024-12-01-preview",
                azure_ad_token_provider=token_provider,
                temperature=0,
            )
    return _llm


def get_news_client() -> NewsApiClient:
    global _news_client
    if _news_client is None:
        api_key = os.getenv("NEWS_API_KEY")
        if not api_key:
            raise RuntimeError("NEWS_API_KEY is not set")
        _news_client = NewsApiClient(api_key=api_key)
    return _news_client


# ---------------------------------------------------------------------------
# Graph nodes
# ---------------------------------------------------------------------------

async def fetch_news_node(state: NewsState) -> dict:
    """Fetch articles from NewsAPI using topic + category keywords."""
    try:
        client = get_news_client()

        keywords = [state["topic"]]
        for cat in state.get("categories", []):
            if cat in CATEGORY_KEYWORDS:
                keywords.append(f"({CATEGORY_KEYWORDS[cat]})")

        query = " OR ".join(keywords[:3])  # NewsAPI limits query length

        response = client.get_everything(
            q=query,
            language="en",
            sort_by="publishedAt",
            page_size=20,
        )

        articles: List[Article] = [
            Article(
                title=a.get("title", ""),
                url=a.get("url", ""),
                source=a.get("source", {}).get("name", ""),
                published_at=a.get("publishedAt", ""),
                description=a.get("description") or "",
                content=a.get("content") or "",
                summary=None,
                relevance_score=None,
            )
            for a in response.get("articles", [])
            if a.get("title") and a.get("url") and "[Removed]" not in (a.get("title") or "")
        ]

        logger.info(f"Fetched {len(articles)} articles for topic: {state['topic']}")
        return {"raw_articles": articles}

    except Exception as e:
        logger.error(f"Error fetching news: {e}")
        return {"raw_articles": [], "error": str(e)}


async def filter_articles_node(state: NewsState) -> dict:
    """Score articles for technical relevance using the LLM."""
    articles = state.get("raw_articles", [])
    if not articles:
        return {"filtered_articles": []}

    llm = get_llm()
    categories = ", ".join(state.get("categories", [])) or "general technical topics"

    articles_text = "\n".join(
        f"{i + 1}. {a['title']} — {a['description'][:120]}"
        for i, a in enumerate(articles)
    )

    try:
        response = await llm.ainvoke([
            SystemMessage(content=f"""You are a technical news filter.
Score each article 1-10 for relevance to: {categories}
Topic: {state['topic']}

- 8-10: Directly technical, highly relevant
- 5-7: Somewhat technical or tangential
- 1-4: Not technical or irrelevant

Return ONLY a JSON array: [{{"index": 1, "score": 8}}, ...]"""),
            HumanMessage(content=articles_text),
        ])

        scores = json.loads(response.content)
        score_map = {s["index"]: s["score"] for s in scores}

        filtered = [
            {**article, "relevance_score": score_map.get(i + 1, 0)}
            for i, article in enumerate(articles)
            if score_map.get(i + 1, 0) >= 7
        ]
        filtered.sort(key=lambda x: x["relevance_score"], reverse=True)

        logger.info(f"Filtered to {len(filtered[:10])} relevant articles")
        return {"filtered_articles": filtered[:10]}

    except Exception as e:
        logger.error(f"Error filtering articles: {e}")
        return {"filtered_articles": articles[:10]}


async def summarise_articles_node(state: NewsState) -> dict:
    """Summarise each article in parallel."""
    articles = state.get("filtered_articles", [])
    if not articles:
        return {"summarised_articles": []}

    llm = get_llm()

    async def summarise_one(article: Article) -> Article:
        try:
            response = await llm.ainvoke([
                SystemMessage(content=(
                    "Summarise this article in 2-3 concise sentences for a technical audience. "
                    "Focus on what is new, why it matters, and any practical implications."
                )),
                HumanMessage(content=(
                    f"Title: {article['title']}\n\n"
                    f"Description: {article['description']}\n\n"
                    f"Content: {article['content'][:500]}"
                )),
            ])
            return {**article, "summary": response.content}
        except Exception as e:
            logger.error(f"Error summarising '{article['title']}': {e}")
            return {**article, "summary": article["description"]}

    summarised = await asyncio.gather(*[summarise_one(a) for a in articles])
    logger.info(f"Summarised {len(summarised)} articles")
    return {"summarised_articles": list(summarised)}


# ---------------------------------------------------------------------------
# Deep dive (called directly from app.py, not part of the graph)
# ---------------------------------------------------------------------------

async def fetch_article_content(url: str) -> str:
    """Fetch and extract readable text from an article URL."""
    try:
        async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
            response = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
            response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")
        for tag in soup(["nav", "footer", "aside", "script", "style", "header"]):
            tag.decompose()

        main = soup.find("main") or soup.find("article") or soup.find("body")
        text = main.get_text(separator="\n", strip=True) if main else soup.get_text()
        return text[:4000]

    except Exception as e:
        logger.warning(f"Could not fetch article content from {url}: {e}")
        return ""


async def deep_dive(url: str, title: str, description: str, question: str) -> str:
    """Answer a follow-up question about a specific article."""
    llm = get_llm()
    content = await fetch_article_content(url)
    context = content or description

    response = await llm.ainvoke([
        SystemMessage(content=(
            "You are a technical analyst. Answer the user's question based on the article provided. "
            "Be specific and concise. If the article does not contain enough information, say so."
        )),
        HumanMessage(content=(
            f"Article title: {title}\n\n"
            f"Article content:\n{context}\n\n"
            f"Question: {question}"
        )),
    ])
    return response.content


# ---------------------------------------------------------------------------
# Graph definition
# ---------------------------------------------------------------------------

def build_news_graph():
    workflow = StateGraph(NewsState)

    workflow.add_node("fetch_news", fetch_news_node)
    workflow.add_node("filter_articles", filter_articles_node)
    workflow.add_node("summarise_articles", summarise_articles_node)

    workflow.set_entry_point("fetch_news")
    workflow.add_edge("fetch_news", "filter_articles")
    workflow.add_edge("filter_articles", "summarise_articles")
    workflow.add_edge("summarise_articles", END)

    return workflow.compile()


news_graph = build_news_graph()
