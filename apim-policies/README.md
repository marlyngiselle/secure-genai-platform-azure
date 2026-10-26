# APIM policies

The gateway behaviour lives in three XML files. Terraform reads them with `file()` and `templatefile()`, so a policy change is a reviewed diff like any other code.

| File | Scope | Loaded by | What it enforces |
| --- | --- | --- | --- |
| [`global.xml`](global.xml) | Every API | `azurerm_api_management_policy.global` | Request ID on every call, removal of headers that fingerprint the platform |
| [`api-azure-openai.xml`](api-azure-openai.xml) | Azure OpenAI API | `azurerm_api_management_api_policy.openai` | Caller authentication, identity swap, backend pool routing, token metrics, retry with backoff, sanitised errors |
| [`product-team-token-limit.xml.tftpl`](product-team-token-limit.xml.tftpl) | One product per team | `azurerm_api_management_product_policy.team` | Tokens per minute and a token quota per subscription key |

## Evaluation order

APIM evaluates scopes from the outside in on the way in, and from the inside out on the way back. `<base />` marks where the parent scope runs.

```text
inbound    global -> product (token limit) -> API (auth, identity, routing, metrics)
backend    API (retry around forward-request)
outbound   API -> product -> global (request ID echo, header hygiene)
```

The token limit sits at product scope on purpose. A request rejected for quota never reaches the identity swap or the backend, so it costs nothing.

## api-azure-openai.xml, step by step

| Step | Policy | Why |
| --- | --- | --- |
| 1 | `validate-azure-ad-token` | Only workloads holding an Entra ID token for the gateway audience get in. A leaked subscription key alone is not enough |
| 2 | `set-header api-key delete` | A caller cannot smuggle a key to the backend. The accounts have local auth disabled anyway |
| 3 | `authentication-managed-identity` | The gateway calls Azure OpenAI as its user-assigned identity, which holds `Cognitive Services OpenAI User` and nothing more |
| 4 | `set-backend-service backend-id="openai-backend-pool"` | Routes to a pool of regional instances with priority and weight |
| 5 | `azure-openai-emit-token-metric` | Prompt, completion and total tokens per product, subscription and deployment, sent to Application Insights for showback |
| 6 | `retry` around `forward-request` | Retries 429 and 5xx with exponential backoff. The circuit breaker on each pool member takes a throttled region out for a minute and honours `Retry-After` |
| 7 | `on-error` | Returns a generic 502 with the request ID. Backend hostnames and stack details never reach the caller |

## Named values

| Name | Source in Terraform | Secret |
| --- | --- | --- |
| `entra-tenant-id` | `data.azurerm_client_config.current.tenant_id` | No |
| `gateway-audience` | `var.gateway_audience` | No |
| `apim-identity-client-id` | `azurerm_user_assigned_identity.apim.client_id` | No |

## Streaming

`forward-request` uses `buffer-response="false"` so server sent events reach the caller as the model produces them. On streamed calls the gateway cannot read a usage block before it starts forwarding, which is why the token limit policy runs with `estimate-prompt-tokens="true"`.

## Changing a policy

1. Edit the XML file.
2. Run `xmllint --noout apim-policies/*.xml` for well formedness.
3. Open a pull request. CI runs `terraform validate`, and `terraform plan` shows the exact policy diff.
