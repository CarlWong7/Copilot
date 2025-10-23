import os
import subprocess
import tempfile
from flask import Flask, request, send_file, jsonify
from werkzeug.utils import secure_filename

app = Flask(__name__)

@app.route('/convert', methods=['POST'])
def convert():
    if 'file' not in request.files:
        return jsonify({'error': 'no file provided'}), 400

    f = request.files['file']
    if f.filename == '':
        return jsonify({'error': 'empty filename'}), 400

    filename = secure_filename(f.filename)
    if not filename.lower().endswith('.pdf'):
        return jsonify({'error': 'only pdf files are supported'}), 400

    with tempfile.TemporaryDirectory() as tmpdir:
        pdf_path = os.path.join(tmpdir, filename)
        f.save(pdf_path)

        # call the script which will produce a CSV next to the PDF
        script_path = '/app/pdf2csv.sh'
        try:
            subprocess.run([script_path, pdf_path], check=True, cwd=tmpdir, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except subprocess.CalledProcessError as e:
            return jsonify({'error': 'conversion failed', 'stdout': e.stdout.decode('utf-8', errors='replace'), 'stderr': e.stderr.decode('utf-8', errors='replace')}), 500

        csv_path = os.path.splitext(pdf_path)[0] + '.csv'
        if not os.path.exists(csv_path):
            return jsonify({'error': 'csv not produced'}), 500

        return send_file(csv_path, mimetype='text/csv', as_attachment=True, download_name=os.path.basename(csv_path))

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
