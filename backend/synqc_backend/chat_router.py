"""
OpenAI chat integration for SynQc backend.
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import os

from openai import OpenAI

router = APIRouter()

class ChatRequest(BaseModel):
    message: str

class ChatResponse(BaseModel):
    reply: str

@router.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    """
    Send a message to OpenAI and get a response.
    Requires OPENAI_API_KEY to be set in the environment.
    """
    # Key must be in the backend environment, not the browser.
    if not os.getenv("OPENAI_API_KEY"):
        raise HTTPException(
            status_code=500, 
            detail="OPENAI_API_KEY is not set on the server"
        )

    # OpenAI client reads OPENAI_API_KEY from environment automatically
    client = OpenAI()

    # Get model from environment or use default
    model = os.getenv("OPENAI_MODEL", "gpt-4o")

    try:
        # Correct API call for chat completions
        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "user", "content": req.message}
            ]
        )

        # Extract the assistant's reply
        reply = response.choices[0].message.content

        return {"reply": reply}

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"OpenAI API error: {str(e)}"
        )
