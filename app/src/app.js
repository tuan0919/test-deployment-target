import express from 'express';

export function createApp({ pool, version = 'dev' }) {
  const app = express();
  app.use(express.json());

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

  app.use((error, _request, response, _next) => {
    response.status(500).json({ error: 'database error' });
  });

  return app;
}
