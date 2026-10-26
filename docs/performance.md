# Performance checks

Run `.build/debug/Senda --performance-checks --verify` after a debug build. The
workload uses 20,000 synthetic files, exercises cached visible-entry reads and
selection synchronization, then lays out the real workspace with a running job.
It does not use SSH or enumerate user directories.

The 2026-10-26 run is recorded in [performance-results.json](performance-results.json):

| Measurement | Result |
| --- | ---: |
| 200 visible-array reads | 0.074 ms |
| 1,000 unchanged-selection synchronizations | 0.700 ms |
| 200 job progress mutations | 0.318 ms |
| 60 progress updates with real view layout | 255.949 ms |
| Model-wide notifications from progress | 0 |

These are local workload timings, not end-to-end interaction latency, frame-rate
measurements or network throughput. `--verify` asserts correctness and notification
isolation instead of imposing unstable timing thresholds. The application retains
native virtualized tables and updates only the individual transfer row on progress.
