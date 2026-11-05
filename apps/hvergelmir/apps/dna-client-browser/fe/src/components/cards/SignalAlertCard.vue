<script setup lang="ts">
import { Zap } from "@lucide/vue";
import type { Card } from "@dna/sdk";
import { text } from "./props";
defineProps<{ card: Card }>();
</script>
<template>
  <div class="card-kicker signal"><Zap :size="14" />Act on this</div>
  <h3 class="card-title">{{ text(card.props, "title") || card.title }}</h3>
  <p class="card-action">{{ text(card.props, "action") }}</p>
  <p class="card-body muted">{{ text(card.props, "why") }}</p>
</template>
