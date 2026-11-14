"""One-process bounded worker; durable status and fail-closed restart recovery."""

import asyncio
import json
import time
from uuid import uuid4

from .errors import PlatformError
from .store import encoded


class Jobs:
    def __init__(self, store, handlers, capacity=8, workers=2, deadline=120):
        self.store, self.handlers = store, handlers
        self.capacity, self.worker_count, self.deadline = capacity, workers, deadline
        self.queue = asyncio.Queue(maxsize=capacity)
        self.tasks = []
        self.running = {}

    async def start(self):
        with self.store.connection() as db:
            # Retries require a new explicit submission; never silently replay work.
            db.execute(
                "UPDATE jobs SET status='failed',error='WORKER_RESTARTED',retryable=1,updated=? WHERE status IN ('queued','running')",
                (time.time(),),
            )
        self.tasks = [
            asyncio.create_task(self._worker()) for _ in range(self.worker_count)
        ]

    async def close(self):
        for task in self.tasks:
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)
        self.tasks.clear()

    def get(self, owner, job_id):
        with self.store.connection() as db:
            row = db.execute(
                "SELECT * FROM jobs WHERE id=? AND owner=?", (str(job_id), owner)
            ).fetchone()
            if row is None:
                raise PlatformError("NOT_FOUND", 404)
            return {
                "id": row["id"],
                "kind": row["kind"],
                "status": row["status"],
                "result": json.loads(row["result"]) if row["result"] else None,
                "error": row["error"],
                "retryable": bool(row["retryable"]),
            }

    async def submit(self, owner, kind, key, request):
        if kind not in self.handlers:
            raise PlatformError("UNSUPPORTED_PRODUCT")
        with self.store.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            # Deduplicate pending work; caller/version/geometry are in the key.
            row = db.execute(
                "SELECT id FROM jobs WHERE owner=? AND cache_key=? AND status IN ('queued','running') ORDER BY created DESC LIMIT 1",
                (owner, key),
            ).fetchone()
            if row:
                ident = row[0]
            else:
                if self.queue.full():
                    raise PlatformError("JOB_CAPACITY", 429, True)
                self.store._quota(db, "jobs")
                ident = str(uuid4())
                now = time.time()
                db.execute(
                    "INSERT INTO jobs (id,owner,cache_key,kind,status,request,created,updated) VALUES (?,?,?,?,?,?,?,?)",
                    (ident, owner, key, kind, "queued", encoded(request), now, now),
                )
                self.queue.put_nowait((ident, owner, kind, request))
        return self.get(owner, ident)

    def cancel(self, owner, ident):
        self.get(owner, ident)
        with self.store.connection() as db:
            db.execute(
                "UPDATE jobs SET status='cancelled',updated=? WHERE id=? AND owner=? AND status IN ('queued','running')",
                (time.time(), str(ident), owner),
            )
        task = self.running.get(str(ident))
        if task:
            task.cancel()
        return self.get(owner, ident)

    def _finish(self, ident, status, result=None, error=None, retryable=False):
        with self.store.connection() as db:
            db.execute(
                "UPDATE jobs SET status=?,result=?,error=?,retryable=?,updated=? WHERE id=? AND status='running'",
                (
                    status,
                    encoded(result) if result is not None else None,
                    error,
                    int(retryable),
                    time.time(),
                    ident,
                ),
            )

    async def _worker(self):
        while True:
            item = await self.queue.get()
            ident, owner, kind, request = item
            try:
                with self.store.connection() as db:
                    changed = db.execute(
                        "UPDATE jobs SET status='running',updated=? WHERE id=? AND status='queued'",
                        (time.time(), ident),
                    ).rowcount
                if not changed:
                    continue
                task = asyncio.create_task(self.handlers[kind](owner, request))
                self.running[ident] = task
                try:
                    async with asyncio.timeout(self.deadline):
                        result = await task
                    self._finish(ident, "succeeded", result=result)
                except PlatformError as exc:
                    self._finish(
                        ident, "failed", error=exc.code, retryable=exc.retryable
                    )
                except TimeoutError:
                    self._finish(ident, "failed", error="TIMEOUT", retryable=True)
                except asyncio.CancelledError:
                    self._finish(
                        ident, "failed", error="WORKER_STOPPED", retryable=True
                    )
                    if asyncio.current_task().cancelling():
                        raise
                except Exception:
                    self._finish(ident, "failed", error="PROCESSING_FAILURE")
                finally:
                    self.running.pop(ident, None)
            finally:
                self.queue.task_done()
