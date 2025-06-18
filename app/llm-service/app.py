import os
import logging
from logging.handlers import RotatingFileHandler
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI
import uvicorn

# Configure logging
log_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
log_file = os.path.join(log_dir, "llm-service.log")

# Ensure log directory exists
os.makedirs(log_dir, exist_ok=True)

# Create a rotating file handler
file_handler = RotatingFileHandler(
    log_file,
    maxBytes=10485760,  # 10MB
    backupCount=5
)

# Configure logging format
formatter = logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s")
file_handler.setFormatter(formatter)

# Configure root logger
logging.basicConfig(
    level=logging.INFO,
    handlers=[
        file_handler,
        logging.StreamHandler()  # Keep console output as well
    ]
)
logger = logging.getLogger("llm-service")

app = FastAPI()

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request/Response models
class ChatRequest(BaseModel):
    message: str

class ChatResponse(BaseModel):
    response: str
    status: str

class HealthResponse(BaseModel):
    status: str

# Initialize the Azure OpenAI client with Microsoft Entra authentication
azure_openai_endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
if not azure_openai_endpoint:
    logger.error("AZURE_OPENAI_ENDPOINT environment variable is not set.")
    raise RuntimeError("AZURE_OPENAI_ENDPOINT environment variable is not set.")

token_provider = get_bearer_token_provider(
    DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default"
)
client = AzureOpenAI(
    api_version="2024-12-01-preview",
    azure_endpoint=azure_openai_endpoint,
    azure_ad_token_provider=token_provider,
)

@app.middleware("http")
async def log_requests(request: Request, call_next):
    logger.info(f"Request: {request.method} {request.url}")
    response = await call_next(request)
    logger.info(f"Response status: {response.status_code}")
    return response

@app.post('/api/process-text', response_model=ChatResponse)
async def chat(request: ChatRequest):
    """Handle chat completion requests to Azure OpenAI."""
    logger.info(f"Received chat request: {request.message!r}")
    try:
        completion = client.chat.completions.create(
            model="model-router",
            messages=[{"role": "user", "content": request.message}]
        )
        ai_message = completion.choices[0].message.content or ""
        logger.info("AI response generated successfully.")
        return ChatResponse(
            response=ai_message,
            status='success'
        )
    except Exception as e:
        logger.exception("Error processing chat request")
        raise HTTPException(status_code=500, detail=str(e)) from e

@app.get('/health', response_model=HealthResponse)
async def health():
    """Health check endpoint."""
    logger.info("Health check requested.")
    return HealthResponse(status='healthy')

if __name__ == '__main__':
    logger.info("Starting server on 0.0.0.0:5001")
    uvicorn.run(app, host="0.0.0.0", port=5001)