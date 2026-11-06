<script setup lang="ts">
// The agent: the transcript, then the composer with the context line and the model controls together.
import { ui } from "../client/store";
import Composer from "./Composer.vue";
import ModelPicker from "./ModelPicker.vue";
import Transcript from "./Transcript.vue";
</script>

<template>
  <section class="column agent-column" data-col="agent" aria-label="Agent">
    <div class="pane transcript-pane"><Transcript /></div>
    <Composer />
    <ModelPicker v-if="ui.models" />
  </section>
</template>
