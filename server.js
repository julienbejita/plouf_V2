import express from 'express';
import { open } from 'sqlite';
import sqlite3 from 'sqlite3';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const uid = () => Math.random().toString(36).slice(2, 10);

async function createDb() {
  const db = await open({
    filename: path.join(__dirname, 'players.db'),
    driver: sqlite3.Database,
  });
  await db.exec(`CREATE TABLE IF NOT EXISTS players (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    present INTEGER NOT NULL
  )`);
  const row = await db.get('SELECT COUNT(*) AS c FROM players');
  if (row.c === 0) {
    const defaults = ['Alice', 'Bob', 'Charly', 'Dora'];
    for (const name of defaults) {
      await db.run('INSERT INTO players(id, name, present) VALUES(?,?,1)', uid(), name);
    }
  }
  return db;
}

const db = await createDb();

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'dist')));

app.get('/api/players', async (req, res) => {
  const players = await db.all('SELECT id, name, present FROM players');
  res.json(players.map(p => ({ ...p, present: !!p.present })));
});

app.post('/api/players', async (req, res) => {
  const { id = uid(), name, present = true } = req.body;
  if (!name) return res.status(400).json({ error: 'name required' });
  await db.run('INSERT INTO players(id, name, present) VALUES(?,?,?)', id, name, present ? 1 : 0);
  res.json({ id, name, present });
});

app.patch('/api/players/:id', async (req, res) => {
  const { id } = req.params;
  const existing = await db.get('SELECT * FROM players WHERE id = ?', id);
  if (!existing) return res.status(404).end();
  const name = req.body.name ?? existing.name;
  const present = req.body.present ?? !!existing.present;
  await db.run('UPDATE players SET name = ?, present = ? WHERE id = ?', name, present ? 1 : 0, id);
  res.json({ id, name, present });
});

app.delete('/api/players/:id', async (req, res) => {
  await db.run('DELETE FROM players WHERE id = ?', req.params.id);
  res.status(204).end();
});

app.post('/api/players/toggleAll', async (req, res) => {
  const { present } = req.body;
  await db.run('UPDATE players SET present = ?', present ? 1 : 0);
  const players = await db.all('SELECT id, name, present FROM players');
  res.json(players.map(p => ({ ...p, present: !!p.present })));
});

app.put('/api/players', async (req, res) => {
  if (!Array.isArray(req.body)) return res.status(400).end();
  await db.exec('DELETE FROM players');
  const stmt = await db.prepare('INSERT INTO players(id, name, present) VALUES(?,?,?)');
  try {
    for (const p of req.body) {
      await stmt.run(p.id, p.name, p.present ? 1 : 0);
    }
  } finally {
    await stmt.finalize();
  }
  res.status(204).end();
});

app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'dist', 'index.html'));
});

const port = process.env.PORT || 80;
app.listen(port, () => {
  console.log(`Server listening on port ${port}`);
});
