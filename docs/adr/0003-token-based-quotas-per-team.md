# ADR 0003. Token based quotas, one APIM product per team

| Status | Date |
| --- | --- |
| Accepted | 2026-03-16 |

## Context

Request based rate limits do not fit language models. One request can cost ten tokens or a hundred thousand. Capacity on Azure OpenAI is sold and throttled in tokens per minute, so a fair share has to be expressed in tokens too.

## Decision

1. Each consuming team is an APIM product, declared in the `teams` variable.
2. Each product carries an `azure-openai-token-limit` policy with tokens per minute and a token quota per period, keyed on the subscription.
3. `estimate-prompt-tokens` is on, so oversize prompts are rejected before they reach the model.
4. Token metrics carry the product ID, which makes the product the unit of showback.

## Consequences

1. Limits are reviewed as code in pull requests, with the numbers visible in the diff.
2. Prompt estimation adds a small CPU cost in the gateway and can differ slightly from the model's own count.
3. Counters are per gateway region. A multi region APIM deployment shares capacity differently and needs its own sizing.
4. Teams that need guaranteed throughput move to a provisioned deployment with its own product, rather than raising shared limits.
