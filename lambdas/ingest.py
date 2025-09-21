import json
import boto3
import os
import re
import uuid
from decimal import Decimal

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
bedrock = boto3.client("bedrock-runtime")

DOCS_BUCKET = os.environ.get("DOCS_BUCKET")
DOCS_TABLE = os.environ.get("DOCS_TABLE")

table = dynamodb.Table(DOCS_TABLE)

def float_to_decimal(obj):
    """
    Recursively convert floats in a dict/list to Decimals (for DynamoDB).
    """
    if isinstance(obj, list):
        return [float_to_decimal(x) for x in obj]
    elif isinstance(obj, dict):
        return {k: float_to_decimal(v) for k, v in obj.items()}
    elif isinstance(obj, float):
        return Decimal(str(obj))  # safe: preserves precision
    else:
        return obj

# Simple chunker: split text into ~500 words
def chunk_text(text, chunk_size=500):
    words = re.split(r"\s+", text)
    for i in range(0, len(words), chunk_size):
        yield " ".join(words[i:i+chunk_size])

def handler(event, context):
    print("Received event:", json.dumps(event))

    for record in event["Records"]:
        msg = json.loads(record["body"])
        doc_id = msg["doc_id"]
        s3_key = msg["s3_key"]

        # Get file from S3
        obj = s3.get_object(Bucket=DOCS_BUCKET, Key=s3_key)
        raw_bytes = obj["Body"].read()
        try:
            text = raw_bytes.decode("utf-8")
        except UnicodeDecodeError:
            text = raw_bytes.decode("latin-1", errors="replace")

        # Split into chunks
        for idx, chunk in enumerate(chunk_text(text)):
            # Call Bedrock Titan Embeddings
            response = bedrock.invoke_model(
                modelId="amazon.titan-embed-text-v2:0",
                body=json.dumps({"inputText": chunk})
            )
            embedding_response = json.loads(response["body"].read())
            embeddings = embedding_response["embedding"]
            
            # Store in DynamoDB
            table.put_item(
                Item={
                    "doc_id": doc_id,
                    "chunk_id": f"chunk-{idx}",
                    "text": chunk,
                    "embedding": float_to_decimal(embeddings)  # vector stored as list
                }
            )

            print(f"Stored doc {doc_id} chunk-{idx} with embedding")

    return {"statusCode": 200}