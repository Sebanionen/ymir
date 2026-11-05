import assert from "node:assert/strict";
import { test } from "node:test";
import { checkComponent, componentCatalog } from "../src/news/components.ts";

const hfs = (hype: number, facts: number, signal: number) => ({
  hype,
  facts,
  signal,
  primary: "signal" as const,
  labels: [],
  ranked: [],
  suspectCombo: false,
});

test("component rules refuse with the alternatives", () => {
  assert.match(
    checkComponent({
      component: "hype_watch",
      props: { title: "x", reality_check: "y" },
      hfs: hfs(12, 80, 40),
    })!,
    /hype score of 40 or more, and jev scored this item 12\. Use brief or fact_check/,
  );
  assert.equal(
    checkComponent({
      component: "hype_watch",
      props: { title: "x", reality_check: "y" },
      hfs: hfs(70, 20, 10),
    }),
    undefined,
  );
  assert.match(
    checkComponent({
      component: "signal_alert",
      props: { title: "x", why: "y" },
      hfs: hfs(0, 80, 90),
    })!,
    /needs action in props/,
  );
  assert.match(
    checkComponent({ component: "signal_alert", props: { title: "x", action: "a", why: "y" } })!,
    /Call jev_classify/,
  );
  assert.match(
    checkComponent({ component: "headline", props: { title: "x", dek: "y" }, attention: 40 })!,
    /attention 70/,
  );
  assert.match(
    checkComponent({
      component: "thread_pulse",
      props: { title: "x", takes: ["a"] },
      hasDiscussion: false,
    })!,
    /discussion link/,
  );
  assert.equal(
    checkComponent({ component: "brief", props: { title: "x", summary: "y" } }),
    undefined,
  );
  assert.match(
    componentCatalog(),
    /\| signal_alert \| something to act on now \| title, action, why \| signal 60 or more \|/,
  );
});
