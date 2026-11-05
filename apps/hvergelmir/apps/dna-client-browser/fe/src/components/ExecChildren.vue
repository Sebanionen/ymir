<script setup lang="ts">
// What one run did, for the Executions tree: its tool calls in order, then its subagent runs, each of which opens
// the same way. Clicking a tool call or a run shows it on the right.
import { onMounted, ref } from "vue";
import { Bot, ChevronDown, ChevronRight, Wrench } from "@lucide/vue";
import { ms, type RunDetail } from "@dna/sdk";
import { go, route } from "../client/route";
import { api, attempt } from "../client/store";

const props = defineProps<{ runId: number }>();
const run = ref<RunDetail>();
const open = ref(new Set<number>());
onMounted(async () => (run.value = await attempt(() => api.run(props.runId))));
const toggle = (id: number) => {
  const next = new Set(open.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  open.value = next;
};
const on = (kind: "tool" | "run", id: number) =>
  route.value.view === "executions" && route.value.kind === kind && route.value.id === id;
</script>

<template>
  <ul class="exec-children">
    <li v-if="!run" class="muted exec-leaf">Loading</li>
    <li v-for="t in run?.toolCallRows ?? []" :key="`t${t.id}`">
      <button
        class="exec-leaf"
        :class="{ on: on('tool', t.id), bad: t.isError }"
        :data-exec-tool="t.toolName"
        @click="go(`/executions/tool/${t.id}`)"
      >
        <Wrench :size="12" /><span class="mono">{{ t.toolName }}</span
        ><span class="muted right">{{ ms(t.durationMs) }}</span>
      </button>
    </li>
    <li v-for="c in run?.children ?? []" :key="`r${c.runEntryId}`">
      <div class="exec-leaf-row">
        <button
          class="twisty"
          :aria-label="`${open.has(c.runEntryId) ? 'Close' : 'Open'} ${c.agent} run ${c.runEntryId}`"
          @click="toggle(c.runEntryId)"
        >
          <component :is="open.has(c.runEntryId) ? ChevronDown : ChevronRight" :size="13" />
        </button>
        <button
          class="exec-leaf"
          :class="{ on: on('run', c.runEntryId) }"
          @click="go(`/executions/run/${c.runEntryId}`)"
        >
          <Bot :size="12" /><span>{{ c.agent }}</span
          ><span class="muted">{{ c.toolCalls }} tools</span>
        </button>
      </div>
      <ExecChildren v-if="open.has(c.runEntryId)" :run-id="c.runEntryId" />
    </li>
    <li v-if="run && !run.toolCallRows.length && !run.children.length" class="muted exec-leaf">
      No tool calls
    </li>
  </ul>
</template>
