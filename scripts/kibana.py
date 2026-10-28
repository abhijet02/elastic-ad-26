#!/usr/bin/env python3
"""Export/import Kibana dashboards with dependencies, using a local SSH tunnel."""
import argparse
import base64
import getpass
import json
import pathlib
import ssl
import urllib.request

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('action', choices=['export', 'import'])
p.add_argument('file', type=pathlib.Path)
p.add_argument('--url', default='http://127.0.0.1:15601', help='Include /s/SPACE for a nondefault Kibana space')
p.add_argument('--user', default='elastic')
p.add_argument('--ca', help='CA certificate for HTTPS')
a = p.parse_args()
password = getpass.getpass('Kibana password (blank for no authentication): ')
headers = {'kbn-xsrf': 'true'}
if password:
    headers['Authorization'] = 'Basic ' + base64.b64encode(f'{a.user}:{password}'.encode()).decode()
if a.action == 'export':
    if a.file.exists():
        p.error('Export destination exists; choose a new file')
    headers['Content-Type'] = 'application/json'
    data = json.dumps({'type': ['dashboard'], 'includeReferencesDeep': True}).encode()
    endpoint = '/api/saved_objects/_export'
else:
    boundary = 'ElasticADRestoreBoundary321'
    headers['Content-Type'] = f'multipart/form-data; boundary={boundary}'
    data = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="dashboards.ndjson"\r\nContent-Type: application/ndjson\r\n\r\n'.encode()
            + a.file.read_bytes() + f'\r\n--{boundary}--\r\n'.encode())
    endpoint = '/api/saved_objects/_import'  # conflicts are reported; no implicit overwrite
req = urllib.request.Request(a.url.rstrip('/') + endpoint, data=data, headers=headers, method='POST')
with urllib.request.urlopen(req, context=ssl.create_default_context(cafile=a.ca), timeout=120) as r:
    result = r.read()
if a.action == 'export':
    objects = [json.loads(line) for line in result.splitlines() if line.strip()]
    if not any(o.get('type') == 'dashboard' for o in objects):
        raise SystemExit('No dashboards returned; check the Kibana space.')
    if any(o.get('missingRefCount', 0) for o in objects):
        raise SystemExit('Export has missing references; resolve these in Kibana first.')
    a.file.parent.mkdir(parents=True, exist_ok=True)
    a.file.write_bytes(result)
    a.file.chmod(0o600)
    print(f'Export saved to {a.file}; review for private data before committing.')
else:
    status = json.loads(result)
    print(json.dumps(status, indent=2))
    if not status.get('success'):
        raise SystemExit('Import needs attention; inspect the errors above.')
