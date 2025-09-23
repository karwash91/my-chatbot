import json
import boto3
import uuid
import base64
import os
import re

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

        # Expect filename + content (Base64 encoded or raw text)
        filename = body.get("filename")
        content = body.get("content", "")

        if not filename or not content:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Missing filename or content"})
            }

        # Generate unique ID for this doc
        doc_id = str(uuid.uuid4())
        s3_key = f"{doc_id}/{filename}"

        # Heuristic to check if content looks like base64
        base64_pattern = re.compile(r'^[A-Za-z0-9+/=]+\Z')
        if len(content) % 4 == 0 and base64_pattern.match(content):
            try:
                content_bytes = base64.b64decode(content, validate=True)
            except Exception:
                content_bytes = content.encode("utf-8")
        else:
            content_bytes = content.encode("utf-8")

        # Save file to S3
        s3.put_object(Bucket=DOCS_BUCKET, Key=s3_key, Body=content_bytes)

        # Push job to ingest queue
        sqs.send_message(
            QueueUrl=INGEST_QUEUE_URL,
            MessageBody=json.dumps({
                "doc_id": doc_id,
                "filename": filename,
                "s3_key": s3_key
            })
        )

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
        print("Error in upload handler:", e)
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)})
        }