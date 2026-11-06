#!/usr/bin/env node
// The dna-tui command: register tsx, then run the TypeScript entry point.
import { register } from "tsx/esm/api";

register();
await import("../src/main.ts");
