<script setup lang="ts">
// Read-only JSON with syntax colors. Values are escaped before highlighting, so v-html only ever adds spans.
import { computed } from "vue";
import { highlightJson } from "../client/json";

const props = defineProps<{ value: unknown }>();
const html = computed(() => highlightJson(props.value));
</script>

<template>
  <!-- eslint-disable-next-line vue/no-v-html -->
  <pre class="json-view" v-html="html" />
</template>
