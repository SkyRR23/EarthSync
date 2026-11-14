"""Availability aggregation only; no agronomic inference or POWER fallback."""

import asyncio

from .common import utcnow
from .models import ContextResponse, Situation
from .vegetation import PRODUCTS, VegetationAdapter


class ContextService:
    def __init__(self, soil, weather, *, now=utcnow):
        self.adapters = [soil, weather, *(VegetationAdapter(k) for k in PRODUCTS)]
        self.now = now

    async def context(self, query):
        evidence = await asyncio.gather(*(a.context(query) for a in self.adapters))
        return ContextResponse(
            as_of=self.now(),
            query=query,
            evidence=evidence,
            situation=Situation(
                availability={e.context_kind: e.availability for e in evidence},
                present_value_counts={
                    e.context_kind: e.quality.present for e in evidence
                },
            ),
        )
