<script setup lang="ts">
// The feed search box: after a pause in typing it runs the same search as the agent's open_tab, in a search tab.
// Typing edits the active search tab. Enter searches now, Escape clears.
import { ref, watch } from "vue";
import { Search } from "@lucide/vue";
import { layout, searchFor, tabKey } from "../client/layout";

const text = ref("");
const input = ref<HTMLInputElement>();
let timer: ReturnType<typeof setTimeout> | undefined;
// Show the active search tab's words, unless the reader is typing.
watch(
  () => layout.tab,
  () => {
    if (document.activeElement === input.value) return;
    const t = layout.tabs.find((x) => tabKey(x) === layout.tab);
    text.value = t?.kind === "search" ? t.value : "";
  },
  { immediate: true },
);
function go() {
  clearTimeout(timer);
  const value = text.value.trim();
  if (value) searchFor(value);
}
function typed() {
  clearTimeout(timer);
  timer = setTimeout(go, 350);
}
function clear() {
  clearTimeout(timer);
  text.value = "";
  input.value?.blur();
}
</script>

<template>
  <form class="feed-search" role="search" data-cap="feed.search" @submit.prevent="go">
    <Search :size="14" />
    <input
      ref="input"
      v-model="text"
      type="search"
      placeholder="Search news"
      aria-label="Search news"
      @input="typed"
      @keydown.esc="clear"
    />
  </form>
</template>
