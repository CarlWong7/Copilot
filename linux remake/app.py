from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import PlainTextResponse
import shutil
import subprocess
import tempfile
from pathlib import Path

app = FastAPI(title="PDF Converter (internal API)")


@app.post("/convert", response_class=PlainTextResponse)
async def convert(file: UploadFile = File(...)):
    # Accepts a PDF upload and returns converted text (single concatenated txt)
    if file.content_type != "application/pdf":
        raise HTTPException(status_code=415, detail="Only PDF files are supported")

    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        in_path = td_path / "input.pdf"
        out_path = td_path / "output.txt"

        # Write uploaded file to disk
        with in_path.open("wb") as f:
            shutil.copyfileobj(file.file, f)

        # Run the bundled converter script
        proc = subprocess.run(["/bin/bash", "/opt/converter/converter.sh", str(in_path), str(out_path)], capture_output=True, text=True)
        if proc.returncode != 0:
            raise HTTPException(status_code=500, detail=f"Conversion failed: {proc.stderr[:1000]}")

        # Read and return the resulting text
        if not out_path.exists():
            raise HTTPException(status_code=500, detail="Conversion did not produce an output file")
        txt = out_path.read_text(encoding="utf-8")
        return PlainTextResponse(content=txt, media_type="text/plain; charset=utf-8")
