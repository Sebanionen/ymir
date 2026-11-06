<script setup lang="ts">
import { computed, ref } from "vue";
import { Check, X } from "@lucide/vue";
import type { ModelInfo } from "@dna/sdk";
import { agentState, api, attempt, feed, info, notify, ui } from "../client/store";

const DEFAULT_MODEL = "anthropic/claude-haiku-5.5";
const search = ref("");
const models = computed(() => info.value?.models ?? []);
const filtered = computed(() =>
  models.value.filter((m) =>
    `${m.name} ${m.id} ${m.tier}`.toLowerCase().includes(search.value.toLowerCase()),
  ),
);
const current = computed(() => agentState.value?.model);
const close = () => (ui.models = false);

async function choose(m: ModelInfo) {
  const state = await attempt(() => api.configure({ model: m.id }));
  if (!state) return;
  feed.apply({ type: "agent.state", state });
  notify(`${m.name} from the next turn`);
  close();
}
</script>

<template>
  <div class="modal-backdrop" @click.self="close">
    <section class="modal model-modal" role="dialog" aria-modal="true" aria-label="Choose a model">
      <header>
        <h2>Choose a model</h2>
        <button class="icon-button" aria-label="Close the model picker" @click="close">
          <X :size="18" />
        </button>
      </header>
      <input v-model="search" placeholder="Search models or tiers" aria-label="Search models" />
      <div class="model-list">
        <button
          v-for="m in filtered"
          :key="m.id"
          class="model-row"
          :class="{ selected: m.id === current }"
          :data-model="m.id"
          @click="choose(m)"
        >
          <img :src="`/icons/${m.icon}`" alt="" />
          <div>
            <strong>{{ m.name }}</strong>
            <small
              >{{ m.tier }} tier, {{ m.provider }}, {{ Math.round(m.contextWindow / 1000) }}k
              context</small
            >
          </div>
          <span v-if="m.id === DEFAULT_MODEL" class="badge">Default</span>
          <Check v-if="m.id === current" :size="18" />
        </button>
      </div>
    </section>
  </div>
</template>
