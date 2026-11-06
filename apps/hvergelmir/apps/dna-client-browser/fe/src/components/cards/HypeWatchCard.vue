<script setup lang="ts">
import { Megaphone } from "@lucide/vue";
import type { Card } from "@dna/sdk";
import { text } from "./props";
defineProps<{ card: Card }>();
</script>
<template>
  <div class="card-kicker hype"><Megaphone :size="14" />Hype watch</div>
  <h3 class="card-title">{{ text(card.props, "title") || card.title }}</h3>
  <p class="card-body">{{ text(card.props, "reality_check") }}</p>
</template>
