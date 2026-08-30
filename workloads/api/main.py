"""
Atlas API -- accepts job submissions, pushes them to the Redis queue,
returns the job ID immediately (async, non-blocking).
"""

import os
import sys
import logging

from flask import Flask, request, jsonify
import redis

sys.path.append(os.path.join(os.path.dirname(__file__), "..", "common"))
from job import Job, JobStatus

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("atlas-api")

app = Flask(__name__)

REDIS_HOST = os.environ.get("REDIS_HOST", "redis")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
QUEUE_KEY = "atlas:queue:pending"
JOB_KEY_PREFIX = "atlas:job:"

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


@app.route("/health", methods=["GET"])
def health():
    try:
        r.ping()
        return jsonify({"status": "healthy"}), 200
    except redis.exceptions.ConnectionError:
        return jsonify({"status": "unhealthy", "reason": "redis unreachable"}), 503


@app.route("/ready", methods=["GET"])
def ready():
    try:
        r.ping()
        return jsonify({"status": "ready"}), 200
    except redis.exceptions.ConnectionError:
        return jsonify({"status": "not_ready"}), 503


@app.route("/jobs", methods=["POST"])
def submit_job():
    body = request.get_json(force=True, silent=True) or {}

    job = Job(
        cpu_millicores=body.get("cpu_millicores", 100),
        memory_mb=body.get("memory_mb", 128),
        priority=body.get("priority", 5),
        max_runtime_seconds=body.get("max_runtime_seconds", 60),
        max_retries=body.get("max_retries", 3),
        region_preference=body.get("region_preference"),
        payload=body.get("payload", {}),
    )

    r.set(f"{JOB_KEY_PREFIX}{job.job_id}", job.to_json())
    r.rpush(QUEUE_KEY, job.job_id)

    logger.info(f"Job submitted: {job.job_id}")

    return jsonify({"job_id": job.job_id, "status": job.status.value}), 202


@app.route("/jobs/<job_id>", methods=["GET"])
def get_job(job_id):
    raw = r.get(f"{JOB_KEY_PREFIX}{job_id}")
    if raw is None:
        return jsonify({"error": "job not found"}), 404
    job = Job.from_json(raw)
    return jsonify({
        "job_id": job.job_id,
        "status": job.status.value,
        "attempts": job.attempts,
        "assigned_worker": job.assigned_worker,
        "scheduling_latency_seconds": job.scheduling_latency_seconds(),
        "total_duration_seconds": job.total_duration_seconds(),
        "result": job.result,
        "error": job.error,
    }), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)  # nosec B104 -- intentional: container must accept traffic from the Kubernetes Service/other pods, not just localhost
