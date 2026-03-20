<script setup>
import { ref, onMounted, onUnmounted } from "vue";

const props = defineProps({
  apiBase: {
    type: String,
    default: "/api/v1/contrib/CircFeed",
  },
  maxEvents: {
    type: Number,
    default: 20,
  },
  pollInterval: {
    type: Number,
    default: 3000,
  },
});

const events = ref([]);
const connected = ref(false);
let pollTimer = null;
let lastSeenId = 0;

const EVENT_LABELS = {
  checkout: "Check out",
  checkin: "Check in",
  renewal: "Renewal",
};

const EVENT_COLORS = {
  checkout: "#1976d2",
  checkin: "#4caf50",
  renewal: "#ff9800",
};

function formatTime(timestamp) {
  if (!timestamp) return "";
  const d = new Date(timestamp.replace(" ", "T"));
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

async function poll() {
  try {
    const res = await fetch(`${props.apiBase}/events/recent`);
    if (!res.ok) return;

    const data = await res.json();
    connected.value = true;

    // Only add events we haven't seen
    const newEvents = data.filter(e => e.id > lastSeenId);
    if (newEvents.length > 0) {
      events.value.push(...newEvents);
      // Trim to max
      while (events.value.length > props.maxEvents) {
        events.value.shift();
      }
      lastSeenId = Math.max(...events.value.map(e => e.id));
    }
  } catch (e) {
    connected.value = false;
  }
}

onMounted(async () => {
  await poll();
  pollTimer = setInterval(poll, props.pollInterval);
});

onUnmounted(() => {
  if (pollTimer) {
    clearInterval(pollTimer);
  }
});
</script>

<template>
  <div class="cf-feed">
    <div class="cf-feed__header">
      <h4 class="cf-feed__title">Live Circulation Feed</h4>
      <span :class="['cf-feed__status', connected ? 'cf-feed__status--on' : 'cf-feed__status--off']">
        {{ connected ? "Live" : "Connecting..." }}
      </span>
    </div>

    <div v-if="events.length === 0" class="cf-feed__empty">
      Waiting for circulation activity...
    </div>

    <TransitionGroup name="cf-event" tag="div" class="cf-feed__list">
      <div v-for="event in [...events].reverse()" :key="event.id" class="cf-feed__event">
        <span
          class="cf-feed__badge"
          :style="{ background: EVENT_COLORS[event.event_type] || '#999' }"
        >
          {{ EVENT_LABELS[event.event_type] || event.event_type }}
        </span>
        <span class="cf-feed__title-text">{{ event.title }}</span>
        <span class="cf-feed__patron">{{ event.patron_name }}</span>
        <span class="cf-feed__library">{{ event.library }}</span>
        <span class="cf-feed__time">{{ formatTime(event.created_at) }}</span>
      </div>
    </TransitionGroup>
  </div>
</template>

<style>
.cf-feed {
  font-family: inherit;
  padding: 1em 1.25em;
  margin: 1em 0;
  border: 1px solid #e0e0e0;
  border-radius: 6px;
  background: #fafafa;
  max-height: 400px;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.cf-feed__header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.75em;
  flex-shrink: 0;
}

.cf-feed__title {
  margin: 0;
  font-size: 1em;
  color: #333;
}

.cf-feed__status {
  font-size: 0.75em;
  padding: 0.2em 0.6em;
  border-radius: 10px;
  font-weight: 600;
}

.cf-feed__status--on {
  background: #e8f5e9;
  color: #2e7d32;
}

.cf-feed__status--off {
  background: #fff3e0;
  color: #e65100;
}

.cf-feed__empty {
  text-align: center;
  color: #999;
  padding: 2em 0;
  font-style: italic;
}

.cf-feed__list {
  overflow-y: auto;
  flex: 1;
}

.cf-feed__event {
  display: flex;
  align-items: center;
  gap: 0.75em;
  padding: 0.5em 0;
  border-bottom: 1px solid #eee;
  font-size: 0.9em;
}

.cf-feed__event:last-child {
  border-bottom: none;
}

.cf-feed__badge {
  flex-shrink: 0;
  padding: 0.15em 0.5em;
  border-radius: 3px;
  color: #fff;
  font-size: 0.8em;
  font-weight: 600;
  min-width: 70px;
  text-align: center;
}

.cf-feed__title-text {
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: #333;
}

.cf-feed__patron {
  color: #666;
  flex-shrink: 0;
}

.cf-feed__library {
  color: #999;
  font-size: 0.85em;
  flex-shrink: 0;
}

.cf-feed__time {
  color: #999;
  font-size: 0.8em;
  flex-shrink: 0;
  font-variant-numeric: tabular-nums;
}

.cf-event-enter-active {
  transition: all 0.3s ease;
}

.cf-event-enter-from {
  opacity: 0;
  transform: translateY(-10px);
}
</style>
