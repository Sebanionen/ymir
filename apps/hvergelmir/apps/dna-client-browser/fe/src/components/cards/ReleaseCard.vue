<script setup lang="ts">
import { Check, Package } from "@lucide/vue";
import type { Card } from "@dna/sdk";
import { list, text } from "./props";
defineProps<{ card: Card }>();
</script>
<template>
  <div class="card-kicker"><Package :size="14" />Release</div>
  <h3 class="card-title">
    {{ text(card.props, "name") || card.title }}
    <span class="version">{{ text(card.props, "version") }}</span>
  </h3>
  <ul class="icon-list">
    <li v-for="(c, i) in list(card.props, 'changes')" :key="i"><Check :size="13" />{{ c }}</li>
  </ul>
</template>
