import assert from "node:assert/strict";
import { test } from "node:test";
import { guard } from "../src/guard.ts";

function run(headers: Record<string, string>, method = "GET", json = true) {
  let status = 200;
  let next = false;
  const req = { headers, method, is: () => json } as never;
  const res = { status: (s: number) => ((status = s), { json: () => undefined }) } as never;
  guard(new Set(["localhost:4851", "mini.local:4851", "my-vm.exe.xyz"]))(req, res, () => {
    next = true;
  });
  return next ? 200 : status;
}

test("a hosted hub answers its own hosts and refuses the rest", () => {
  assert.equal(run({ host: "mini.local:4851" }), 200);
  assert.equal(run({ host: "evil.example:4851" }), 421, "DNS rebinding");
});

test("the origin must be a served host, even when a proxy rewrites Host", () => {
  assert.equal(run({ host: "localhost:4851", origin: "https://my-vm.exe.xyz" }, "POST"), 200);
  assert.equal(run({ host: "mini.local:4851", origin: "https://evil.example" }, "POST"), 403);
  assert.equal(
    run({ host: "mini.local:4851", origin: "http://mini.local:4851" }, "POST", false),
    415,
  );
});
