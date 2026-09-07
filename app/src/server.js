import pg from 'pg';
import { createApp } from './app.js';

const { Pool } = pg;
const port = Number(process.env.PORT || 8080);
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

await pool.query(`
  CREATE TABLE IF NOT EXISTS notes (
    id BIGSERIAL PRIMARY KEY,
    text TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )
`);

const app = createApp({ pool, version: process.env.APP_VERSION || 'dev' });
const server = app.listen(port, () => console.log(`notes API listening on ${port}`));

async function close() {
  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
}

process.on('SIGTERM', close);
process.on('SIGINT', close);
