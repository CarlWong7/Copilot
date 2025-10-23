# Use Debian slim with Python
FROM python:3.11-slim

# Install poppler for pdftotext and other utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    build-essential \
    procps \
    ca-certificates \
    tini \
  && rm -rf /var/lib/apt/lists/*

# Create app dir
WORKDIR /app

# Copy files
COPY pdf2csv.sh /app/pdf2csv.sh
COPY server.py /app/server.py
COPY requirements.txt /app/requirements.txt

# Make script executable
RUN chmod +x /app/pdf2csv.sh

# Install Python deps
RUN pip install --no-cache-dir -r /app/requirements.txt

EXPOSE 8000

# Use tini as PID 1 to reap zombies
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python", "-u", "server.py"]
