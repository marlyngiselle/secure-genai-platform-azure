<div align="center">

<img src=".github/assets/secure-genai-platform-azure-banner.svg" alt="Secure GenAI Platform on Azure" width="100%">

# Secure GenAI Platform on Azure

Run Azure OpenAI for many teams through one private, keyless and metered gateway.

<a href="infra/terraform"><img src="https://img.shields.io/badge/Azure-private%20by%20default-0b1f4d?style=for-the-badge&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPHBhdGggZmlsbD0id2hpdGUiIGQ9Ik02LjUgMTlhNC41IDQuNSAwIDAgMS0uOS04LjkxQTYgNiAwIDAgMSAxNy4yIDguNiA1IDUgMCAwIDEgMTggMTl6Ii8%2BPC9zdmc%2B" alt="Azure"></a>
<a href="apim-policies"><img src="https://img.shields.io/badge/Azure%20OpenAI-behind%20APIM-16367f?style=for-the-badge&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0xMiAybDIuNCA3LjZMMjIgMTJsLTcuNiAyLjRMMTIgMjJsLTIuNC03LjZMMiAxMmw3LjYtMi40eiIvPjwvc3ZnPg%3D%3D" alt="Azure OpenAI"></a>
<a href="infra/terraform/versions.tf"><img src="https://img.shields.io/badge/Terraform-azurerm%204%20%2B%20azapi%202-1a3a8a?style=for-the-badge&logo=terraform&logoColor=white" alt="Terraform"></a>
<a href="app"><img src="https://img.shields.io/badge/Python-3.11-2456c8?style=for-the-badge&logo=python&logoColor=white" alt="Python"></a>
<a href="app"><img src="https://img.shields.io/badge/FastAPI-streaming-2456c8?style=for-the-badge&logo=fastapi&logoColor=white" alt="FastAPI"></a>
<a href=".github/workflows/ci.yml"><img src="https://img.shields.io/badge/CI-pinned%20%2B%20OIDC-16367f?style=for-the-badge&logo=githubactions&logoColor=white" alt="GitHub Actions"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-0b1f4d?style=for-the-badge" alt="MIT License"></a>

</div>

<br>

## In numbers

| | |
| --- | --- |
| 0 | API keys in the chain. Local auth is disabled on every Cognitive Services account |
| 43 | Terraform resource blocks across 31 resource types, in 14 files |
| 18 | Validation rules guarding 14 of the 18 input variables |
| 3 | APIM policy files, loaded by Terraform as reviewed code |
| 4 | Private DNS zones, so models, secrets and the gateway resolve only inside the VNet |
| 9 | Offline `terraform test` runs with mocked providers |
| 44 | Python unit tests, 94 percent branch coverage |
| 15 | STRIDE threats mapped to a control and a file |
| 3 | Architecture decision records |

## What it is

A reference platform for putting generative AI into production inside an enterprise. Every team calls one API Management gateway, which authenticates the caller with Entra ID, enforces a token budget per team, swaps in its own managed identity and routes to Azure OpenAI deployments in two regions over private endpoints. Usage is emitted as token metrics per team, so cost can be shown back without asking anyone for a spreadsheet. A small FastAPI service shows the client side of the contract, with streaming, request tracing and input guardrails.

## Architecture

```mermaid
flowchart LR
  subgraph consumers["Consumers"]
    app["fa:fa-cube genai-service<br/>FastAPI, workload identity"]
    other["fa:fa-users Other team workloads"]
  end

  subgraph gateway["AI gateway, API Management (Internal VNet)"]
    direction TB
    auth["fa:fa-id-badge validate-azure-ad-token"]
    quota["fa:fa-gauge azure-openai-token-limit<br/>per team product"]
    mi["fa:fa-key authentication-managed-identity"]
    metric["fa:fa-chart-line azure-openai-emit-token-metric"]
    pool["fa:fa-shuffle Backend pool<br/>retry, circuit breaker"]
    auth --> quota --> mi --> metric --> pool
  end

  subgraph models["Models, private endpoints only"]
    aoai1["fa:fa-brain Azure OpenAI<br/>primary region"]
    aoai2["fa:fa-brain Azure OpenAI<br/>secondary region"]
  end

  subgraph security["Identity and secrets"]
    entra["fa:fa-user-shield Entra ID"]
    kv["fa:fa-lock Key Vault, RBAC"]
    cs["fa:fa-filter Content Safety"]
  end

  subgraph observe["Observability"]
    appi["fa:fa-wave-square Application Insights"]
    law["fa:fa-database Log Analytics"]
  end

  app -- "Bearer token + team key" --> auth
  other --> auth
  app -. "token" .- entra
  app -. "subscription key" .- kv
  app -. "screening" .- cs
  pool --> aoai1
  pool --> aoai2
  metric --> appi
  app -- "OpenTelemetry" --> appi
  appi --> law
  aoai1 -. "diagnostics" .-> law
  aoai2 -. "diagnostics" .-> law

  classDef consumer fill:#0b1f4d,stroke:#8fb3ff,stroke-width:2px,color:#ffffff
  classDef gw fill:#1a3a8a,stroke:#c7d7ff,stroke-width:2px,color:#ffffff
  classDef model fill:#2456c8,stroke:#ffffff,stroke-width:2px,color:#ffffff
  classDef sec fill:#12306e,stroke:#8fb3ff,stroke-width:2px,color:#ffffff
  classDef obs fill:#16367f,stroke:#8fb3ff,stroke-width:2px,color:#ffffff
  class app,other consumer
  class auth,quota,mi,metric,pool gw
  class aoai1,aoai2 model
  class entra,kv,cs sec
  class appi,law obs
  style consumers fill:#eef3ff,stroke:#2456c8,stroke-width:1px,color:#0b1f4d
  style gateway fill:#eef3ff,stroke:#2456c8,stroke-width:1px,color:#0b1f4d
  style models fill:#eef3ff,stroke:#2456c8,stroke-width:1px,color:#0b1f4d
  style security fill:#eef3ff,stroke:#2456c8,stroke-width:1px,color:#0b1f4d
  style observe fill:#eef3ff,stroke:#2456c8,stroke-width:1px,color:#0b1f4d
```

Network topology, subnets and NSGs are in [docs/architecture.md](docs/architecture.md).

## How a request flows

```mermaid
sequenceDiagram
  autonumber
  participant C as Client
  participant S as genai-service
  participant E as Entra ID
  participant G as APIM gateway
  participant P as Azure OpenAI primary
  participant B as Azure OpenAI secondary
  participant M as Application Insights

  C->>S: POST /v1/chat (x-request-id)
  S->>S: Guard (length, denylist) and PII redaction
  S->>E: Token for api://genai-gateway (managed identity)
  E-->>S: Access token, cached until near expiry
  S->>G: Chat completions, Bearer + subscription key + x-request-id
  G->>G: Validate token, check team token budget
  G->>E: Token for Cognitive Services (gateway identity)
  G->>P: Forward via private endpoint
  P-->>G: 429 Too Many Requests
  Note over G,P: Circuit breaker opens for the primary, retry with backoff
  G->>B: Forward via private endpoint
  B-->>G: Server sent events
  G-->>M: Prompt, completion and total tokens per team
  G-->>S: Stream, x-request-id echoed
  S-->>C: Stream, same x-request-id
```

## Quick start

Everything below runs on a laptop without an Azure subscription.

```bash
git clone https://github.com/marlyngiselle/secure-genai-platform-azure.git
cd secure-genai-platform-azure

# Infrastructure, offline
terraform -chdir=infra/terraform init -backend=false
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform test
tflint --chdir=infra/terraform --config="$PWD/.tflint.hcl" --init
tflint --chdir=infra/terraform --config="$PWD/.tflint.hcl"

# Sample service
python3.11 -m venv .venv
.venv/bin/pip install -e ".[dev]"
.venv/bin/ruff check . && .venv/bin/mypy && .venv/bin/pytest
```

To deploy, write your state storage account into `infra/terraform/backend.hcl` (see `backend.hcl.example`), then run from a machine with access to Azure.

```bash
az login
export TF_VAR_subscription_id="$(az account show --query id -o tsv)"
terraform -chdir=infra/terraform init -backend-config=backend.hcl
terraform -chdir=infra/terraform plan -var-file=env/dev.tfvars -out=tfplan
terraform -chdir=infra/terraform apply tfplan
```

Then point the sample service at the gateway from inside the VNet.

```bash
export GENAI_GATEWAY_BASE_URL="$(terraform -chdir=infra/terraform output -raw gateway_base_url)"
export AZURE_CLIENT_ID="$(terraform -chdir=infra/terraform output -raw workload_identity_client_id)"
.venv/bin/uvicorn --factory genai_service.main:create_app --app-dir app/src --port 8080
```

## Security model

| Control | Layer | Implementation |
| --- | --- | --- |
| No public model endpoint | Network | `public_network_access_enabled = false` and a private endpoint per account, DNS in `privatelink.openai.azure.com` |
| No keys | Identity | `local_auth_enabled = false` on Azure OpenAI and Content Safety |
| Caller authentication | Gateway | `validate-azure-ad-token` against the gateway audience, plus a product subscription key |
| Backend authentication | Gateway | `authentication-managed-identity` with a user-assigned identity |
| Least privilege | RBAC | `Cognitive Services OpenAI User` for the gateway, `Key Vault Secrets User` and `Monitoring Metrics Publisher` for the workload |
| Fair use | Gateway | `azure-openai-token-limit` per team, tokens per minute and a periodic quota |
| Resilience | Gateway | Backend pool across regions, circuit breaker on 429 and 5xx, retry with exponential backoff |
| Secrets | Key Vault | RBAC mode, private endpoint, purge protection, `prevent_destroy` |
| Input hygiene | Workload | Length and message limits, prompt injection denylist hook, PII redaction hook |
| Traceability | All | `x-request-id` from client to model and back, diagnostic settings on every resource |
| Supply chain | CI | Actions pinned to commit SHA, `persist-credentials: false`, OIDC instead of secrets |

The full STRIDE analysis is in [docs/threat-model.md](docs/threat-model.md).

## Delivery

```mermaid
flowchart LR
  pr["fa:fa-code-pull-request Pull request"] --> tf["fa:fa-cubes terraform<br/>fmt, validate, test, tflint"]
  pr --> py["fa:fa-flask app<br/>ruff, mypy, pytest"]
  pr --> dl["fa:fa-docker dockerfile<br/>hadolint"]
  tf --> plan["fa:fa-file-lines plan via OIDC<br/>disabled by default"]
  py --> plan
  plan --> gate{"fa:fa-user-check Environment<br/>approval"}
  gate --> apply["fa:fa-rocket apply"]

  classDef auto fill:#1a3a8a,stroke:#c7d7ff,stroke-width:2px,color:#ffffff
  classDef manual fill:#0b1f4d,stroke:#8fb3ff,stroke-width:2px,color:#ffffff
  classDef off fill:#2456c8,stroke:#ffffff,stroke-width:2px,color:#ffffff,stroke-dasharray:5 5
  class pr,tf,py,dl auto
  class gate manual
  class plan,apply off
```

The three validation jobs run on every pull request with no cloud access. The plan job is wired for OIDC federation and stays off until a federated credential and the repository variables exist.

## Before you deploy

> [!WARNING]
> An APIM instance injected in a VNet takes 30 to 60 minutes to create, and the Developer SKU has no SLA. Use `Premium_N` with zones for production.

> [!IMPORTANT]
> In `Internal` mode the gateway has no public DNS name. The sample service, your laptop or your CI runner must resolve `azure-api.net` through the private zone, which means running inside the VNet or through a peered network with DNS forwarding.

> [!WARNING]
> Model deployments consume regional quota of the subscription. If a region has no capacity left for a model, the apply fails with `InsufficientQuota`. Check quota per region before adding a pool member.

> [!CAUTION]
> Key Vault and Cognitive Services accounts are soft deleted. With purge protection on, a destroyed vault keeps its name for 90 days. The random suffix on globally unique names exists so a rebuild does not collide with the deleted copy.

## Repository map

| Path | What it holds |
| --- | --- |
| [`infra/terraform/`](infra/terraform) | Root module, one file per concern (network, openai, apim, keyvault, monitoring, rbac) |
| [`infra/terraform/tests/`](infra/terraform/tests) | Offline plan tests with mocked providers |
| [`infra/terraform/env/`](infra/terraform/env) | Variable files per environment |
| [`apim-policies/`](apim-policies) | Gateway policies as XML, with a step by step explanation |
| [`app/`](app) | FastAPI sample service, tests and Dockerfile |
| [`docs/`](docs) | Architecture, threat model, operating model and ADRs |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | Validation pipeline and the disabled OIDC plan job |

## Documentation

| Document | Answers |
| --- | --- |
| [Architecture](docs/architecture.md) | How the network, the gateway and the models fit together, and why azapi is used twice |
| [Threat model](docs/threat-model.md) | What can go wrong on the request path and which control stops it |
| [Operating model](docs/operating-model.md) | How a team is onboarded, how quotas are sized and how cost is shown back |
| [APIM policies](apim-policies/README.md) | What each policy does, in order |
| [ADR 0001](docs/adr/0001-api-management-as-ai-gateway.md) | Why API Management is the AI gateway |
| [ADR 0002](docs/adr/0002-managed-identity-no-keys.md) | Why there are no API keys anywhere |
| [ADR 0003](docs/adr/0003-token-based-quotas-per-team.md) | Why quotas are counted in tokens, per team |
| [Sample service](app/README.md) | How the client side of the contract works |

<br>

<div align="center">
<sub>Built and maintained by Giselle Da Costa. MIT licensed.</sub>
</div>
