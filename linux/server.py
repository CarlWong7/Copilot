import os
import tempfile
import subprocess
from flask import Flask, request, send_file, jsonify

app = Flask(__name__)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({ 'status': 'ok' })

@app.route('/convert', methods=['POST'])
def convert():
    if 'file' not in request.files:
        return jsonify({ 'error': 'no file part' }), 400
    f = request.files['file']
    if f.filename == '':
        return jsonify({ 'error': 'empty filename' }), 400

    # Save uploaded PDF to tmp
    with tempfile.TemporaryDirectory() as tmpdir:
        in_path = os.path.join(tmpdir, 'input.pdf')
        out_path = os.path.join(tmpdir, 'output.csv')
        f.save(in_path)

        # Call the shell script to convert
        cmd = ["/app/pdf2csv.sh", in_path, out_path]
        try:
            subprocess.check_output(cmd, stderr=subprocess.STDOUT, timeout=120)
        except subprocess.CalledProcessError as e:
            return jsonify({ 'error': 'conversion failed', 'details': e.output.decode(errors='ignore') }), 500
        except subprocess.TimeoutExpired:
            return jsonify({ 'error': 'conversion timeout' }), 504

        if not os.path.exists(out_path):
            return jsonify({ 'error': 'conversion produced no output' }), 500

        return send_file(out_path, as_attachment=True, download_name=os.path.basename(f.filename).rsplit('.',1)[0] + '.csv')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
