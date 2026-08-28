FROM python:3.12-slim

WORKDIR /app

COPY common/requirements.txt ./common-requirements.txt
COPY worker/requirements.txt ./worker-requirements.txt
RUN pip install --no-cache-dir -r common-requirements.txt -r worker-requirements.txt

COPY common/ ./common/
COPY worker/ ./worker/

WORKDIR /app/worker

USER nobody

CMD ["python3", "main.py"]
