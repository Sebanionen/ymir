<script setup lang="ts">
import { BadgeCheck, Link } from "@lucide/vue";
import type { Card } from "@dna/sdk";
import { list, text } from "./props";
defineProps<{ card: Card }>();
</script>
<template>
  <div class="card-kicker facts"><BadgeCheck :size="14" />Fact check</div>
  <h3 class="card-title">{{ text(card.props, "claim") || card.title }}</h3>
  <p class="verdict">{{ text(card.props, "verdict") }}</p>
  <ul class="icon-list">
    <li v-for="(e, i) in list(card.props, 'evidence')" :key="i">
      <Link :size="13" /><a v-if="e.startsWith('http')" :href="e" target="_blank" rel="noopener">{{
        e.replace(/^https?:\/\//, "").slice(0, 70)
      }}</a
      ><span v-else>{{ e }}</span>
    </li>
  </ul>
</template>
