<script setup lang="ts">
import { MessageSquare, MessagesSquare } from "@lucide/vue";
import type { Card } from "@dna/sdk";
import { list, text } from "./props";
defineProps<{ card: Card }>();
</script>
<template>
  <div class="card-kicker"><MessagesSquare :size="14" />Thread pulse</div>
  <h3 class="card-title">{{ text(card.props, "title") || card.title }}</h3>
  <ul class="icon-list">
    <li v-for="(t, i) in list(card.props, 'takes')" :key="i">
      <MessageSquare :size="13" />{{ t }}
    </li>
  </ul>
  <a
    v-if="card.discussionUrl"
    class="card-link"
    :href="card.discussionUrl"
    target="_blank"
    rel="noopener"
    >Read the thread</a
  >
</template>
