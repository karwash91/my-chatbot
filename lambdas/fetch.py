import json

def handler(event, context):
    """
    Fetches chat results from DynamoDB.
    For now: just returns a placeholder response.
    """
    print("Fetch event:", event)

    session_id = event.get("pathParameters", {}).get("session_id", "unknown")

    return {
        "statusCode": 200,
        "headers": { "Content-Type": "application/json" },
        "body": json.dumps({
            "session_id": session_id,
            "response": "Fetch Lambda alive!"
        })
    }