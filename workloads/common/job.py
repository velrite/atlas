"""
Atlas -- Shared job schema.
Every component (API, scheduler, worker) imports this so the
definition of a "job" is consistent across the whole system.
"""

import uuid
import time
from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import Optional
import json


class JobStatus(str, Enum):
    QUEUED = "queued"
    ASSIGNED = "assigned"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    DEAD_LETTER = "dead_letter"


@dataclass
class Job:
    job_id: str = field(default_factory=lambda: str(uuid.uuid4()))

    cpu_millicores: int = 100
    memory_mb: int = 128
    priority: int = 5
    max_runtime_seconds: int = 60
    max_retries: int = 3
    region_preference: Optional[str] = None
    payload: dict = field(default_factory=dict)

    status: JobStatus = JobStatus.QUEUED
    attempts: int = 0
    assigned_worker: Optional[str] = None
    submitted_at: float = field(default_factory=time.time)
    scheduled_at: Optional[float] = None
    started_at: Optional[float] = None
    finished_at: Optional[float] = None
    result: Optional[dict] = None
    error: Optional[str] = None

    # W3C traceparent carrier, injected at submission time by the API and
    # read back at each stage (scheduler, worker) so all spans for this
    # job share one trace_id -- this is the deliberate manual propagation
    # this project's Redis-mediated handoff needs, since there's no HTTP
    # call between scheduler and worker for auto-instrumentation to hook.
    trace_context: dict = field(default_factory=dict)

    def to_json(self) -> str:
        d = asdict(self)
        d["status"] = self.status.value
        return json.dumps(d)

    @staticmethod
    def from_json(data: str) -> "Job":
        d = json.loads(data)
        d["status"] = JobStatus(d["status"])
        return Job(**d)

    def scheduling_latency_seconds(self) -> Optional[float]:
        if self.scheduled_at is None:
            return None
        return self.scheduled_at - self.submitted_at

    def total_duration_seconds(self) -> Optional[float]:
        if self.finished_at is None:
            return None
        return self.finished_at - self.submitted_at
