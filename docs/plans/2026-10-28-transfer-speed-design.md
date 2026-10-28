# Live transfer speed

Show recent throughput below each running transfer's progress bar and in its
details. Use B/s, KB/s, MB/s and GB/s with decimal thresholds, matching file sizes.
Both directions share the same measurement; downloads are the primary use case.

Choose a two-second rolling window over lifetime average (slow to reflect stalls)
or single-callback speed (too noisy). Use cumulative whole-task bytes, so directory
child changes do not reset the estimate. Capture monotonic time on the protocol
queue after bytes are acknowledged or written, before main-actor dispatch.
Ignore stale samples and wait briefly for a meaningful initial measurement.

A small SwiftUI TimelineView refreshes only the speed label every half second.
Advancing the window without new packets reaches 0 B/s on stalls. Waiting,
planning, cancellation and terminal states hide the label and its timer. Existing
progress throttling and per-job observation are preserved. There is no additional
network request or model-wide timer. The view reuses Beautiful UI TaskRows styles
and the generated color/spacing tokens.

Verify unit boundaries, irregular sample timing, stalls/recovery, large byte
counters, stale callbacks, task state transitions, actual local SFTP transfers,
and notification isolation. Inspect queue and detail layouts with synthetic demo
data, then build, sign and install the updated application.
