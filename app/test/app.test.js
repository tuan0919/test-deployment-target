import test from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../src/app.js';

function createPool({ rows = [], error } = {}) {
  return {
    async query() {
      if (error) throw error;
      return { rows };
    }
  };
}

test('returns the deployed immutable version', async () => {
  const response = await request(createApp({ pool: createPool(), version: 'abc123' }))
    .get('/version')
    .expect(200);

  assert.deepEqual(response.body, { version: 'abc123' });
});

test('reports healthy when PostgreSQL accepts a query', async () => {
  const response = await request(createApp({ pool: createPool() }))
    .get('/health')
    .expect(200);

  assert.deepEqual(response.body, { status: 'ok' });
});

test('reports unavailable when PostgreSQL rejects a health query', async () => {
  const response = await request(createApp({ pool: createPool({ error: new Error('connection refused') }) }))
    .get('/health')
    .expect(503);

  assert.deepEqual(response.body, { status: 'error' });
});

test('rejects a note without text', async () => {
  const response = await request(createApp({ pool: createPool() }))
    .post('/notes')
    .send({ text: '   ' })
    .expect(400);

  assert.deepEqual(response.body, { error: 'text is required' });
});

test('creates and returns a trimmed persisted note', async () => {
  const note = { id: 7, text: 'before-v1.2', created_at: '2026-09-07T00:00:00.000Z' };
  const response = await request(createApp({ pool: createPool({ rows: [note] }) }))
    .post('/notes')
    .send({ text: '  before-v1.2  ' })
    .expect(201);

  assert.deepEqual(response.body, note);
});

test('lists persisted notes newest first', async () => {
  const notes = [
    { id: 2, text: 'new', created_at: '2026-09-07T00:01:00.000Z' },
    { id: 1, text: 'old', created_at: '2026-09-07T00:00:00.000Z' }
  ];
  const response = await request(createApp({ pool: createPool({ rows: notes }) }))
    .get('/notes')
    .expect(200);

  assert.deepEqual(response.body, notes);
});
