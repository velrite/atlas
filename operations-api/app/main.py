from fastapi import FastAPI, Response

app = FastAPI(title="Atlas Operations API")

# Kubernetes liveness probe hits this. It should only ever answer
# "am I alive" — never touch Redis, Atlas, or anything external.
@app.get("/health")
def health():
    return {"status": "ok"}

# Kubernetes readiness probe hits this. Chunk 2 will make this check
# it can actually reach kubectl/GMP before saying "ready" — for now
# it's identical to /health, on purpose, so we can prove the container
# and its probes work before adding real dependencies to fail on.
@app.get("/ready")
def ready():
    return {"status": "ready"}
