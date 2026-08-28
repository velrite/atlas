"""
Atlas Scheduler -- pulls queued jobs, evaluates real worker capacity,
and assigns each job to the best-fit available worker.
"""

import os
import sys
import time
import logging

import redis

sys.path.append(os.path.join(os.path.dirname(__file__), "..", "common"))
from job import Job, JobStatus

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("atlas-scheduler")

REDIS_HOST = os.environ.get("REDIS_HOST", "redis")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
QUEUE_KEY = "atlas:queue:pending"
JOB_KEY_PREFIX = "atlas:job:"
WORKER_KEY_PREFIX = "atlas:worker:"
ASSIGNED_QUEUE_PREFIX = "atlas:queue:worker:"
WORKER_HEARTBEAT_TIMEOUT_SECONDS = 15

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def get_live_workers():
    live = []
    now = time.time()
    for key in r.scan_iter(f"{WORKER_KEY_PREFIX}*"):
        data = r.hgetall(key)
        if not data:
            continue
        last_heartbeat = float(data.get("last_heartbeat", 0))
        if now - last_heartbeat > WORKER_HEARTBEAT_TIMEOUT_SECONDS:
            continue
        live.append({
            "worker_id": data["worker_id"],
            "available_cpu_millicores": int(data["available_cpu_millicores"]),
            "available_memory_mb": int(data["available_memory_mb"]),
        })
    return live


def select_worker(job, candidates):
    eligible = [
        w for w in candidates
        if w["available_cpu_millicores"] >= job.cpu_millicores
        and w["available_memory_mb"] >= job.memory_mb
    ]
    if not eligible:
        return None
    return min(eligible, key=lambda w: w["available_cpu_millicores"])


def schedule_loop():
    logger.info("Scheduler started. Polling for jobs...")
    while True:
        job_id = r.blpop(QUEUE_KEY, timeout=5)
        if job_id is None:
            continue

        _, job_id = job_id
        raw = r.get(f"{JOB_KEY_PREFIX}{job_id}")
        if raw is None:
            logger.warning(f"Job {job_id} vanished before scheduling -- skipping")
            continue

        job = Job.from_json(raw)

        candidates = get_live_workers()
        chosen = select_worker(job, candidates)

        if chosen is None:
            logger.warning(f"No capacity for job {job.job_id} (needs {job.cpu_millicores}m/{job.memory_mb}MB, {len(candidates)} live workers). Requeuing.")
            r.rpush(QUEUE_KEY, job.job_id)
            time.sleep(1)
            continue

        job.status = JobStatus.ASSIGNED
        job.assigned_worker = chosen["worker_id"]
        job.scheduled_at = time.time()
        r.set(f"{JOB_KEY_PREFIX}{job.job_id}", job.to_json())

        r.rpush(f"{ASSIGNED_QUEUE_PREFIX}{chosen['worker_id']}", job.job_id)

        latency = job.scheduling_latency_seconds()
        logger.info(f"Job {job.job_id} assigned to {chosen['worker_id']} (scheduling latency: {latency:.3f}s)")


if __name__ == "__main__":
    schedule_loop()
