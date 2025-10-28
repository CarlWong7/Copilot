PDF Converter Docker image

This repository contains a small Docker image that bundles `converter.sh` (a PDF->TXT converter that attempts to split multi-column pages into separate column pages when a blank vertical separator is detected) and exposes it via an internal HTTP API using FastAPI.

Important: per request, the image does not publish or expose host ports. The server runs inside the container on port 8000, but you should interact with it via `docker exec` (or from other containers on the same Docker network).

Build:

    docker build -t pdf-converter:latest .

Run (detached):

    docker run -d --name pdfconv pdf-converter:latest

Convert a file from the host without publishing ports

Option A — use `docker exec` with `curl` from inside the container:

    # copy a local PDF into the container (optional)
    docker cp mydoc.pdf pdfconv:/tmp/mydoc.pdf

    # then run curl inside the container to post and save the result
    docker exec -i pdfconv curl -s -X POST "http://127.0.0.1:8000/convert" -F "file=@/tmp/mydoc.pdf" -o /tmp/result.txt

    # then copy result back to host
    docker cp pdfconv:/tmp/result.txt ./result.txt

Option B — run a transient container that mounts your file and calls the API internally:

    docker run --rm -v "$PWD":/work --entrypoint sh pdf-converter:latest -c "curl -s -X POST 'http://127.0.0.1:8000/convert' -F 'file=@/work/mydoc.pdf' -o /work/result.txt"

Notes:

- If you want to reach the API directly from the host via localhost, you can instead publish the port when running the container (e.g. `-p 8000:8000`) but per your request the provided examples avoid publishing host ports.
- The converter requires `pdftotext` / `pdfinfo` (poppler-utils) and Python 3 — these are installed in the image.
- Tweak detection thresholds (THRESH, MIN_RUN) inside `converter.sh` if your PDFs have narrow inter-column spacing.
