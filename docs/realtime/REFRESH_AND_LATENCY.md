# Refresh and latency

| Source | Initial check cadence | Data interpretation |
|---|---:|---|
| Iowa station | 60 s | Minute-table recent measurements; individual sensors may report less often |
| NWS alerts | 60 s, never below provider cache/rate rules | Official active feed; empty success differs from failure |
| NWS daily/hourly/grid | 900 s + provider cache lifetime | Original forecast validity and accumulation intervals |
| Open-Meteo | 1,800 s + cache validators | Model blend; initialization/publication unknown |
| Extended GFS | 1,800 s metadata/cycle check | Current cycle, bounded fallback to previous cycle; unchanged run reused |
| IMERG Early | 900 s catalog check | New half-hour products, normally hours delayed |
| HLS-VI / SMAP | 3,600 s catalog check | New granule/revision only; daily/multi-day source latency |
| SoilGrids / POWER | Existing explicit reference workflows | Not minute weather feeds |
| Flutter local cache | 15 s | No direct NASA/NOAA requests or credentials |

One backend scheduler maintains independent in-flight source tasks, so a slow
satellite or model operation does not stop station/alert checks. Network connection
pools, host locks, shared GFS throttling and a NASA numerical semaphore bound work.
Only Ames is monitored by default. Explicit selection activates secondary public
references and at most four farm revisions. The worker is process-local: use the
provided single-worker local launcher, not multiple competing uvicorn workers.

SQLite retains latest states, at most 80 conditional HTTP cache entries, 64 QA
rejection keys, 40 farm-source slots and a bounded recent station window. The
existing source cache separately evicts expired entries and caps at 128. Raw
satellite range blocks are memory-only and freed after each extraction. Shutdown
cancels tasks and signals active numerical readers; HTTP operations remain bounded.

Three delays are deliberately separate:

1. **Observation → publication:** unknown when the provider does not verify it.
2. **Publication → ingestion:** also unknown without a verified publication time.
3. **Backend cache → browser display:** measured in the actual browser watch.

Observation-to-ingestion is an additional descriptive interval, not proof that
EarthSync controls provider publication latency. CMR revision time is not promoted
to publication time. Cached API timings and backend-first-noticed-to-display
measurements appear in `evidence/verification-summary.json`. These are measured
samples on this cloud machine, not service guarantees or Windows benchmarks.
