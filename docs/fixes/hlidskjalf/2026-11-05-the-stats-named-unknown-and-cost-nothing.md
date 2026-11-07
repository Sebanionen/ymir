# The stats named 92% of the work "unknown" and costed it at zero

**2026-11-05 · component: hlidskjalf · `bin/desktop/hlidskjalf-usage.sh` · `apps/hlidskjalf/src/gates/Stats.tsx`**

His word, with the panel in front of him: *"are hildskjalf showing how many tokens i have uses from opencode and pi??"* and then
*"all needs to be seen and knwon"*.

## What the panel said, and what was true

```
before[4]{row,panel,truth}:
  "pi · 46,087 messages","model `unknown`, 245M tokens","pi records the model on every message: `{\"type\":\"message\",\"message\":{\"model\":\"deepseek-v4.1-flash\",\"usage\":{…}}}`, 27,121 of them"
  "cost","$0.0000 everywhere","each pi message carries `usage.cost.total`; the door never read it — the 30-day figure is **$59.00**"
  "local vs online","pi counted as online, local 0.0%","the id `deepseek-v4.1-flash` matched no marker; the registry (`~/.pi/agent/models.json`) says which providers are ours"
  "cache-hit","98.3% in one line, 0.0% in another","two different formulas in one panel"
```

## The three faults, in the script

1. **The model was looked for at the top level.** Pi nests it beside the usage. The reader checked `d["modelID"]`/`d["model"]`
   and never `d["message"]["model"]`, so almost everything fell to `unknown`.
2. **The cost was never read at all** — `usage.cost.total` was present on every line and no accumulator existed.
3. **Local was decided by substring luck.** `LOCAL_MARKERS` held `llama`, `ollama`, `qwen3.6-35b-a3b`; a rail-served id
   named `deepseek-v4.1-flash` failed the test. The registry is the authority, so the door now reads it
   (`providers.*` whose name contains llama/local/ollama/lmstudio, models as a LIST of `{id,…}`) and falls back to markers.

## Fixed, measured on the same 30 days

```
after[4]{row,value}:
  "pi models attributed","27,121 · deepseek-v4.1-flash ($50.46) · 3,004 · deepseek-v4-flash ($7.04) · 9,744 · space-bunny-free · 25 unknown"
  "total cost","$59.00 (was $0.0000)"
  "local vs online","local 3,361 calls / 6.0M tokens · online 45,083 calls / 259.0M tokens (was local 0.0%)"
  "cache-hit","one formula: cache_read ÷ (input + cache_read) = 98.3%"
```

## Also changed

`Stats.tsx` used `stats?.cache_hit_ratio` (the smithy's runs) for the "Cache-hit ratio" tile while the header used the harness
aggregate — hence 98.3% beside 0.0%. Both now prefer the harness aggregate and fall back to the smithy's.

## Still owed

The `unknown` row (25 messages) is pi lines that genuinely carry no model — a resumed or edited session. It is honest, and it
should be a named gap rather than a silent bucket: the next change labels it `unattributed`.

## CHANGE LOG

- **2026-11-05** — model attribution, cost, and local/online fixed in the usage door; one cache formula in the panel (Hœnir).
