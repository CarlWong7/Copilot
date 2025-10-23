FROM python:3.11-slim

# Install poppler (pdftotext) and other small deps
RUN apt-get update \
    && apt-get install -y --no-install-recommends poppler-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy application files
COPY pdf2csv.sh /app/pdf2csv.sh
COPY app.py /app/app.py
COPY requirements.txt /app/requirements.txt

RUN chmod +x /app/pdf2csv.sh

# Install Python deps
RUN pip install --no-cache-dir -r /app/requirements.txt

EXPOSE 8080

CMD ["gunicorn", "-b", "0.0.0.0:8080", "app:app", "--workers", "1"]
