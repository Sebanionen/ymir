import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { Agent } from 'node:http';

// Ports are environment-driven so a deployment can avoid collisions with other
// services on a shared host; the historic defaults are unchanged. The gate API
// reads the same names (scripts/start.sh passes them through).
const SPA_PORT = Number(process.env.HLIDSKJALF_PORT ?? 3888);
const API_PORT = Number(process.env.HLIDSKJALF_API_PORT ?? 3889);
// Bind host: 127.0.0.1 for bare local dev. Inside a container the published port
// is forwarded to the container's interface, so a deployment sets this to 0.0.0.0
// (and pins the host-side publish to loopback where the surface must stay private).
const SPA_HOST = process.env.HLIDSKJALF_HOST ?? '127.0.0.1';
const API_ORIGIN = `http://127.0.0.1:${API_PORT}`;
// http-proxy otherwise forces Connection: close. On native Windows this reset
// real audio uploads; retain the origin connection rather than retrying audio.
const API_PROXY = { target: API_ORIGIN, agent: new Agent({ keepAlive: true }) };

export default defineConfig({
  plugins: [react()],
  server: {
    host: SPA_HOST,
    port: SPA_PORT,
    strictPort: false,
    // Tunnelled hostnames (Cloudflare -> gate API -> vite) must be allowed or
    // Vite blocks them with "Blocked request. This host … is not allowed."
    // Keep hostnames in env (private); default to allowing any host on this
    // localhost-bound dev server rather than hardcoding an operator domain.
    allowedHosts: (() => {
      const list = (process.env.YMIR_ALLOWED_HOSTS ?? '').split(',').map((h) => h.trim()).filter(Boolean);
      return list.length ? list : true;
    })(),
    proxy: {
      // The local gate API (apps/hlidskjalf/server) reading the Brokk runtime.
      '/api': API_PROXY,
    },
    fs: {
      // Allow importing the canonical design tokens from midgard/.
      allow: ['..', '../..', '../../..'],
    },
  },
  preview: {
    host: SPA_HOST,
    port: SPA_PORT,
    proxy: {
      '/api': API_PROXY,
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
});
