import os
import logging
from logging.handlers import RotatingFileHandler
from typing import List

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI
import uvicorn

from graph import news_graph, deep_dive as graph_deep_dive

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
os.makedirs(log_dir, exist_ok=True)

file_handler = RotatingFileHandler(
    os.path.join(log_dir, "agent-service.log"),
    maxBytes=10485760,
    backupCount=5,
)
file_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
logging.basicConfig(level=logging.INFO, handlers=[file_handler, logging.StreamHandler()])
logger = logging.getLogger("agent-service")

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Azure OpenAI client (existing chat endpoint)
# ---------------------------------------------------------------------------

azure_openai_endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
if not azure_openai_endpoint:
    raise RuntimeError("AZURE_OPENAI_ENDPOINT environment variable is not set.")

api_key = os.getenv("AZURE_OPENAI_API_KEY")
if api_key:
    client = AzureOpenAI(
        api_version="2024-12-01-preview",
        azure_endpoint=azure_openai_endpoint,
        api_key=api_key,
    )
else:
    token_provider = get_bearer_token_provider(
        DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default"
    )
    client = AzureOpenAI(
        api_version="2024-12-01-preview",
        azure_endpoint=azure_openai_endpoint,
        azure_ad_token_provider=token_provider,
    )

# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------

class ChatRequest(BaseModel):
    message: str

class ChatResponse(BaseModel):
    response: str
    status: str

class HealthResponse(BaseModel):
    status: str

class NewsSearchRequest(BaseModel):
    topic: str
    categories: List[str] = []

class ArticleResponse(BaseModel):
    title: str
    url: str
    source: str
    published_at: str
    description: str
    summary: str | None = None
    relevance_score: int | None = None

class DeepDiveRequest(BaseModel):
    url: str
    title: str
    description: str
    question: str

class DeepDiveResponse(BaseModel):
    answer: str

# ---------------------------------------------------------------------------
# Middleware
# ---------------------------------------------------------------------------

@app.middleware("http")
async def log_requests(request: Request, call_next):
    logger.info(f"Request: {request.method} {request.url}")
    response = await call_next(request)
    logger.info(f"Response status: {response.status_code}")
    return response

# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/health", response_model=HealthResponse)
async def health():
    return HealthResponse(status="healthy")


@app.post("/api/process-text", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """Original general-purpose chat endpoint."""
    logger.info(f"Received chat request: {request.message!r}")
    try:
        completion = client.chat.completions.create(
            model="model-router",
            messages=[{"role": "user", "content": request.message}],
        )
        ai_message = completion.choices[0].message.content or ""
        return ChatResponse(response=ai_message, status="success")
    except Exception as e:
        logger.exception("Error processing chat request")
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.post("/api/news/search", response_model=List[ArticleResponse])
async def search_news(request: NewsSearchRequest):
    """Fetch, filter, and summarise technical news using the LangGraph pipeline."""
    logger.info(f"News search: topic={request.topic!r}, categories={request.categories}")
    try:
        result = await news_graph.ainvoke({
            "topic": request.topic,
            "categories": request.categories,
            "raw_articles": [],
            "filtered_articles": [],
            "summarised_articles": [],
            "error": None,
        })

        if result.get("error") and not result.get("summarised_articles"):
            raise HTTPException(status_code=502, detail=result["error"])

        return result.get("summarised_articles", [])

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Error in news search")
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.post("/api/news/deep-dive", response_model=DeepDiveResponse)
async def deep_dive_endpoint(request: DeepDiveRequest):
    """Answer a follow-up question about a specific article."""
    logger.info(f"Deep dive: {request.title!r} — {request.question!r}")
    try:
        answer = await graph_deep_dive(
            url=request.url,
            title=request.title,
            description=request.description,
            question=request.question,
        )
        return DeepDiveResponse(answer=answer)
    except Exception as e:
        logger.exception("Error in deep dive")
        raise HTTPException(status_code=500, detail=str(e)) from e


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5001)
