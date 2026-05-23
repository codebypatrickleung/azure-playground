from typing import TypedDict, List, Optional


class Article(TypedDict):
    title: str
    url: str
    source: str
    published_at: str
    description: str
    content: Optional[str]
    summary: Optional[str]
    relevance_score: Optional[int]


class NewsState(TypedDict):
    topic: str
    categories: List[str]
    raw_articles: List[Article]
    filtered_articles: List[Article]
    summarised_articles: List[Article]
    error: Optional[str]
