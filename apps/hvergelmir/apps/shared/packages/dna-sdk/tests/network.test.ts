import assert from "node:assert/strict";
import { test } from "node:test";
import { hubPort, parseNetwork } from "../src/node/network.ts";

const yaml = (miniPort: number) => `devices:
  local: { kind: local, url: http://127.0.0.1:4850, hub_port: 4851 }
  mini: { kind: ssh, ssh: me@mini.local, service: launchd, url: http://mini.local:4850, hub_port: ${miniPort} }
  box: { kind: ssh, ssh: me@box, service: systemd, url: http://box:4850 }
`;

test("each device has its own browser hub port, 4851 without one", () => {
  const net = parseNetwork(yaml(4853));
  assert.equal(hubPort(net.devices.local), 4851);
  assert.equal(hubPort(net.devices.mini), 4853);
  assert.equal(hubPort(net.devices.box), 4851);
});

test("two devices with the same hub_port are a config error", () => {
  assert.throws(() => parseNetwork(yaml(4851)), /mini.hub_port 4851 is also local's/);
});

test("a device can serve its own UI: ssh opts in with a URL, exe-dev always serves it privately", () => {
  const net = parseNetwork(`devices:
  local: { kind: local, url: http://127.0.0.1:4850, ui: http://ignored:1 }
  mini: { kind: ssh, ssh: me@mini.local, service: launchd, url: http://mini.local:4850, ui: "http://mini.local:4851/" }
  vm: { kind: exe-dev, vm: my-vm, service: systemd, url: http://127.0.0.1:4852 }
`);
  assert.equal(net.devices.local.ui, undefined, "the laptop serves its UI with a laptop hub");
  assert.deepEqual(net.devices.mini.ui, { url: "http://mini.local:4851", port: 4851 });
  assert.deepEqual(net.devices.vm.ui, { url: "https://my-vm.exe.xyz", port: 4851 });
});
