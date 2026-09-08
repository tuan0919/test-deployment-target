import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { JSDOM } from 'jsdom';
import { mountNotesUi } from '../public/app.js';

const html = await readFile(new URL('../public/index.html', import.meta.url), 'utf8');

function jsonResponse(body, status = 200) {
  return { ok: status >= 200 && status < 300, status, json: async () => body };
}

async function settle() {
  await new Promise((resolve) => setImmediate(resolve));
  await new Promise((resolve) => setImmediate(resolve));
}

test('submits a new note and renders its persistent text', async () => {
  const dom = new JSDOM(html, { url: 'http://notes.test/' });
  const calls = [];
  const note = { id: 1, text: 'state before v1.2', created_at: '2026-09-08T00:00:00.000Z' };
  const fetchFn = async (url, options = {}) => {
    calls.push({ url, options });
    if (url === '/version') return jsonResponse({ version: 'v1.1' });
    if (url === '/notes' && options.method === 'POST') return jsonResponse(note, 201);
    if (url === '/notes') return jsonResponse(calls.some((call) => call.options.method === 'POST') ? [note] : []);
    throw new Error(`unexpected request: ${url}`);
  };

  mountNotesUi({ document: dom.window.document, fetchFn });
  await settle();
  const text = dom.window.document.querySelector('#note-text');
  text.value = note.text;
  dom.window.document.querySelector('#note-form').dispatchEvent(new dom.window.Event('submit', { bubbles: true, cancelable: true }));
  await settle();

  assert.equal(calls.find((call) => call.options.method === 'POST').options.body, JSON.stringify({ text: note.text }));
  assert.match(dom.window.document.querySelector('#notes-list').textContent, /state before v1\.2/);
  assert.match(dom.window.document.querySelector('#deployment-version').textContent, /v1\.1/);
});
