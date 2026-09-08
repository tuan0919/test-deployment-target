import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const publicDirectory = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'public');

export function createApp({ pool, version = 'dev' }) {
  const app = express();
  app.use(express.json());
  app.use(express.static(publicDirectory));

  app.get('/health', async (_request, response) => {
    try {
      await pool.query('SELECT 1');
      response.json({ status: 'ok' });
    } catch {
      response.status(503).json({ status: 'error' });
    }
  });

  app.get('/version', (_request, response) => {
    response.json({ version });
  });

  app.get('/notes', async (_request, response, next) => {
    try {
      const result = await pool.query('SELECT id, text, created_at FROM notes ORDER BY created_at DESC');
      response.json(result.rows);
    } catch (error) {
      next(error);
    }
  });

  app.post('/notes', async (request, response, next) => {
    const text = typeof request.body?.text === 'string' ? request.body.text.trim() : '';
    if (!text) {
      response.status(400).json({ error: 'text is required' });
      return;
    }

    try {
      const result = await pool.query(
        'INSERT INTO notes(text) VALUES ($1) RETURNING id, text, created_at',
        [text]
      );
      response.status(201).json(result.rows[0]);
    } catch (error) {
      next(error);
    }
  });

  app.patch('/notes/:id', async (request, response, next) => {
    const id = Number(request.params.id);
    const text = typeof request.body?.text === 'string' ? request.body.text.trim() : '';
    if (!Number.isInteger(id) || id < 1 || !text) {
      response.status(400).json({ error: 'valid id and text are required' });
      return;
    }

    try {
      const result = await pool.query(
        'UPDATE notes SET text = $1 WHERE id = $2 RETURNING id, text, created_at',
        [text, id]
      );
      if (!result.rows[0]) {
        response.status(404).json({ error: 'note not found' });
        return;
      }
      response.json(result.rows[0]);
    } catch (error) {
      next(error);
    }
  });

  app.delete('/notes/:id', async (request, response, next) => {
    const id = Number(request.params.id);
    if (!Number.isInteger(id) || id < 1) {
      response.status(400).json({ error: 'valid id is required' });
      return;
    }

    try {
      const result = await pool.query('DELETE FROM notes WHERE id = $1 RETURNING id', [id]);
      if (!result.rows[0]) {
        response.status(404).json({ error: 'note not found' });
        return;
      }
      response.status(204).end();
    } catch (error) {
      next(error);
    }
  });

  app.use((error, _request, response, _next) => {
    response.status(500).json({ error: 'database error' });
  });

  return app;
}
