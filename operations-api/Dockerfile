FROM python:3.12-slim

# Kyverno's disallow-privileged-containers policy needs the container
# to run as a non-root user, not just "not privileged" in the pod spec.
RUN useradd --create-home --uid 1000 appuser
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

USER appuser
EXPOSE 8080

# 0.0.0.0 because inside a container "localhost" only means "this
# container" — the Service can't reach a server that only listens on
# its own loopback interface.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
