<script setup lang="ts">
import { Quote } from "@lucide/vue";
import type { Card } from "@dna/sdk";
import { text } from "./props";
defineProps<{ card: Card }>();
</script>
<template>
  <blockquote class="card-quote">
    <Quote :size="18" /><span>{{ text(card.props, "quote") }}</span>
  </blockquote>
  <p class="card-body muted">{{ text(card.props, "speaker") }}</p>
</template>
