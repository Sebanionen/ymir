<script setup lang="ts">
// A pane that flows bottom up like a chat: newest last, pinned to the bottom, with a jump button for new items.
import { ref } from "vue";
import { ArrowDown } from "@lucide/vue";
import { usePinned } from "../client/pin";

const props = defineProps<{ count: number; label: string }>();
const scroller = ref<HTMLElement>();
const { unseen, jump } = usePinned(scroller, () => props.count);
</script>

<template>
  <div class="bottom-pane">
    <div ref="scroller" class="bottom-scroll" :aria-label="label">
      <div class="bottom-inner"><slot /></div>
    </div>
    <button
      v-if="unseen > 0"
      class="new-items"
      :aria-label="`${unseen} new, jump to the newest`"
      @click="jump"
    >
      <ArrowDown :size="15" />{{ unseen }} new
    </button>
  </div>
</template>
