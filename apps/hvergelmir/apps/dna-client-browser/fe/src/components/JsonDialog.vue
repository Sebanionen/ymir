<script setup lang="ts">
// A JSON payload in a modal: highlighted, with copy. Esc or the backdrop closes it.
import { onBeforeUnmount, onMounted } from "vue";
import { X } from "@lucide/vue";
import CopyJson from "./CopyJson.vue";
import JsonView from "./JsonView.vue";

defineProps<{ title: string; value: unknown }>();
const emit = defineEmits<{ close: [] }>();
// Capture phase, and stop it there: Esc closes this modal only, not the view underneath.
const onKey = (e: KeyboardEvent) => {
  if (e.key !== "Escape") return;
  e.stopPropagation();
  emit("close");
};
onMounted(() => window.addEventListener("keydown", onKey, true));
onBeforeUnmount(() => window.removeEventListener("keydown", onKey, true));
</script>

<template>
  <div class="modal-backdrop" @click.self="emit('close')">
    <section class="modal json-modal" role="dialog" aria-modal="true" :aria-label="title">
      <header>
        <strong class="mono">{{ title }}</strong>
        <span class="grow" />
        <CopyJson :value="value" label="payload" />
        <button class="icon-button" aria-label="Close" @click="emit('close')">
          <X :size="18" />
        </button>
      </header>
      <JsonView :value="value" />
    </section>
  </div>
</template>
