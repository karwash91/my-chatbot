# Logs are sent to CloudWatch by default when using AWS Lambda.
import json
import boto3
import uuid
import base64
import os
import re
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
sqs = boto3.client("sqs")

DOCS_BUCKET = os.environ.get("DOCS_BUCKET")
INGEST_QUEUE_URL = os.environ.get("INGEST_QUEUE_URL")

def handler(event, context):
    """
    Upload Lambda:
    - Saves uploaded doc content to S3
    - Sends job message to SQS for ingestion
    """
    try:
        body = json.loads(event.get("body", "{}"))

        # Expect filename + content (plain UTF-8 text)
        filename = body.get("filename")
        content = body.get("content", "")
        logger.info(f"Received filename: {filename}")
        logger.info(f"Received content (first 200 chars): {content[:200]}")

        if not filename or not content:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Missing filename or content"})
            }

        # Generate unique ID for this doc
        doc_id = str(uuid.uuid4())
        s3_key = f"{doc_id}/{filename}"

        # For simplicity, this demo assumes UTF-8 plain text only
        content_bytes = content.encode("utf-8", errors="replace")
        logger.info(f"Encoded content bytes (first 200 bytes): {content_bytes[:200]}")

        # Save file to S3
        s3.put_object(Bucket=DOCS_BUCKET, Key=s3_key, Body=content_bytes)
        logger.info(f"Saved to S3 with key: {s3_key}, size: {len(content_bytes)} bytes")

        # Push job to ingest queue
        message_body = json.dumps({
            "doc_id": doc_id,
            "filename": filename,
            "s3_key": s3_key
        })
        sqs.send_message(
            QueueUrl=INGEST_QUEUE_URL,
            MessageBody=message_body
        )
        logger.info(f"Sent SQS message: {message_body}")

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "message": "File uploaded and ingest job queued",
                "doc_id": doc_id,
                "s3_key": s3_key
            })
        }

    except Exception as e:
        logger.error("Error in upload handler: %s", e)
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)})
        }