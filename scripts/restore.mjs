import { readFileSync, readdirSync } from 'node:fs';

const root = '/restore';
const auth = 'Basic ' + Buffer.from('elastic:' + process.env.ELASTIC_PASSWORD).toString('base64');
async function api(base, path, method, body) {
  const headers = { Authorization: auth, 'kbn-xsrf': 'true' };
  if (!(body instanceof FormData) && body !== undefined) {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(body);
  }
  const response = await fetch(base + path, {
    method, headers, body, signal: AbortSignal.timeout(180000),
  });
  if (!response.ok) throw new Error(`${method} ${path}: HTTP ${response.status} ${(await response.text()).slice(0, 500)}`);
  return response.json();
}
const es = 'http://elasticsearch:9200';
const kb = 'http://kibana:5601';
const load = path => JSON.parse(readFileSync(root + path, 'utf8'));

await api(es, '/_ilm/policy/winlogbeat-policy', 'PUT', load('/config/elasticsearch/winlogbeat-policy.json'));
const pipelines = new Map(readdirSync(root + '/config/elasticsearch/pipelines')
  .filter(name => name.endsWith('.json'))
  .map(name => [name.slice(0, -5), load('/config/elasticsearch/pipelines/' + name)]));
const done = new Set();
const active = new Set();
function dependencies(value, found = new Set()) {
  if (Array.isArray(value)) value.forEach(child => dependencies(child, found));
  else if (value && typeof value === 'object') {
    if (value.pipeline?.name) found.add(value.pipeline.name);
    Object.values(value).forEach(child => dependencies(child, found));
  }
  return found;
}
async function putPipeline(name) {
  if (done.has(name)) return;
  if (!pipelines.has(name)) throw new Error('Missing pipeline dependency: ' + name);
  if (active.has(name)) throw new Error('Pipeline dependency cycle: ' + name);
  active.add(name);
  for (const dependency of dependencies(pipelines.get(name))) await putPipeline(dependency);
  await api(es, '/_ingest/pipeline/' + encodeURIComponent(name), 'PUT', pipelines.get(name));
  active.delete(name);
  done.add(name);
}
for (const name of pipelines.keys()) await putPipeline(name);
await api(es, '/_index_template/winlogbeat', 'PUT', load('/config/elasticsearch/winlogbeat-template.json'));

// Conflicts stop the import. An operator can explicitly opt into overwriting on retry.
const form = new FormData();
form.append('file', new Blob([readFileSync(root + '/dashboards/default.ndjson')],
  { type: 'application/ndjson' }), 'default.ndjson');
const overwrite = process.env.RESTORE_OVERWRITE === '1' ? '?overwrite=true' : '';
const result = await api(kb, '/api/saved_objects/_import' + overwrite, 'POST', form);
if (!result.success) {
  throw new Error('Dashboard import needs attention: ' + JSON.stringify(result.errors).slice(0, 2000));
}
console.log(`Restored 60-day policy, ${done.size} pipelines, Winlogbeat template, and ${result.successCount} saved objects.`);
