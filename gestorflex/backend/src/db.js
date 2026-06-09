// src/db.js — Conexão com SQL Server via mssql (driver msnodesqlv8)
const sql = require('mssql/msnodesqlv8');

const server   = process.env.DB_SERVER   || '.\\SQLEXPRESS';
const database = process.env.DB_NAME     || 'GestorFlex';
const user     = process.env.DB_USER     || 'sa';
const password = process.env.DB_PASSWORD || '';

const config = {
  connectionString: `Driver={ODBC Driver 17 for SQL Server};Server=${server};Database=${database};UID=${user};PWD=${password};`,
  pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
};

let pool = null;

async function getPool() {
  if (!pool) {
    pool = await sql.connect(config);
    console.log('✅ SQL Server conectado:', server, '/', database);
  }
  return pool;
}

// Atalhos para queries parametrizadas
async function query(text, params = {}) {
  const p = await getPool();
  const req = p.request();
  for (const [key, val] of Object.entries(params)) {
    req.input(key, val);
  }
  return req.query(text);
}

async function queryTyped(text, params = []) {
  // params = [{ name, type, value }]
  const p = await getPool();
  const req = p.request();
  for (const { name, type, value } of params) {
    req.input(name, type, value);
  }
  return req.query(text);
}

module.exports = { sql, getPool, query, queryTyped };
