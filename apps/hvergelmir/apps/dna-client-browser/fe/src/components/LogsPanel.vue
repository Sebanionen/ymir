<script setup lang="ts">
// Logs from every app and every level by default, newest last. Pills narrow apps and levels (each starts selected);
// a line with a payload opens it as highlighted JSON in a modal.
import { computed, onMounted, ref, watch } from "vue";
import { Braces, RefreshCw } from "@lucide/vue";
import type { LogLine } from "@dna/sdk";
import { api, attempt } from "../client/store";
import JsonDialog from "./JsonDialog.vue";
import LoadingRows from "./LoadingRows.vue";

const props = defineProps<{ sweepId?: number; conversationId?: number }>();
const APPS = ["api", "cron", "cli", "hub"] as const;
const LEVELS = ["debug", "info", "warn", "error"] as const;
const apps = ref<string[]>([...APPS]);
const levels = ref<string[]>([...LEVELS]);
const lines = ref<LogLine[]>([]);
const loading = ref(true);
const open = ref<LogLine>();

const load = async () => {
  loading.value = true;
  lines.value =
    (await attempt(() =>
      api.logs({
        apps: apps.value.join(","),
        levels: levels.value.join(","),
        sweepId: props.sweepId,
        conversationId: props.conversationId,
        limit: 400,
      }),
    )) ?? [];
  loading.value = false;
};
onMounted(load);
watch([apps, levels, () => props.sweepId, () => props.conversationId], load, { deep: true });

/** Toggle a pill; the last selected one stays on so the list never filters to nothing. */
function toggle(which: "apps" | "levels", value: string) {
  const list = which === "apps" ? apps : levels;
  const on = list.value.includes(value);
  if (on && list.value.length === 1) return;
  list.value = on ? list.value.filter((x) => x !== value) : [...list.value, value];
}
const payload = (l: LogLine) => {
  const { ts: _t, level: _l, app: _a, event: _e, device: _d, ...more } = l;
  return more;
};
const hasPayload = (l: LogLine) => Object.keys(payload(l)).length > 0;
const counts = computed(() => {
  const out: Record<string, number> = {};
  for (const l of lines.value) out[l.level] = (out[l.level] ?? 0) + 1;
  return out;
});
</script>

<template>
  <div class="logs" data-cap="logs">
    <div class="logs-head">
      <div class="pill-group" role="group" aria-label="Apps">
        <button
          v-for="a in APPS"
          :key="a"
          class="pill"
          :class="{ on: apps.includes(a) }"
          :aria-pressed="apps.includes(a)"
          @click="toggle('apps', a)"
        >
          {{ a }}
        </button>
      </div>
      <div class="pill-group" role="group" aria-label="Levels">
        <button
          v-for="l in LEVELS"
          :key="l"
          class="pill"
          :class="[l, { on: levels.includes(l) }]"
          :aria-pressed="levels.includes(l)"
          @click="toggle('levels', l)"
        >
          {{ l }}<small v-if="counts[l]">{{ counts[l] }}</small>
        </button>
      </div>
      <span v-if="sweepId" class="muted">sweep {{ sweepId }}</span
      ><span v-if="conversationId" class="muted">conversation {{ conversationId }}</span>
      <span class="grow" />
      <button class="icon-button small" aria-label="Refresh logs" @click="load">
        <RefreshCw :size="13" />
      </button>
    </div>
    <div class="log-lines">
      <div v-for="(l, i) in lines" :key="i" class="log-line" :class="l.level" :data-event="l.event">
        <span class="mono muted">{{ l.ts.slice(11, 19) }}</span>
        <span class="lvl">{{ l.level }}</span>
        <span class="log-app">{{ l.app }}</span>
        <span class="log-event">{{ l.event }}</span>
        <span class="grow" />
        <button
          v-if="hasPayload(l)"
          class="icon-button small"
          :aria-label="`Show the ${l.event} payload`"
          title="Payload"
          @click="open = l"
        >
          <Braces :size="13" />
        </button>
      </div>
      <LoadingRows v-if="loading && !lines.length" kind="lines" :count="8" label="Loading logs" />
      <p v-else-if="!lines.length" class="muted">No log lines match.</p>
    </div>
    <JsonDialog
      v-if="open"
      :title="`${open.app} ${open.event} at ${open.ts.slice(11, 19)}`"
      :value="payload(open)"
      @close="open = undefined"
    />
  </div>
</template>
