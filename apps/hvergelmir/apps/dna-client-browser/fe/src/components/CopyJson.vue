<script setup lang="ts">
import { Copy } from "@lucide/vue";
import { notify } from "../client/store";

const props = defineProps<{ value: unknown; label?: string }>();
async function copy() {
  await navigator.clipboard?.writeText(JSON.stringify(props.value, null, 2)).catch(() => undefined);
  notify("Copied JSON");
}
</script>
<template>
  <button
    class="icon-button small copy"
    :aria-label="`Copy ${label ?? 'JSON'}`"
    title="Copy JSON"
    @click.stop="copy"
  >
    <Copy :size="13" />
  </button>
</template>
