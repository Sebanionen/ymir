# @dna/sdk

Shared wire contract, route table, capability registry, HTTP/SSE client, state reducers and Node helpers for the Durable News Agent.

| Piece                             | What it gives you                                                                                      |
| --------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `routes.ts`                       | `ROUTES` and `routePath()`: every `/v1/*` and `/healthz` route with its method, path and auth scope    |
| `capabilities.ts`                 | `CAPABILITIES`: every reader capability mapped to routes and verified across Browser, TUI and CLI      |
| `components.ts`                   | `NEWS_COMPONENTS`: the 8 generative card component names (`headline`, `brief`, `signal_alert`, etc.)   |
| `api.ts`, `wire.ts`, `errors.ts`  | Wire types for cards, sweeps, timelines, taste, telemetry, SSE frames and `DnaError`                   |
| `client.ts`                       | `DnaClient`: typed client calling routes by `RouteId` with bearer auth and `Idempotency-Key` headers   |
| `sse.ts`                          | `readSse()` and `follow()`: SSE frame parser and auto-reconnecting stream loop with backoff            |
| `feed-model.ts`, `agent-model.ts` | `FeedModel` and `AgentModel`: shared client state reducers for the feed and live agent transcripts     |
| `format.ts`                       | `cleanText()`, `k()`, `usd()`, `ago()` and `searchQuery()`: shared formatting across all three clients |
| `@dna/sdk/node`                   | `loadRootEnv()`, `createLogger()`, `ensureTokens()`, `loadNetwork()` and `targetUrl()`                 |

## Using the client and reducers

```ts
import { AgentModel, DnaClient, FeedModel, follow } from "@dna/sdk";

const client = new DnaClient("http://127.0.0.1:4850", process.env.DNA_CLIENT_TOKEN);
const feed = new FeedModel();
const agent = new AgentModel();

const [page, sweeps, questions, state] = await Promise.all([
  client.feed({ limit: 200 }),
  client.sweeps({ limit: 20 }),
  client.questions("open"),
  client.agent(),
]);
feed.load({ cards: page.items, sweeps, questions, agent: state });

const stop = new AbortController();
void follow(
  (signal) => client.stream(signal),
  (frame) => {
    feed.apply(frame);
    agent.apply(frame);
  },
  undefined,
  stop.signal,
);
```

## Capability parity

Every non-infrastructure route in [src/routes.ts](src/routes.ts) belongs to a capability in [src/capabilities.ts](src/capabilities.ts). [tests/capabilities.test.ts](tests/capabilities.test.ts) verifies that every capability is implemented in:

- the CLI (`apps/dna-cli/src/coverage.ts`)
- the TUI (`apps/dna-client-tui/src/coverage.ts`)
- the Browser (`data-cap="<id>"` attributes across `apps/dna-client-browser/fe/src/**/*.vue`)
