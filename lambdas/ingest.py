import json
import boto3
import os
import re
import uuid
import logging
from dataclasses import dataclass
from decimal import Decimal
from typing import Any, Dict, Generator, List

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# -----------------------------------------------------------------------------
# AWS Clients
# -----------------------------------------------------------------------------
s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
bedrock = boto3.client("bedrock-runtime")

# -----------------------------------------------------------------------------
# Configuration (parameterized)
# -----------------------------------------------------------------------------
DOCS_BUCKET: str = os.environ.get("DOCS_BUCKET", "")
DOCS_TABLE: str = os.environ.get("DOCS_TABLE", "")
EMBEDDING_MODEL_ID: str = os.environ.get("EMBEDDING_MODEL_ID", "amazon.titan-embed-text-v2:0")
CHUNK_SIZE: int = int(os.environ.get("CHUNK_SIZE", "500"))

table = dynamodb.Table(DOCS_TABLE)

# -----------------------------------------------------------------------------
# Data Models
# -----------------------------------------------------------------------------
@dataclass
class UploadMessage:
    doc_id: str
    s3_key: str
    filename: str

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
def float_to_decimal(obj: Any) -> Any:
    """Recursively convert floats to Decimals for DynamoDB storage."""
    if isinstance(obj, list):
        return [float_to_decimal(x) for x in obj]
    if isinstance(obj, dict):
        return {k: float_to_decimal(v) for k, v in obj.items()}
    if isinstance(obj, float):
        return Decimal(str(obj))
    return obj


def chunk_text(text: str, chunk_size: int = CHUNK_SIZE) -> Generator[str, None, None]:
    """Split text into chunks of approximately `chunk_size` words."""
    words = re.split(r"\s+", text)
    for i in range(0, len(words), chunk_size):
        yield " ".join(words[i:i + chunk_size])


def embed_text(chunk: str) -> List[float]:
    """Call Bedrock Titan Embeddings and return embedding vector."""
    response = bedrock.invoke_model(
        modelId=EMBEDDING_MODEL_ID,
        body=json.dumps({"inputText": chunk})
    )
    embedding_response = json.loads(response["body"].read())
    return embedding_response["embedding"]

# -----------------------------------------------------------------------------
# Lambda Handler
# -----------------------------------------------------------------------------
def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    logger.info("Received event: %s", json.dumps(event))

    for record in event.get("Records", []):
        msg_dict = json.loads(record["body"])
        msg = UploadMessage(
            doc_id=msg_dict["doc_id"],
            s3_key=msg_dict["s3_key"],
            filename=msg_dict.get("filename", "")
        )

        # Get file from S3
        obj = s3.get_object(Bucket=DOCS_BUCKET, Key=msg.s3_key)
        raw_bytes: bytes = obj["Body"].read()
        logger.info("Raw bytes preview: %s", raw_bytes[:200])

        decoded: str = raw_bytes.decode("utf-8", errors="replace")
        logger.info("Decoded preview: %s", decoded[:200])

        # Parse JSON if possible, fallback to raw text
        try:
            loaded = json.loads(decoded)
            text: str = loaded if isinstance(loaded, str) else decoded
        except json.JSONDecodeError:
            text = decoded

        logger.info("Final text preview: %s", text[:200])

        # Split into chunks and embed
        for idx, chunk in enumerate(chunk_text(text)):
            embeddings = embed_text(chunk)

            table.put_item(
                Item={
                    "doc_id": msg.doc_id,
                    "chunk_id": f"chunk-{idx}",
                    "text": chunk,
                    "embedding": float_to_decimal(embeddings),
                    "filename": msg.filename,
                }
            )
            logger.info(
                "Stored doc %s chunk-%d with embedding for filename %s",
                msg.doc_id, idx, msg.filename
            )

    return {"statusCode": 200}