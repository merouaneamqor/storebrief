import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';

function runtime() {
  const buckets = new Map();
  const origin = 'https://vazivo.test';
  const key = request => typeof request === 'string' ? new URL(request, origin).href : request.url;
  const caches = {
    async open(name) {
      if (!buckets.has(name)) buckets.set(name, new Map());
      const data = buckets.get(name);
      return {
        async put(request, response) { data.set(key(request), response.clone()); },
        async match(request) { return data.get(key(request))?.clone(); },
        async delete(request) { return data.delete(key(request)); },
        async keys() { return [...data.keys()].map(url => new Request(url)); },
      };
    },
    async keys() { return [...buckets.keys()]; },
    async delete(name) { return buckets.delete(name); },
  };
  let network;
  const context = vm.createContext({ caches, Request, Response, Headers, URL, crypto: webcrypto, Date,
    self: { location: { origin }, addEventListener() {} }, fetch: request => network(request) });
  const source = fs.readFileSync(new URL('../../app/views/pwa/service-worker.js.erb', import.meta.url), 'utf8').replace(/<%=[\s\S]*?%>/, '{ en: "Unavailable offline", fr: "Indisponible" }');
  vm.runInContext(source, context);
  const handle = vm.runInContext('handle', context);
  const state = () => vm.runInContext('state', context);
  const response = (path, owner, body = owner || 'asset', session = owner) => {
    const result = new Response(body, { headers: { 'Content-Type': path.startsWith('/assets/') ? 'text/javascript' : 'text/html',
      ...(owner ? { 'X-Vazivo-Offline-Owner': owner, 'X-Vazivo-Offline-Session': session } : {}) } });
    Object.defineProperty(result, 'url', { value: origin + path }); return result;
  };
  return { buckets, state, response, setNetwork(callback) { network = callback; },
    handle(path, method = 'GET') { return handle(new Request(origin + path, { method, headers: { Accept: 'text/html' } })); } };
}

test('late old-owner response cannot enter another owner cache; logout removes private pages', async () => {
  const app = runtime();
  app.setNetwork(async () => app.response('/inbox', '1:10', 'Private A'));
  await app.handle('/inbox');
  let release;
  app.setNetwork(() => new Promise(resolve => { release = resolve; }));
  const late = app.handle('/inbox/1');
  while (!release) await new Promise(resolve => setImmediate(resolve));
  app.setNetwork(async () => app.response('/app', '2:20', 'Private B'));
  await app.handle('/login', 'POST');
  release(app.response('/inbox/1', '1:10', 'Late secret A'));
  await late;
  assert.equal(app.state().owner, '2:20');
  app.setNetwork(async () => { throw new Error('Offline'); });
  assert.equal((await app.handle('/inbox/1')).status, 503);
  app.setNetwork(async () => app.response('/inbox', '2:20', 'Private B'));
  await app.handle('/inbox');
  app.setNetwork(async () => { throw new Error('Offline'); });
  assert.equal(await (await app.handle('/inbox')).text(), 'Private B');
  await app.handle('/logout', 'DELETE');
  assert.equal((await app.handle('/inbox')).status, 503);
});

test('only allowlisted HTML is cached, with bounded size and expiry; assets remain public', async () => {
  const app = runtime();
  app.setNetwork(async request => app.response(new URL(request.url).pathname, '1:10'));
  for (const path of ['/billing', '/admin', '/offline_context', '/rails/active_storage/blobs/private']) await app.handle(path);
  for (let id = 0; id < 45; id++) await app.handle('/inbox/' + id);
  const privateBuckets = [...app.buckets].filter(([name]) => name.startsWith('vazivo-private-'));
  assert.equal(privateBuckets.length, 1);
  assert.equal(privateBuckets[0][1].size, 40);
  assert([...privateBuckets[0][1].keys()].every(url => /\/inbox\/\d+$/.test(url)));
  const [url, cached] = [...privateBuckets[0][1]].at(-1);
  const headers = new Headers(cached.headers); headers.set('X-Vazivo-Cached-At', '1');
  privateBuckets[0][1].set(url, new Response('Expired secret', { headers }));
  app.setNetwork(async () => { throw new Error('Offline'); });
  assert.equal((await app.handle(new URL(url).pathname)).status, 503);
  app.setNetwork(async request => app.response(new URL(request.url).pathname, null, 'Public script'));
  await app.handle('/assets/application-12345678.js');
  app.setNetwork(async () => { throw new Error('Offline'); });
  assert.equal(await (await app.handle('/assets/application-12345678.js')).text(), 'Public script');
});
