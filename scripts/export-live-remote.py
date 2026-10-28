#!/usr/bin/env python3
"""Read-only exporter executed on the source VM by capture-live.sh.

Writes a tar.gz to stdout; diagnostics go to stderr. No event documents exported.
"""
import base64
import io
import json
import pathlib
import sys
import tarfile
import urllib.parse
import urllib.request

env = {}
for line in pathlib.Path('/root/elastic-ad/.env').read_text().splitlines():
    line = line.strip()
    if line and not line.startswith('#') and '=' in line:
        key, value = line.split('=', 1)
        env[key.strip()] = value.strip().strip('\"\'')
auth = base64.b64encode(('elastic:' + env['ELASTIC_PASSWORD']).encode()).decode()


def request(port, path, payload=None):
    headers = {'Authorization': 'Basic ' + auth, 'kbn-xsrf': 'true'}
    data = None
    if payload is not None:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(payload).encode()
    req = urllib.request.Request('http://127.0.0.1:' + port + path,
                                 data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=180) as response:
        return response.read()


files = {}
spaces = json.loads(request(env.get('KIBANA_PORT', '5601'), '/api/spaces/space'))
manifest = {'version': env.get('ELASTIC_VERSION'), 'spaces': []}
for space in spaces:
    space_id = space['id']
    prefix = '' if space_id == 'default' else '/s/' + urllib.parse.quote(space_id, safe='')
    data = request(env.get('KIBANA_PORT', '5601'), prefix + '/api/saved_objects/_export',
                   {'type': ['dashboard'], 'includeReferencesDeep': True})
    objects = [json.loads(line) for line in data.splitlines() if line.strip()]
    if any(obj.get('missingRefCount', 0) for obj in objects):
        raise RuntimeError('Missing dashboard references in space ' + space_id)
    filename = 'dashboards/' + urllib.parse.quote(space_id, safe='') + '.ndjson'
    files[filename] = data
    count = sum(obj.get('type') == 'dashboard' for obj in objects)
    manifest['spaces'].append({'id': space_id, 'name': space['name'],
                               'file': filename, 'dashboards': count})
    print('Exported space %s: %d dashboards' % (space_id, count), file=sys.stderr)

for name, endpoint in {
    'index-templates': '/_index_template',
    'component-templates': '/_component_template',
    'legacy-templates': '/_template',
    'ilm-policies': '/_ilm/policy',
    'ingest-pipelines': '/_ingest/pipeline',
    'indices': '/_cat/indices?format=json&h=index,docs.count,store.size',
    'node-settings': '/_nodes/settings?flat_settings=true',
}.items():
    files['elasticsearch/' + name + '.json'] = request(env.get('ES_PORT', '9200'), endpoint)
files['manifest.json'] = json.dumps(manifest, indent=2).encode()
# Build fully before sending, so an API failure produces no apparent valid archive.
buffer = io.BytesIO()
with tarfile.open(fileobj=buffer, mode='w:gz') as archive:
    for name, data in files.items():
        entry = tarfile.TarInfo(name)
        entry.size = len(data)
        entry.mode = 0o600
        archive.addfile(entry, io.BytesIO(data))
sys.stdout.buffer.write(buffer.getvalue())
