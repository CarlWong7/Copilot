Docker Compose usage

This repo includes a `docker-compose.yml` with two services:

- `api` - builds the web API and exposes it on port 8000
- `convert` - a helper one-off service that runs `/app/pdf2csv.sh` inside the image

Build and run the API service:

```powershell
# Build and start services
docker compose up --build -d api

# View logs
docker compose logs -f api

# Stop
docker compose down
```

Run a one-off conversion using the `convert` service by mounting your files into the project folder and using the service to convert:

```powershell
# Assuming you have input.pdf in the repo folder (or adjust path), run:
docker compose run --rm convert /data/input.pdf /data/output.csv

# The command above will write output.csv into the project folder because the repo is mounted at /data
```

If you prefer a single docker run instead of compose, use the Docker run commands from the main README.
