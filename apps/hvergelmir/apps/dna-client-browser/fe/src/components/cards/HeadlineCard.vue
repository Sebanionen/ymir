<script setup lang="ts">
import type { Card } from "@dna/sdk";
import { text } from "./props";
defineProps<{ card: Card }>();
</script>
<template>
  <h3 class="card-title big">{{ text(card.props, "title") || card.title }}</h3>
  <p class="card-dek">{{ text(card.props, "dek") }}</p>
</template>
