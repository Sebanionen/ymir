<script setup lang="ts">
// One tool call in light detail: status, name, short args, duration, context tokens and cost. Click opens it in
// the executions view.
import { computed } from "vue";
import { Circle, CircleCheck, CircleX, LoaderCircle, Users } from "@lucide/vue";
import { k, ms, usd, type ToolCallView } from "@dna/sdk";
import { go } from "../client/route";
import { toolRows } from "../client/store";
import { shortArgs } from "../client/text";

const props = defineProps<{ call: ToolCallView }>();
const row = computed(() => toolRows.value.get(props.call.callId));
const cost = computed(() => (row.value ? row.value.toolCostUsd + (row.value.paidUsd ?? 0) : 0));
function open() {
  if (row.value) go(`/executions/tool/${row.value.id}`);
}
</script>

<template>
  <button
    class="tool-row"
    :class="call.status"
    data-cap="tool.read"
    :data-tool="call.name"
    :data-status="call.status"
    :disabled="!row"
    :title="row ? 'Open in executions' : 'Telemetry arrives when the call ends'"
    @click="open"
  >
    <LoaderCircle v-if="call.status === 'running'" :size="14" class="spin" />
    <CircleCheck v-else-if="call.status === 'done'" :size="14" />
    <CircleX v-else-if="call.status === 'error'" :size="14" />
    <Circle v-else :size="14" />
    <span class="tool-name">{{ call.name }}</span>
    <span class="tool-args">{{ shortArgs(call.args) }}</span>
    <span v-if="row?.children?.length" class="tool-sub" title="Subagents"
      ><Users :size="12" />{{ row.children.length }}</span
    >
    <span v-if="row" class="tool-stats">
      <span data-stat="duration">{{ ms(row.durationMs) }}</span>
      <span data-stat="context">{{ k(row.contextTokens ?? 0) }} ctx</span>
      <span data-stat="cost">{{ usd(cost) }}</span>
    </span>
  </button>
</template>
