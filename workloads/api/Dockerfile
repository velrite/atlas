FROM python:3.12-slim

WORKDIR /app

COPY common/requirements.txt ./common-requirements.txt
COPY api/requirements.txt ./api-requirements.txt
RUN pip install --no-cache-dir -r common-requirements.txt -r api-requirements.txt

COPY common/ ./common/
COPY api/ ./api/

WORKDIR /app/api

EXPOSE 8080

USER nobody

CMD ["python3", "main.py"]
