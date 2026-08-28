"""
Atlas Worker -- registers its capacity, heartbeats, pulls assigned jobs
from its own queue, executes them, and reports results.
"""

import os
import sys
import time
import uuid
import socket
import logging
import threading

import redis

sys.path.append(os.path.join(os.path.dirname(__file__), "..", "common"))
from job import Job, JobStatus

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("atlas-worker")

REDIS_HOST = os.environ.get("REDIS_HOST", "redis")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
JOB_KEY_PREFIX = "atlas:job:"
WORKER_KEY_PREFIX = "atlas:worker:"
ASSIGNED_QUEUE_PREFIX = "atlas:queue:worker:"
HEARTBEAT_INTERVAL_SECONDS = 5

TOTAL_CPU_MILLICORES = int(os.environ.get("WORKER_CPU_MILLICORES", "1000"))
TOTAL_MEMORY_MB = int(os.environ.get("WORKER_MEMORY_MB", "512"))

WORKER_ID = f"worker-{socket.gethostname()}-{uuid.uuid4().hex[:6]}"

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

_lock = threading.Lock()
_used_cpu = 0
_used_memory = 0


def heartbeat_loop():
    while True:
        with _lock:
            available_cpu = TOTAL_CPU_MILLICORES - _used_cpu
            available_memory = TOTAL_MEMORY_MB - _used_memory
        r.hset(f"{WORKER_KEY_PREFIX}{WORKER_ID}", mapping={
            "worker_id": WORKER_ID,
            "available_cpu_millicores": available_cpu,
            "available_memory_mb": available_memory,
            "last_heartbeat": time.time(),
        })
        time.sleep(HEARTBEAT_INTERVAL_SECONDS)


def execute_job(job):
    global _used_cpu, _used_memory

    raw = r.get(f"{JOB_KEY_PREFIX}{job.job_id}")
    if raw:
        current = Job.from_json(raw)
        if current.status == JobStatus.SUCCEEDED:
            logger.info(f"Job {job.job_id} already succeeded elsewhere -- skipping duplicate execution")
            return

    with _lock:
        _used_cpu += job.cpu_millicores
        _used_memory += job.memory_mb

    job.status = JobStatus.RUNNING
    job.started_at = time.time()
    job.attempts += 1
    r.set(f"{JOB_KEY_PREFIX}{job.job_id}", job.to_json())
    logger.info(f"Executing job {job.job_id} (attempt {job.attempts})")

    try:
        work_duration = min(job.payload.get("simulated_duration_seconds", 2), job.max_runtime_seconds)
        time.sleep(work_duration)

        job.status = JobStatus.SUCCEEDED
        job.result = {"message": "completed", "worker": WORKER_ID}

    except Exception as e:
        job.error = str(e)
        if job.attempts >= job.max_retries:
            job.status = JobStatus.DEAD_LETTER
            logger.error(f"Job {job.job_id} exceeded max retries ({job.max_retries}) -- dead-lettered")
        else:
            job.status = JobStatus.QUEUED
            logger.warning(f"Job {job.job_id} failed (attempt {job.attempts}), will retry")
            r.rpush("atlas:queue:pending", job.job_id)

    finally:
        job.finished_at = time.time()
        r.set(f"{JOB_KEY_PREFIX}{job.job_id}", job.to_json())
        with _lock:
            _used_cpu -= job.cpu_millicores
            _used_memory -= job.memory_mb


def work_loop():
    logger.info(f"Worker {WORKER_ID} started. Capacity: {TOTAL_CPU_MILLICORES}m CPU / {TOTAL_MEMORY_MB}MB")
    queue_key = f"{ASSIGNED_QUEUE_PREFIX}{WORKER_ID}"
    while True:
        job_id = r.blpop(queue_key, timeout=5)
        if job_id is None:
            continue
        _, job_id = job_id
        raw = r.get(f"{JOB_KEY_PREFIX}{job_id}")
        if raw is None:
            logger.warning(f"Job {job_id} vanished before execution -- skipping")
            continue
        job = Job.from_json(raw)
        execute_job(job)


if __name__ == "__main__":
    hb_thread = threading.Thread(target=heartbeat_loop, daemon=True)
    hb_thread.start()
    work_loop()
