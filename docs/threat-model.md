# Threat model

Scope is the request path from a workload to a model deployment, through the gateway. The method is STRIDE per element, followed by the residual risks the platform accepts.

## Assets

| Asset | Why it matters |
| --- | --- |
| Model capacity (TPM quota) | Finite and shared. Exhaustion is a denial of service for every team |
| Prompts and completions | Can contain business data and personal data |
| Gateway identity | Can call every model deployment behind the pool |
| Team subscription keys | Map a caller to a quota and a cost centre |
| Telemetry | Must prove who used what, without itself becoming a data leak |

## Trust boundaries

1. Workload to gateway, inside the VNet.
2. Gateway to Azure OpenAI, through private endpoints.
3. Control plane, from the CI pipeline to Azure Resource Manager.

## STRIDE for the GenAI gateway

| Threat | Example against this system | Mitigation in this repo | Where |
| --- | --- | --- | --- |
| Spoofing | A workload reuses a leaked subscription key to consume another team's quota | Every call needs both an Entra ID token for the gateway audience and a product subscription key | `validate-azure-ad-token` in `api-azure-openai.xml` |
| Spoofing | A caller calls Azure OpenAI directly with a key | Local auth disabled, public network access disabled, no keys exist | `openai.tf` |
| Tampering | A caller injects an `api-key` header or overrides the backend URL | Header deleted, backend fixed by policy, `min_api_version` set | `api-azure-openai.xml`, `apim.tf` |
| Tampering | Prompt injection tries to override the system prompt | Denylist hook and input limits in the workload, Content Safety and model content filters downstream | `app/src/genai_service/guards.py` |
| Tampering | Unreviewed change to a policy | Policies are files in Git, applied only by Terraform through CI | `apim-policies/`, `.github/workflows/ci.yml` |
| Repudiation | A team disputes its token consumption | Token metrics per product, subscription and deployment, request ID returned to the caller and logged at each hop | `azure-openai-emit-token-metric`, `request_context.py` |
| Information disclosure | PII in prompts reaches the model or the logs | Redaction hook runs before the gateway call. APIM diagnostic logs headers only, body bytes set to 0 | `redaction.py`, `azapi_resource.apim_diagnostic` |
| Information disclosure | Error bodies reveal backend hostnames or regions | `on-error` returns a generic 502, region and APIM headers stripped | `api-azure-openai.xml`, `global.xml` |
| Information disclosure | DNS or network path exposes the model endpoint | Private endpoints and private DNS zones, gateway in Internal mode | `network.tf`, `openai.tf` |
| Denial of service | One team floods the models and starves the others | Tokens per minute and token quota per product, counted on tokens not requests | `product-team-token-limit.xml.tftpl` |
| Denial of service | One region throttles | Pool across regions, circuit breaker per member, retry with backoff | `apim.tf`, `api-azure-openai.xml` |
| Denial of service | Oversized prompts burn capacity | Input length and message count limits before the call | `guards.py` |
| Elevation of privilege | Gateway identity used to manage deployments | Only `Cognitive Services OpenAI User`, a data plane role | `rbac.tf` |
| Elevation of privilege | Workload reads secrets it does not own | Key Vault in RBAC mode, `Key Vault Secrets User` only | `keyvault.tf`, `rbac.tf` |
| Elevation of privilege | CI pipeline holds a long lived secret | OIDC federation, no client secret, deploy job gated by an environment | `.github/workflows/ci.yml` |

## Residual risks

| Risk | Status | Next step |
| --- | --- | --- |
| Regex denylists miss novel injection techniques | Accepted for the sample. It is a cheap first filter, not a control of record | Call Content Safety Prompt Shields from the workload or the gateway |
| Regex PII redaction has false negatives | Accepted for the sample | Replace `RegexPiiRedactor` with Azure AI Language PII detection behind the same interface |
| Application Insights keeps local auth for the APIM logger | Accepted | Move the logger to managed identity and set `local_authentication_disabled` |
| Model output is not screened | Open | Add Content Safety text analysis on completions for user facing scenarios |
| Indirect prompt injection through retrieved documents | Out of scope | Belongs to the RAG layer, which this repo does not ship |
