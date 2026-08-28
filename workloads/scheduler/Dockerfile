FROM python:3.12-slim

WORKDIR /app

COPY common/requirements.txt ./common-requirements.txt
COPY scheduler/requirements.txt ./scheduler-requirements.txt
RUN pip install --no-cache-dir -r common-requirements.txt -r scheduler-requirements.txt

COPY common/ ./common/
COPY scheduler/ ./scheduler/

WORKDIR /app/scheduler

USER nobody

CMD ["python3", "main.py"]
