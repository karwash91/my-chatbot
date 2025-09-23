import boto3
import json
import os
import math
from decimal import Decimal
import time

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["DOC_TABLE"])
bedrock = boto3.client("bedrock-runtime")

# Guardrails config (env overrides allowed)
GUARDRAIL_ID = "rqkveuut7fzm"
GUARDRAIL_VERSION = os.environ.get("BEDROCK_GUARDRAIL_VERSION", "1")

# --- Helpers ---

def decimal_to_float(obj):
    """Recursively convert Decimals to float for math ops."""
    if isinstance(obj, list):
        return [decimal_to_float(x) for x in obj]
    elif isinstance(obj, dict):
        return {k: decimal_to_float(v) for k, v in obj.items()}
    elif isinstance(obj, Decimal):
        return float(obj)
    else:
        return obj

def cosine_similarity(vec1, vec2):
    dot = sum(a * b for a, b in zip(vec1, vec2))
    norm1 = math.sqrt(sum(a * a for a in vec1))
    norm2 = math.sqrt(sum(b * b for b in vec2))
    return dot / (norm1 * norm2)

# --- Lambda handler ---

def handler(event, context):
    print("=== EVENT RECEIVED ===")
    print(json.dumps(event, indent=2))
    try:
        body = json.loads(event.get("body", "{}"))
        query = body.get("query")
        print("Parsed query:", query)

        if not query:
            return {"statusCode": 400, "body": json.dumps({"error": "No query provided"})}

        # 1. Embed the query
        embed_response = bedrock.invoke_model(
            modelId="amazon.titan-embed-text-v2:0",
            contentType="application/json",
            body=json.dumps({"inputText": query}),
        )
        print("Embed response received")
        query_vec = json.loads(embed_response["body"].read())["embedding"]

        # 2. Retrieve all chunks from DynamoDB (⚠️ for demo only, later switch to vector DB)
        resp = table.scan()
        print("DynamoDB scan completed. Retrieved {} items".format(len(resp.get("Items", []))))
        items = resp.get("Items", [])

        # 3. Compute similarities
        scored = []
        for item in items:
            chunk_vec = decimal_to_float(item["embedding"])
            score = cosine_similarity(query_vec, chunk_vec)
            scored.append((score, item["text"], item.get("filename", "")))

        print("Top chunk scores:", scored[:3])
        top_chunks = [{"text": t, "filename": f} for _, t, f in sorted(scored, key=lambda x: x[0], reverse=True)[:3]]

        # 4. Ask Bedrock LLM with context
        system_prompt = "You are a helpful DevOps assistant. Use the provided context to answer the user’s question in 1200 characters or less."

        # Input tagging for Bedrock Guardrails (required for prompt-attack detection with InvokeModel)
        guardrail_tag_suffix = "usr"  # must match tagSuffix below
        open_tag = f"<amazon-bedrock-guardrails-guardContent_{guardrail_tag_suffix}>"
        close_tag = f"</amazon-bedrock-guardrails-guardContent_{guardrail_tag_suffix}>"

        user_payload_text = (
            f"Here is some context:\n{chr(10).join([chunk['text'] for chunk in top_chunks])}\n\n"
            f"Question:\n{open_tag}\n{query}\n{close_tag}"
        )

        request_payload = {
            "anthropic_version": "bedrock-2023-05-31",
            "system": system_prompt,
            "max_tokens": 300,
            "messages": [
                {"role": "user", "content": [{"type": "text", "text": user_payload_text}]}
            ],
            # Required when using guardrails with InvokeModel; tagSuffix ties to the <...guardContent_suffix> tags above
            "amazon-bedrock-guardrailConfig": {"tagSuffix": guardrail_tag_suffix}
        }
        print("Claude request payload:", json.dumps(request_payload, indent=2))
        start = time.time()
        llm_response = bedrock.invoke_model(
            modelId="arn:aws:bedrock:us-east-1:588738567290:inference-profile/us.anthropic.claude-sonnet-4-20250514-v1:0",
            contentType="application/json",
            accept="application/json",
            guardrailIdentifier=GUARDRAIL_ID,
            guardrailVersion=GUARDRAIL_VERSION,
            trace="ENABLED",
            body=json.dumps(request_payload).encode("utf-8"),
        )
        duration = time.time() - start
        print(f"Claude call duration: {duration:.2f} seconds")
        raw_response = llm_response["body"].read()

        # Inspect guardrail action from response headers (INTERVENED | NONE)
        headers = llm_response.get("ResponseMetadata", {}).get("HTTPHeaders", {}) or {}

        print("Claude raw response:", raw_response)
        parsed = json.loads(raw_response)

        assistant_text = ""
        if "content" in parsed and parsed["content"]:
            for block in parsed["content"]:
                if block.get("type") == "text":
                    assistant_text += block.get("text", "")

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",   # allow all origins (or restrict to your frontend domain)
                "Access-Control-Allow-Headers": "Content-Type",
                "Access-Control-Allow-Methods": "OPTIONS,POST,GET"
            },
            "body": json.dumps({"answer": assistant_text, "context": top_chunks}),
        }
    except Exception as e:
        print("ERROR in handler:", str(e))
        import traceback
        traceback.print_exc()
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}