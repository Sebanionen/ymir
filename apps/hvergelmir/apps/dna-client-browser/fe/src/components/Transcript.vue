<script setup lang="ts">
// The agent's transcript: your messages on the right, the agent on the left, every tool call as a row, scheduled
// sweeps as chips with their progress lines, thinking collapsed, and open taste questions inline at the bottom.
import { computed } from "vue";
import { Activity, Brain, CircleHelp, Clock, Minimize2, Telescope } from "@lucide/vue";
import type { TranscriptItem } from "@dna/sdk";
import { agentView, feedState } from "../client/store";
import { clean, markdown } from "../client/text";
import BottomPane from "./BottomPane.vue";
import TasteQuestionCard from "./TasteQuestionCard.vue";
import ToolCallRow from "./ToolCallRow.vue";

const items = computed(() => agentView.value.items);
const questions = computed(() => feedState.value.questions);
const count = computed(
  () => items.value.length + questions.value.length + (agentView.value.generating ? 1 : 0),
);

function special(
  item: TranscriptItem & { kind: "user" },
): { kind: "sweep" | "taste" | "deep"; label: string } | undefined {
  const sweep = item.text.match(/Run scheduled sweep (\d+)/);
  if (sweep) return { kind: "sweep", label: `Scheduled sweep ${sweep[1]}` };
  const deep = item.text.match(/Deep research #(\d+): researcher (\d+) of (\d+) reported/);
  if (deep)
    return {
      kind: "deep",
      label: `Deep research ${deep[1]}: researcher ${deep[2]} of ${deep[3]} reported`,
    };
  if (/The reader answered your taste question/.test(item.text))
    return { kind: "taste", label: "You answered a taste question" };
  return undefined;
}
const progress = (item: TranscriptItem & { kind: "event" }) =>
  (item.data as { phase?: string } | undefined)?.phase;
</script>

<template>
  <BottomPane :count="count" label="Agent transcript">
    <div class="transcript" data-cap="chat.watch" data-testid="chat">
      <p v-if="!items.length" class="empty">
        This agent did not wait for me to work. It works for me, then waits, then keeps working.
      </p>
      <template v-for="item in items" :key="`${item.kind}:${item.id}`">
        <template v-if="item.kind === 'user'">
          <div v-if="special(item)" class="chip-line" :data-chip="special(item)!.kind">
            <span class="chip"
              ><Clock v-if="special(item)!.kind === 'sweep'" :size="14" /><Telescope
                v-else-if="special(item)!.kind === 'deep'"
                :size="14"
              /><CircleHelp v-else :size="14" />{{ special(item)!.label }}</span
            >
          </div>
          <div v-else class="msg user" data-role="user">
            <div class="bubble">{{ clean(item.text) }}</div>
          </div>
        </template>
        <div
          v-else-if="item.kind === 'assistant'"
          class="msg agent"
          data-role="agent"
          :class="{ streaming: item.streaming }"
        >
          <template v-for="(block, i) in item.blocks" :key="i">
            <details v-if="block.type === 'thinking'" class="thinking">
              <summary><Brain :size="13" />Thinking</summary>
              <p>{{ clean(block.text) }}</p>
            </details>
            <div
              v-else-if="block.type === 'text'"
              class="bubble markdown"
              v-html="markdown(block.text)"
            />
            <ToolCallRow v-else :call="block.call" />
          </template>
          <p v-if="item.error" class="msg-error">{{ clean(item.error) }}</p>
        </div>
        <ToolCallRow v-else-if="item.kind === 'tool'" :call="item.call" />
        <div v-else-if="item.kind === 'tool-result'" class="event-line">
          <Activity :size="13" />{{ item.name }} {{ item.isError ? "failed" : "finished" }}
        </div>
        <div
          v-else-if="item.kind === 'event'"
          class="event-line"
          :class="{ progress: item.entryKind === 'dna.sweep-progress' }"
          :data-entry="item.entryKind"
        >
          <Minimize2 v-if="item.entryKind === 'pi.compaction'" :size="13" /><Activity
            v-else
            :size="13"
          />
          <span v-if="progress(item)" class="phase">{{ progress(item) }}</span
          >{{ clean(item.text) }}
        </div>
      </template>
      <TasteQuestionCard v-for="q in questions" :key="`q${q.id}`" :question="q" />
    </div>
  </BottomPane>
</template>
