# ADR 0002. Managed identity end to end, no API keys

| Status | Date |
| --- | --- |
| Accepted | 2026-03-09 |

## Context

Azure OpenAI accounts accept API keys by default. A key grants full data plane access to every deployment on the account, cannot be scoped to a caller and tends to end up in configuration files, pipelines and chat messages.

## Decision

1. Every Cognitive Services account sets `local_auth_enabled = false`, so keys cannot be used even if someone lists them.
2. The gateway calls Azure OpenAI as a user-assigned identity with `Cognitive Services OpenAI User` on each account.
3. Workloads call the gateway with an Entra ID token for the gateway audience, obtained through `DefaultAzureCredential`.
4. The APIM subscription key is kept as a quota and attribution handle, not as the authentication factor, and is stored in Key Vault.
5. CI authenticates to Azure with OIDC federation. No client secret exists.

## Consequences

1. A leaked subscription key alone does not grant access.
2. Revoking a workload means removing its identity, with no key rotation across teams.
3. Local development needs `az login` and a role on the gateway audience, which is a small onboarding step.
4. Some third party tools that only support keys cannot call the gateway directly and need a thin adapter.
