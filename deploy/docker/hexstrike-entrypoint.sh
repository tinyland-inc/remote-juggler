#!/usr/bin/env bash
set -euo pipefail

echo "HexStrike pentest agent starting..."
echo "  RJ Gateway:  ${RJ_GATEWAY_URL}"
echo "  Aperture:    ${APERTURE_URL}"
echo "  Results dir: ${RESULTS_DIR}"

# Simple health endpoint + idle loop until real implementation replaces this.
python3 -c "
import http.server, threading, json, time, os

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                'status': 'ok',
                'agent': 'hexstrike',
                'scaffold': True,
                'gateway': os.environ.get('RJ_GATEWAY_URL', ''),
                'tools': ['nmap', 'netcat', 'dig', 'whois'],
            }).encode())
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, format, *args):
        pass

server = http.server.HTTPServer(('0.0.0.0', 8080), HealthHandler)
threading.Thread(target=server.serve_forever, daemon=True).start()
print('Health endpoint listening on :8080')

while True:
    time.sleep(60)
"
