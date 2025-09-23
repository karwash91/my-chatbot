# Import typing essentials
from typing import Dict, Any, Optional
import json
import boto3
import uuid
import base64
import os
import re
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


# Constants and AWS clients with type hints
CONTENT_TYPE_JSON: str = "application/json"
DOCS_BUCKET: str = os.environ.get("DOCS_BUCKET", "")
INGEST_QUEUE_URL: str = os.environ.get("INGEST_QUEUE_URL", "")
s3: Any = boto3.client("s3")
sqs: Any = boto3.client("sqs")

# Helper functions for S3 and SQS actions
def save_to_s3(bucket: str, key: str, data: bytes) -> None:
    s3.put_object(Bucket=bucket, Key=key, Body=data)
    logger.info(f"Saved to S3 with key: {key}, size: {len(data)} bytes")

def send_sqs_message(queue_url: str, message_body: str) -> None:
    sqs.send_message(QueueUrl=queue_url, MessageBody=message_body)
    logger.info(f"Sent SQS message: {message_body[:300]}")

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Upload Lambda:
    - Saves uploaded doc content to S3
    - Sends job message to SQS for ingestion
    """
    try:
        body: Dict[str, Any] = json.loads(event.get("body", "{}"))

        filename: Optional[str] = body.get("filename")
        content: str = body.get("content", "")
        logger.info(f"Received filename: {filename}")
        logger.info(f"Received content (first 200 chars): {content[:200]}")

        if not filename or not content:
            logger.error("Missing filename or content")
            return {
                "statusCode": 400,
                "headers": {"Content-Type": CONTENT_TYPE_JSON},
                "body": json.dumps({"error": "Missing filename or content"})
            }

        doc_id: str = str(uuid.uuid4())
        s3_key: str = f"{doc_id}/{filename}"

        # For simplicity, this demo assumes UTF-8 plain text only
        content_bytes: bytes = content.encode("utf-8", errors="replace")
        logger.info(f"Encoded content bytes (first 200 bytes): {content_bytes[:200]}")

        save_to_s3(DOCS_BUCKET, s3_key, content_bytes)

        message_body: str = json.dumps({
            "doc_id": doc_id,
            "filename": filename,
            "s3_key": s3_key
        })
        send_sqs_message(INGEST_QUEUE_URL, message_body)

        return {
            "statusCode": 200,
            "headers": {"Content-Type": CONTENT_TYPE_JSON},
            "body": json.dumps({
                "message": "File uploaded and ingest job queued",
                "doc_id": doc_id,
                "s3_key": s3_key
            })
        }

    except Exception as e:
        logger.error(f"Error in upload handler: {e}")
        return {
            "statusCode": 500,
            "headers": {"Content-Type": CONTENT_TYPE_JSON},
            "body": json.dumps({"error": str(e)})
        }