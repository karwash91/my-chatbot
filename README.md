[UI (React/Vite)]
        │
        │  https
        ▼
[CloudFront CDN]  ──→  [S3 Frontend Bucket]
        │
        │  https (Authorization: Cognito tokens / or bearer)
        ▼
[API Gateway /dev]
   │        │
   │        ├── POST /chat ──→ [Lambda: chat] ──→ [Bedrock InvokeModel + ApplyGuardrail]
   │        │                                 └── (returns {answer, sources})
   │        │
   │        └── POST /upload → [Lambda: upload] ──→ [S3 docs-bucket/<doc_id>/file]
   │                                          └── [SQS enqueue {doc_id, s3_key, filename}]
   │
   └── GET /fetch/{session_id} (optional) → [Lambda: fetch]
                                            └── [DynamoDB answers/docs]


Ingestion path
	1.	Frontend (or a script) calls POST /upload with { filename, content }.
	2.	upload lambda writes the raw file to S3 and enqueues an ingest job on SQS.
	3.	ingest lambda consumes SQS message, reads S3, chunks text, creates embeddings, and stores chunks in DynamoDB:
	•	Partition keys include doc_id (and we store filename alongside each chunk for later attribution in answers).
	4.	chat lambda runs retrieval over DynamoDB/embeddings, calls Bedrock with Guardrails applied, and returns { answer, sources: [filenames...] }.

Chat path
	•	Frontend calls POST /chat { query } → API GW → chat lambda → Bedrock → response goes back to UI.
	•	UI shows the answer and a deduped list of filenames (hidden when the answer starts with “Sorry …”).

⸻

Components

Frontend (React + Vite)
	•	Served via CloudFront → S3 (private bucket with OAI; static site index).
	•	Uses VITE_… env vars generated from Terraform outputs during CI:
	•	VITE_API_BASE_URL
	•	VITE_COGNITO_CLIENT_ID
	•	VITE_COGNITO_DOMAIN
	•	VITE_COGNITO_ISSUER
	•	ChatWindow:
	•	Right-aligned user bubbles (max-width 70%, width = text width), left-aligned bot bubbles.
	•	“Suggested prompts” component.
	•	Upload form component (UploadForm.tsx) that calls POST /upload.
	•	Shows deduped sources under answers using the .caption-text class (only when answer doesn’t contain “Sorry”).

Identity (Cognito)
	•	User Pool + Hosted UI.
	•	Allowed callbacks/sign-outs are set from Terraform to match the current CloudFront URL and localhost:5173 for local dev.
	•	React uses Authorization Code Flow via Hosted UI and stores tokens client-side.

API (API Gateway REST)
	•	Endpoints: /chat, /upload, /fetch/{session_id}.
	•	CORS:
	•	OPTIONS mock integrations return Access-Control-Allow-* headers.
	•	If you need credentials (cookies/Authorization), don’t use * for origin; echo the request origin or specify the exact origins (CloudFront + localhost).
	•	A deployment trigger ensures changes to methods/integrations force a new API deployment.

Compute (Lambda)
	•	upload, ingest-worker, chat, fetch.
	•	Code is uploaded to an S3 code bucket and referenced by s3_bucket/s3_key (faster, avoids large inline zips).
	•	source_code_hash is set to the SHA of each zip so Terraform detects code changes and updates the function.
	•	CloudWatch Logs enabled automatically; code uses print()/logger to emit useful debugging at each step (upload receive, S3 write, SQS payload, ingest chunk counts, first N characters of text, etc.).

Data (S3, DynamoDB, SQS)
	•	S3: my-chatbot-docs-<region>-<account> (private) stores uploaded files by doc_id prefix.
	•	DynamoDB:
	•	my-chatbot-docs (document/chunk/embedding index; includes filename for attribution).
	•	my-chatbot-answers (optional for sessions/history).
	•	Encryption at rest is AWS-managed (for demo; recommend KMS in prod).
	•	SQS: my-chatbot-ingest-queue triggers ingest-worker.

Content Generation (Bedrock)
	•	InvokeModel with Guardrails via bedrock:ApplyGuardrail (IAM-allowed on the specific guardrail ARN).
	•	Guardrails: blocks/filters unsafe content, sensitive topics, and enforces your moderation policy.
You implemented:
	•	Use of a guardrail ARN and version in the InvokeModel request.
	•	Lambda IAM includes bedrock:InvokeModel and bedrock:ApplyGuardrail on that guardrail resource.

⸻

Security, Governance, Controls

Data handling
	•	Stateless chat: Chat requests/responses are not persisted by default (beyond Lambda logs).
	•	Documents: Uploaded text is stored in S3 and DynamoDB (for retrieval).
	•	PII: If PII is present in source docs, it will be embedded; ensure you have a data classification policy for what’s allowed in docs/.

Bedrock data usage
	•	By design, Amazon Bedrock does not use your data to train base models by default. Review your account settings/policies to confirm data usage/retention preferences for your organization.

Guardrails for governance
	•	Bedrock Guardrails are configured and enforced by IAM:
	•	The Lambda role is explicitly allowed to ApplyGuardrail only on your guardrail ARN.
	•	Update guardrail definitions centrally to evolve policy without app code changes.
	•	Consider adding CloudTrail rules/alerts for bedrock:* activity.

IAM least privilege
	•	Lambda role grants:
	•	Minimal S3 access to docs/code buckets (scoped to bucket ARNs/prefixes).
	•	DynamoDB table read/write on the two chatbot tables.
	•	SQS receive/delete for the ingest queue.
	•	Bedrock Invoke/ApplyGuardrail for specific models/guardrail.
	•	API Gateway → Lambda permissions added per function/route.

Network / CORS
	•	API Gateway CORS configured for localhost and the current CloudFront domain.
	•	CloudFront restricts bucket access via Origin Access Identity; S3 public access is blocked.

Logging & monitoring
	•	CloudWatch Logs for all Lambdas, with additional debug prints in upload.py and ingest.py (ingest shows text lengths and sample prefixes to catch encoding issues).
	•	Consider adding metrics/alarms on Lambda errors, DLQs for SQS, and API GW 4xx/5xx rates.

State & governance
	•	Terraform remote state in s3://karwash91-tfstate/chatbot/terraform.tfstate.
	•	CI enforces consistent deployments; a separate manual “destroy” job exists for cleanup.

Upload a doc (script example)

API_URL="<api-invoke-url>/upload"
for f in docs/*.txt; do
  echo "Uploading $f"
  json=$(jq -n --arg fn "$(basename "$f")" --rawfile c "$f" '{filename:$fn, content:$c}')
  curl -s -X POST "$API_URL" -H "Content-Type: application/json" -d "$json" | jq .
done