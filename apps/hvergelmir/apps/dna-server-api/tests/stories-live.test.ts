// Small labeled smoke set. This is not a calibrated accuracy estimate. Run only with JEV_LIVE=1.
import assert from "node:assert/strict";
import { test } from "node:test";
import { join } from "node:path";
import { JevClient } from "@dna/jev";
import type { Logger } from "@dna/sdk/node";
import { Bus } from "../src/events.ts";
import { Judge } from "../src/news/hfs.ts";
import { StoryMatcher } from "../src/news/stories.ts";
import { PROMPTS_DIR, tempStore } from "./helpers.ts";

test(
  "live story decisions: repeated coverage, new evidence, correction, new event, unrelated and thin evidence",
  { skip: process.env.JEV_LIVE !== "1" },
  async () => {
    const { store, cleanup } = tempStore();
    try {
      const client = new JevClient();
      const judge = new Judge({
        store,
        dir: join(PROMPTS_DIR, "jev"),
        decide: (s, q, o) => client.systemOne(s, q, o),
      });
      const matcher = new StoryMatcher({
        store,
        judge,
        bus: new Bus(),
        log: { warn() {}, info() {} } as unknown as Logger,
        http: {
          get: async () => {
            throw new Error("use supplied evidence only");
          },
          postJson: async () => {
            throw new Error("offline");
          },
        },
      });
      const base =
        "Anthropic announced Scion, its internal source control system, on October 10. The announcement says it replaced Git for internal development because daily code merges grew from about 2,500 in May to over 30,000. Scion is used inside Anthropic only. The announcement does not offer a public download or open source repository. It describes the adoption and the merge figures but gives no details of the storage architecture. These figures are attributed to Anthropic, not independently measured by this publication.";
      const existing = store.news.upsertItem({
        url: "https://example.org/announcement",
        title: "Anthropic introduces internal source control Scion",
        excerpt: base,
      }).item;
      const cases = [
        {
          name: "reworded coverage",
          expected: "duplicate",
          text: "According to Anthropic's October 10 announcement, the company now uses an internal system named Scion in place of Git. It says daily merges went from about 2,500 in May to more than 30,000. The system remains internal, with no public repository or download. The company gave no storage architecture details. This article repeats that announcement and contains no additional reporting.",
        },
        {
          name: "later publication of the same announcement",
          expected: "duplicate",
          text:
            base +
            " This article was published on October 13 and summarizes the October 10 announcement without further developments.",
        },
        {
          name: "architecture evidence",
          expected: "evidence",
          text:
            base +
            " In an accompanying technical document about the same system and adoption, Anthropic explains that Scion stores immutable content-addressed objects in a distributed object store. The document provides a storage diagram and benchmark methodology. This explains the previously announced system, with no new launch or availability change.",
        },
        {
          name: "conflicting report",
          expected: "evidence",
          text: "This report concerns Anthropic's October 10 Scion announcement. It quotes an internal document saying daily merges were 25,000 rather than the previously reported over 30,000. The discrepancy has not been resolved and there is no official correction. The system is still internal. This is additional conflicting evidence about the same adoption, not a new release.",
        },
        {
          name: "public release",
          expected: "development",
          text: "On October 13 Anthropic released Scion publicly under an open source license and published a download and installation guide. This is a change from the October 10 announcement, when Scion was internal only. The public release is version 1.0 and external developers can now install it. This article reports the new public availability and links to the release repository.",
        },
        {
          name: "same company different event",
          expected: "different",
          text: "Anthropic announced a new Claude voice interface on October 13. It supports spoken conversations, voice selection and transcription. It is unrelated to the Scion source control announcement. The release concerns the consumer Claude application and does not change Scion or code merge infrastructure.",
        },
        {
          name: "insufficient teaser",
          expected: "uncertain",
          text: "Scion changes everything. Subscribe to read what happened next.",
        },
      ];
      const failures: string[] = [];
      for (const c of cases) {
        const item = store.news.upsertItem({
          url: `https://example.org/${encodeURIComponent(c.name)}`,
          title:
            c.name === "same company different event"
              ? "Anthropic introduces Claude voice"
              : "Anthropic Scion news",
          excerpt: c.text,
        }).item;
        const result = await matcher.compare(item, existing);
        console.log(JSON.stringify({ case: c.name, expected: c.expected, ...result }));
        if (result.action !== c.expected)
          failures.push(`${c.name}: ${result.action}, expected ${c.expected}`);
      }
      console.log(
        JSON.stringify(
          store.db.prepare("SELECT count(*) calls, sum(cost_usd) costUsd FROM jev_calls").get(),
        ),
      );
      assert.deepEqual(failures, []);
    } finally {
      cleanup();
    }
  },
);
