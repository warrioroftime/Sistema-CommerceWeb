// src/routes/contas-receber.js
const router = require('express').Router();
const { query } = require('../db');
const { auth } = require('../middleware/auth');

// GET /api/contas-receber?status=&cliente_id=&de=&ate=&page=1&limit=100
router.get('/', auth, async (req, res) => {
  try {
    const emp = req.user.empresa_id;
    const { status = '', cliente_id = '', de = '', ate = '', page = 1, limit = 100 } = req.query;

    let where = `cr.empresa_id = @emp`;
    const params = { emp };

    if (status)     { where += ` AND cr.status = @st`;       params.st  = status; }
    if (cliente_id) { where += ` AND cr.cliente_id = @cid`;  params.cid = parseInt(cliente_id); }
    if (de)         { where += ` AND cr.criado_em >= @de`;   params.de  = new Date(de + 'T00:00:00'); }
    if (ate)        { where += ` AND cr.criado_em <= @ate`;  params.ate = new Date(ate + 'T23:59:59'); }

    const offset = (parseInt(page) - 1) * parseInt(limit);

    const r = await query(`
      SELECT cr.id, cr.venda_id, cr.parcela_num, cr.parcelas_total,
             cr.valor, cr.data_vencimento, cr.status, cr.data_recebimento, cr.valor_recebido,
             cr.observacao, cr.criado_em,
             c.id   AS cliente_id,
             c.nome AS cliente_nome,
             c.telefone AS cliente_tel
      FROM ContasReceber cr
      LEFT JOIN Clientes c ON c.id = cr.cliente_id
      WHERE ${where}
      ORDER BY
        CASE cr.status WHEN 'pendente' THEN 0 ELSE 1 END,
        cr.data_vencimento ASC,
        cr.criado_em DESC
      LIMIT ${parseInt(limit)} OFFSET ${offset}
    `, params);

    const tot = await query(`
      SELECT
        COUNT(*) AS n,
        COALESCE(SUM(CASE WHEN cr.status='pendente' THEN cr.valor ELSE 0 END),0) AS total_pendente,
        COALESCE(SUM(CASE WHEN cr.status='recebido' THEN cr.valor ELSE 0 END),0) AS total_recebido
      FROM ContasReceber cr
      LEFT JOIN Clientes c ON c.id = cr.cliente_id
      WHERE ${where}
    `, params);

    res.json({
      data:           r.recordset,
      total:          parseInt(tot.recordset[0].n),
      total_pendente: parseFloat(tot.recordset[0].total_pendente),
      total_recebido: parseFloat(tot.recordset[0].total_recebido),
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao listar contas a receber.' });
  }
});

// PUT /api/contas-receber/:id/receber
router.put('/:id/receber', auth, async (req, res) => {
  try {
    const id  = parseInt(req.params.id);
    const emp = req.user.empresa_id;
    const { valor_recebido, observacao } = req.body;

    const rec = await query(
      `SELECT id, valor, status FROM ContasReceber WHERE id=@id AND empresa_id=@emp`,
      { id, emp }
    );
    if (!rec.recordset[0]) return res.status(404).json({ error: 'Registro não encontrado.' });
    if (rec.recordset[0].status === 'recebido')
      return res.status(400).json({ error: 'Esta parcela já foi recebida.' });

    const val = parseFloat(valor_recebido) || parseFloat(rec.recordset[0].valor);
    await query(
      `UPDATE ContasReceber
       SET status='recebido', data_recebimento=NOW(), valor_recebido=@vr,
           observacao=COALESCE(@obs, observacao)
       WHERE id=@id AND empresa_id=@emp`,
      { id, emp, vr: val, obs: observacao || null }
    );
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao registrar recebimento.' });
  }
});

// PUT /api/contas-receber/:id/cancelar
router.put('/:id/cancelar', auth, async (req, res) => {
  try {
    const id  = parseInt(req.params.id);
    const emp = req.user.empresa_id;
    await query(
      `UPDATE ContasReceber SET status='cancelado' WHERE id=@id AND empresa_id=@emp`,
      { id, emp }
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: 'Erro ao cancelar.' });
  }
});

module.exports = router;
