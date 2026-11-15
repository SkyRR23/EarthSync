# Bounded performance measurements

Subject `660b479c3ffb714cd1d489e1241c026ceae6ed67`. Environment `Linux-6.18.57-x86_64-with-glibc2.41`, Python 3.12.14, three reported CPUs. No public-provider load test.

| Path | n | Median | p95 nearest rank | Maximum |
|---|---:|---:|---:|---:|
| Native one-day ET0 subprocess | 20 | 1.69 ms | 3.52 ms | 3.76 ms |
| Original REAL transport requests | 188 | 0.938 s | 2.489 s | 11.587 s |

Twenty local sequential native calls used clearly synthetic valid weather; the network timings were already captured by the bounded real-source run. They are separate distributions, not whole-screen latency. Network admission was serialized by the disk-cache lock despite a configured maximum concurrency of two. Host/network/caches differ from farmers' devices. No capacity, Windows/mobile speed, low-bandwidth SLA, large-polygon throughput or production uptime claim is supported. [Raw timing summary](evidence/performance.json).
