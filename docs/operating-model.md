# Operating model

The platform team runs the gateway. Product teams consume it. This page describes how a team gets access, how capacity is shared, and how cost is shown back.

## Roles

| Role | Owns |
| --- | --- |
| Platform team | Terraform stack, policies, model deployments, regional capacity, incident response on the gateway |
| Product team | Its workload, its prompts, its usage inside the quota it was granted |
| Security | Threat model review, Content Safety configuration, access reviews |
| FinOps | Showback reports and quota reviews with each team |

## Onboarding a team

1. The team opens a pull request adding an entry to `teams` in `infra/terraform/env/<env>.tfvars` with a display name, tokens per minute and a monthly token quota.
2. The platform team reviews the numbers against regional capacity and merges.
3. Terraform creates the product, attaches the API, renders the token limit policy and creates the subscription.
4. The subscription key is stored in Key Vault, and the team workload identity gets `Key Vault Secrets User`.
5. The team registers its workload identity as a caller of the gateway audience in Entra ID.

No team ever receives an Azure OpenAI key or a role on an Azure OpenAI account.

## Quotas

Two numbers per team, both measured in tokens.

| Limit | Policy attribute | Behaviour when exceeded |
| --- | --- | --- |
| Tokens per minute | `tokens-per-minute` | 429 with `Retry-After`. Smooths bursts so one team cannot starve another |
| Token quota | `token-quota` and `token-quota-period` | 403 until the period resets. Caps spend per team |

As a rule of thumb, the sum of all teams' tokens per minute can exceed the deployed capacity, because teams rarely peak together. Keep it under about 1.5 times the pool capacity and review monthly with the metrics below.

## Showback

`azure-openai-emit-token-metric` writes three custom metrics per call (`Prompt Tokens`, `Completion Tokens`, `Total Tokens`) with the product, subscription, API, operation and deployment as dimensions. They land in the `AppMetrics` table of the Log Analytics workspace.

### Tokens per team and deployment, last 30 days

```kusto
AppMetrics
| where TimeGenerated > ago(30d)
| where Name in ("Prompt Tokens", "Completion Tokens")
| extend team = tostring(Properties["Product ID"]), deployment = tostring(Properties["Deployment"])
| summarize tokens = sum(Sum) by team, deployment, Name
| evaluate pivot(Name, sum(tokens))
| order by team asc
```

### Estimated cost this month

Unit prices come from your own rate card. The zeros below are placeholders.

```kusto
let price_per_1k = datatable(deployment: string, prompt: real, completion: real) [
    "gpt-4o-mini", 0.0, 0.0,
    "text-embedding-3-small", 0.0, 0.0
];
AppMetrics
| where TimeGenerated > startofmonth(now())
| where Name in ("Prompt Tokens", "Completion Tokens")
| extend team = tostring(Properties["Product ID"]), deployment = tostring(Properties["Deployment"])
| summarize prompt_tokens = sumif(Sum, Name == "Prompt Tokens"), completion_tokens = sumif(Sum, Name == "Completion Tokens") by team, deployment
| join kind=leftouter price_per_1k on deployment
| extend cost = prompt_tokens / 1000.0 * prompt + completion_tokens / 1000.0 * completion
| summarize cost = sum(cost), tokens = sum(prompt_tokens + completion_tokens) by team
| order by cost desc
```

### Throttling pressure per team

A team that is throttled every day has a quota that is too tight.

```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(7d)
| where ResponseCode == 429
| summarize throttled = count() by ProductId, bin(TimeGenerated, 1h)
| render timechart
```

## Runbook entries

| Signal | First check | Usual fix |
| --- | --- | --- |
| Spike of 429 for one team | Its tokens per minute against its traffic | Raise the limit in tfvars, or ask the team to batch |
| Spike of 429 for all teams | Regional capacity of the deployments | Add capacity or a pool member in another region |
| 401 from the gateway | Token audience and caller registration | Fix the scope (`<audience>/.default`) or the app registration |
| 502 from the gateway | Circuit breaker state, backend health | Check the private endpoint and DNS resolution from the APIM subnet |

## Reviews

| Cadence | Review | Input |
| --- | --- | --- |
| Monthly | Quota per team | Showback query, throttling query |
| Quarterly | Access | APIM subscriptions, Key Vault role assignments |
| Quarterly | Threat model | `docs/threat-model.md` residual risks |
| On model release | Deployment versions | `model_deployments`, with `version_upgrade_option = NoAutoUpgrade` |
