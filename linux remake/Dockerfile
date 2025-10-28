FROM python:3.11-slim

# Install poppler-utils (pdftotext, pdfinfo) and cleanup
RUN apt-get update \
    && apt-get install -y --no-install-recommends poppler-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/converter

# Copy the existing converter script into the image
COPY converter.sh /opt/converter/converter.sh
RUN chmod +x /opt/converter/converter.sh

# Python deps for the API server
COPY requirements.txt /opt/converter/requirements.txt
RUN pip install --no-cache-dir -r /opt/converter/requirements.txt

# App
COPY app.py /opt/converter/app.py

# Do not expose ports in the Dockerfile (user requested "no ports").
# The server will run inside the container, reachable via container-internal networking
# (e.g. via `docker exec` or from other containers on the same Docker network).

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
