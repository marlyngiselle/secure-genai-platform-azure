# genai-service

Sample workload for the secure GenAI gateway. It shows the client side of the contract that the platform enforces.

| Concern | How the service handles it |
| --- | --- |
| Identity | `DefaultAzureCredential` gets an Entra ID token for the gateway audience. Managed identity in Azure, Azure CLI on a laptop |
| Quota | Sends the team APIM subscription key (from Key Vault) so token limits apply per team |
| Streaming | Relays server sent events from the gateway as they arrive |
| Traceability | Accepts or creates an `x-request-id`, forwards it to the gateway and returns it to the caller |
| Telemetry | OpenTelemetry traces to Application Insights when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set |
| Guardrails | Input length and message count limits, a regex denylist hook for prompt injection, and a PII redaction hook |

## Run locally

```bash
python3.11 -m venv .venv
.venv/bin/pip install -e ".[dev]"
export GENAI_GATEWAY_BASE_URL="https://apim-genai-dev-xxxxx.azure-api.net/openai"
az login
.venv/bin/uvicorn --factory genai_service.main:create_app --app-dir app/src --port 8080
```

```bash
curl -s localhost:8080/v1/chat \
  -H 'content-type: application/json' \
  -d '{"messages":[{"role":"user","content":"Say hello in five words"}],"stream":true}'
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `GENAI_GATEWAY_BASE_URL` | required | Output `gateway_base_url` of the Terraform stack |
| `GENAI_GATEWAY_SCOPE` | `api://genai-gateway/.default` | Entra ID scope for the gateway audience |
| `GENAI_DEPLOYMENT` | `gpt-4o-mini` | Model deployment name |
| `GENAI_API_VERSION` | `2024-10-21` | Azure OpenAI API version |
| `GENAI_SUBSCRIPTION_KEY` | none | Team APIM subscription key, mounted from Key Vault |
| `GENAI_MAX_INPUT_CHARS` | `8000` | Total characters accepted per conversation |
| `GENAI_MAX_MESSAGES` | `40` | Messages accepted per conversation |
| `AZURE_CLIENT_ID` | none | Client ID of the user-assigned workload identity |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | none | Enables OpenTelemetry export |

## Container

```bash
docker build -f app/Dockerfile -t genai-service:local .
docker run --rm -p 8080:8080 -e GENAI_GATEWAY_BASE_URL=https://example.invalid/openai genai-service:local
```
