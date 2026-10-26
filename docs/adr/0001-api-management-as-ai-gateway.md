# ADR 0001. API Management as the AI gateway

| Status | Date |
| --- | --- |
| Accepted | 2026-03-02 |

## Context

Several product teams want to use Azure OpenAI. Letting each team create its own account multiplies keys, network exposure, quota requests and invoices that nobody can attribute. We need one controlled entry point that authenticates callers, shares capacity fairly, survives regional throttling and measures usage per team.

## Options

| Option | For | Against |
| --- | --- | --- |
| Direct access to Azure OpenAI per team | Simple to start | Keys or broad roles per team, no cross team quota, no single audit point |
| Custom proxy service | Full control | We would own auth, retries, metrics and scaling code forever |
| Azure API Management with the GenAI policies | Native token limits, token metrics, managed identity auth, backend pools and circuit breakers | APIM cost, Internal mode needs a Developer or Premium SKU |

## Decision

Use Azure API Management as the only path to the models, with the built in `azure-openai-token-limit`, `azure-openai-emit-token-metric` and `authentication-managed-identity` policies and a backend pool across regions.

## Consequences

1. Teams integrate once with a stable URL and contract, whatever happens to deployments behind it.
2. Quotas and showback come from configuration, not code.
3. APIM becomes a critical dependency and needs Premium with zones in production.
4. Pool backends and the diagnostic metrics switch need `azapi` until `azurerm` supports them.
