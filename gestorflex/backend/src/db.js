// src/db.js — Conexão com PostgreSQL via pg
const { Pool } = require('pg');

const pool = new Pool({
  host:     process.env.DB_SERVER   || 'localhost',
  port:     parseInt(process.env.DB_PORT) || 5432,
  database: process.env.DB_NAME     || 'commerceweb',
  user:     process.env.DB_USER     || 'sa',
  password: process.env.DB_PASSWORD || 'Server123!',
  max: 10,
  idleTimeoutMillis: 30000,
});

// Converte @param nomeados para $1 posicionais do PostgreSQL
// Suporta o mesmo param repetido no mesmo SQL (mapeia para o mesmo $n)
function namedToPositional(text, params = {}) {
  const values = [];
  const nameToIdx = {};
  const sql = text.replace(/@(\w+)/g, (_, name) => {
    if (!(name in nameToIdx)) {
      values.push(params[name] !== undefined ? params[name] : null);
      nameToIdx[name] = values.length;
    }
    return '$' + nameToIdx[name];
  });
  return { sql, values };
}

// Query padrão com params nomeados — retorna { recordset, rowCount }
async function query(text, params = {}) {
  const { sql, values } = namedToPositional(text, params);
  const result = await pool.query(sql, values);
  return {
    recordset: result.rows,
    rowCount:  result.rowCount,
  };
}

// Executa um callback dentro de uma transação PostgreSQL
// O callback recebe `tq` — função de query com mesma assinatura que `query`
async function withTransaction(callback) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const tq = async (text, params = {}) => {
      const { sql, values } = namedToPositional(text, params);
      const r = await client.query(sql, values);
      return { recordset: r.rows, rowCount: r.rowCount };
    };
    const result = await callback(tq);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// Testa a conexão e retorna o pool (compatibilidade com app.js)
async function getPool() {
  await pool.query('SELECT 1');
  console.log('✅ PostgreSQL conectado:', process.env.DB_SERVER || 'localhost', '/', process.env.DB_NAME || 'commerceweb');
  return pool;
}

module.exports = { query, withTransaction, getPool };
