import json
import math
import os
import time
import logging
from dataclasses import dataclass
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

import boto3

# -----------------------------------------------------------------------------
# Configuration (parameterized via environment variables)
# -----------------------------------------------------------------------------

DOC_TABLE: str = os.environ.get("DOC_TABLE", "")
EMBEDDING_MODEL_ID: str = os.environ.get("EMBEDDING_MODEL_ID", "amazon.titan-embed-text-v2:0")
BEDROCK_MODEL_ID: str = os.environ.get(
    "BEDROCK_MODEL_ID",
    # Default to your existing inference profile ARN to avoid breaking behavior.
    "arn:aws:bedrock:us-east-1:588738567290:inference-profile/us.anthropic.claude-sonnet-4-20250514-v1:0",
)
BEDROCK_GUARDRAIL_ID: Optional[str] = os.environ.get("BEDROCK_GUARDRAIL_ID", "rqkveuut7fzm")
BEDROCK_GUARDRAIL_VERSION: str = os.environ.get("BEDROCK_GUARDRAIL_VERSION", "5")

# Retrieval tuning
TOP_K: int = int(os.environ.get("RETRIEVAL_TOP_K", "3"))
MIN_SIMILARITY: float = float(os.environ.get("MIN_SIMILARITY", "0.0"))  # e.g., 0.2 to filter weak matches

# CORS
CORS_ALLOW_ORIGIN: str = os.environ.get("CORS_ALLOW_ORIGIN", "*")

# -----------------------------------------------------------------------------
# AWS Clients
# -----------------------------------------------------------------------------

dynamodb = boto3.resource("dynamodb")
bedrock = boto3.client("bedrock-runtime")

table = dynamodb.Table(DOC_TABLE)

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

logger = logging.getLogger()
if not logger.handlers:
    logging.basicConfig(level=logging.INFO)
logger.setLevel(logging.INFO)

# -----------------------------------------------------------------------------
# Types & Data Models
# -----------------------------------------------------------------------------

@dataclass
class RetrievedChunk:
    text: str
    filename: str
    score: float


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

def decimal_to_float(obj: Any) -> Any:
    """Recursively convert Decimals to float for math ops."""
    if isinstance(obj, list):
        return [decimal_to_float(x) for x in obj]
    if isinstance(obj, dict):
        return {k: decimal_to_float(v) for k, v in obj.items()}
    if isinstance(obj, Decimal):
        return float(obj)
    return obj


def cosine_similarity(vec1: List[float], vec2: List[float]) -> float:
    """Compute cosine similarity; return 0.0 if a norm is zero or vectors are empty."""
    if not vec1 or not vec2:
        return 0.0
    dot = sum(a * b for a, b in zip(vec1, vec2))
    norm1 = math.sqrt(sum(a * a for a in vec1))
    norm2 = math.sqrt(sum(b * b for b in vec2))
    if norm1 == 0.0 or norm2 == 0.0:
        return 0.0
    return dot / (norm1 * norm2)


def scan_all_items(table_resource) -> List[Dict[str, Any]]:
    """Scan the whole table (demo-only!)."""
    items: List[Dict[str, Any]] = []
    scan_kwargs: Dict[str, Any] = {}
    while True:
        resp = table_resource.scan(**scan_kwargs)
        items.extend(resp.get("Items", []))
        lek = resp.get("LastEvaluatedKey")
        if not lek:
            break
        scan_kwargs["ExclusiveStartKey"] = lek
    return items


def embed_text(text: str) -> List[float]:
    """Call Bedrock embedding model and return the embedding vector."""
    logger.info("Calling embedding model: %s", EMBEDDING_MODEL_ID)
    resp = bedrock.invoke_model(
        modelId=EMBEDDING_MODEL_ID,
        contentType="application/json",
        body=json.dumps({"inputText": text}),
    )
    payload = json.loads(resp["body"].read())
    # Titan returns {"embedding": [...]}
    vec = payload.get("embedding") or payload.get("vector") or []
    return [float(x) for x in vec]


def build_llm_request(query: str, context_chunks: List[RetrievedChunk], use_guardrails: bool) -> Dict[str, Any]:
    """Construct the request payload for the Bedrock text model."""
    # Instruction ensures no answer without context.
    system_prompt = (
        "You are a helpful DevOps assistant.\n"
        "Use only the provided Context to answer the user's question.\n"
        "If no Context is provided (or it's empty), reply exactly:\n"
        "\"Sorry, I couldn't find any context matching your question.\"\n"
        "If the user's question involves dangerous instructions (such as actions that could cause catastrophic harm to systems), respond with:\n"
        "\"Sorry, the model cannot answer this question.\"\n"
        "Do not attempt to answer the question without context.\n"
        "Keep answers under 1200 characters. Use short, clear sentences."
    )

    guardrail_tag_suffix = "usr"  # must match tagSuffix if guardrails enabled
    open_tag = f"<amazon-bedrock-guardrails-guardContent_{guardrail_tag_suffix}>"
    close_tag = f"</amazon-bedrock-guardrails-guardContent_{guardrail_tag_suffix}>"

    # Join context
    context_text = "\n\n".join(ch.text for ch in context_chunks)

    if use_guardrails:
        user_text = (
            f"Context:\n{context_text}\n\n"
            f"Question:\n{open_tag}\n{query}\n{close_tag}"
        )
    else:
        user_text = f"Context:\n{context_text}\n\nQuestion:\n{query}"

    request_payload: Dict[str, Any] = {
        "anthropic_version": "bedrock-2023-05-31",
        "system": system_prompt,
        "max_tokens": 300,
        "messages": [
            {"role": "user", "content": [{"type": "text", "text": user_text}]}
        ],
    }

    if use_guardrails:
        request_payload["amazon-bedrock-guardrailConfig"] = {"tagSuffix": guardrail_tag_suffix}

    return request_payload


def build_response(status: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": CORS_ALLOW_ORIGIN,
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
        },
        "body": json.dumps(body),
    }


# -----------------------------------------------------------------------------
# Lambda handler
# -----------------------------------------------------------------------------

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    logger.info("=== EVENT RECEIVED ===")
    logger.info(json.dumps(event, indent=2))

    # Handle CORS preflight
    if event.get("httpMethod") == "OPTIONS":
        return build_response(204, {"ok": True})

    try:
        body_raw = event.get("body") or "{}"
        body = json.loads(body_raw)
    except Exception:
        return build_response(400, {"error": "Invalid JSON body"})

    query: Optional[str] = body.get("query")
    logger.info("Parsed query: %s", query)

    if not query:
        return build_response(400, {"error": "No query provided"})

    # 1) Embed the query
    start_embed = time.time()
    query_vec = embed_text(query)
    logger.info("Embedding duration: %.2fs", time.time() - start_embed)

    # 2) Retrieve + score chunks (demo: full table scan)
    start_scan = time.time()
    items = scan_all_items(table)
    logger.info("Scanned DynamoDB: %d items in %.2fs", len(items), time.time() - start_scan)

    scored: List[RetrievedChunk] = []
    for it in items:
        emb = it.get("embedding")
        txt = it.get("text", "")
        fname = it.get("filename", "")

        if not emb or not isinstance(emb, list) or not txt:
            continue

        chunk_vec = decimal_to_float(emb)
        score = cosine_similarity(query_vec, chunk_vec)  # type: ignore[arg-type]
        scored.append(RetrievedChunk(text=txt, filename=fname, score=score))

    # Sort by similarity and take top-k
    scored.sort(key=lambda c: c.score, reverse=True)
    top = [c for c in scored if c.score >= MIN_SIMILARITY][:TOP_K]

    logger.info("Top scores: %s", [(round(c.score, 3), c.filename) for c in top[:3]])

    # If no strong context, short-circuit with explicit message (saves LLM call)
    if not top:
        return build_response(
            200,
            {
                "answer": "Sorry, I couldn't find any context matching your question.",
                "context": [],
            },
        )

    # 3) Ask Bedrock LLM with context
    use_guardrails = bool(BEDROCK_GUARDRAIL_ID)
    request_payload = build_llm_request(query, top, use_guardrails)
    logger.info("Claude request payload: %s", json.dumps(request_payload, indent=2))

    invoke_kwargs: Dict[str, Any] = {
        "modelId": BEDROCK_MODEL_ID,
        "contentType": "application/json",
        "accept": "application/json",
        "trace": "ENABLED",
        "body": json.dumps(request_payload).encode("utf-8"),
    }
    if use_guardrails:
        invoke_kwargs["guardrailIdentifier"] = BEDROCK_GUARDRAIL_ID
        invoke_kwargs["guardrailVersion"] = BEDROCK_GUARDRAIL_VERSION

    start_llm = time.time()
    llm_response = bedrock.invoke_model(**invoke_kwargs)
    logger.info("Claude call duration: %.2fs", time.time() - start_llm)

    raw = llm_response["body"].read()
    logger.info("Claude raw response: %s", raw)

    try:
        parsed = json.loads(raw)
    except Exception:
        return build_response(502, {"error": "Invalid model response"})

    assistant_text = ""
    for block in parsed.get("content", []) or []:
        if block.get("type") == "text":
            assistant_text += block.get("text", "")

    # 4) Return
    # Include filenames in context for UI to render sources
    context_payload = [{"text": c.text, "filename": c.filename} for c in top]

    return build_response(
        200,
        {
            "answer": assistant_text or "Sorry, I couldn't find any context matching your question.",
            "context": context_payload,
        },
    )
