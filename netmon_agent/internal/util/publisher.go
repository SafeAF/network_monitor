package util

import (
  "netmon_agent/internal/event"
  "netmon_agent/internal/metrics"
)

func TrySend(out chan<- event.Event, m *metrics.Metrics, stream string, ev event.Event) bool {
  select {
  case out <- ev:
    return true
  default:
    if m != nil {
      m.DroppedLocalTotal.WithLabelValues(stream).Inc()
    }
    return false
  }
}
