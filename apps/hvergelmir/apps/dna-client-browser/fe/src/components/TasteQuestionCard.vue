<script setup lang="ts">
// The agent asks how to read an item. Pick the labels that fit, or none, and the answer goes back to the agent.
import { computed, ref } from "vue";
import { BadgeCheck, CircleHelp, Megaphone, Send, Zap } from "@lucide/vue";
import { HFS_CATEGORIES, type HfsCategory, type TasteQuestion } from "@dna/sdk";
import { api, attempt, feed, feedState, notify } from "../client/store";
import { clean } from "../client/text";

const props = defineProps<{ question: TasteQuestion }>();
const ICONS = { hype: Megaphone, facts: BadgeCheck, signal: Zap };
const NAMES: Record<HfsCategory, string> = { hype: "Hype", facts: "Facts", signal: "Signal" };
const picked = ref<HfsCategory[]>([]);
const sending = ref(false);
const card = computed(() => feedState.value.news.find((c) => c.id === props.question.cardId));
const toggle = (c: HfsCategory) =>
  (picked.value = picked.value.includes(c)
    ? picked.value.filter((x) => x !== c)
    : [...picked.value, c]);

async function answer() {
  sending.value = true;
  const q = await attempt(() => api.answer(props.question.id, picked.value));
  sending.value = false;
  if (!q) return;
  feed.apply({ type: "taste.question", question: q });
  notify("Answer sent to the agent");
}
</script>

<template>
  <div class="taste-question" data-cap="taste.answer" :data-question="question.id">
    <div class="taste-head"><CircleHelp :size="15" /><span>The agent asks</span></div>
    <p>{{ clean(question.question) }}</p>
    <p v-if="card" class="muted">Card: {{ clean(card.title) }}</p>
    <div class="taste-actions">
      <button
        v-for="c in HFS_CATEGORIES"
        :key="c"
        class="fb tag"
        :class="[c, { on: picked.includes(c) }]"
        :aria-pressed="picked.includes(c)"
        @click="toggle(c)"
      >
        <component :is="ICONS[c]" :size="13" />{{ NAMES[c] }}
      </button>
      <span class="grow" />
      <button class="button small" :disabled="sending" @click="answer">
        <Send :size="14" />{{ picked.length ? "Answer" : "None of these" }}
      </button>
    </div>
  </div>
</template>
