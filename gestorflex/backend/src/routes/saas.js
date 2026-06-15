// src/routes/saas.js — Administração da plataforma SaaS
const router  = require('express').Router();
const bcrypt  = require('bcryptjs');
const { auth, superAdminOnly } = require('../middleware/auth');
const { query } = require('../db');

router.use(auth, superAdminOnly);

// ── DASHBOARD DA PLATAFORMA ────────────────────────────────────────

// GET /api/saas/dashboard
router.get('/dashboard', async (req, res) => {
  try {
    const stats = await query(`
      SELECT
        (SELECT COUNT(*) FROM Empresas)                                AS total_empresas,
        (SELECT COUNT(*) FROM Empresas WHERE ativo=TRUE)              AS empresas_ativas,
        (SELECT COUNT(*) FROM Empresas WHERE ativo=FALSE)             AS empresas_inativas,
        (SELECT COUNT(*) FROM Usuarios WHERE perfil != 'super_admin') AS total_usuarios,
        (SELECT COUNT(*) FROM Assinaturas
          WHERE status IN ('trial','ativo')
            AND (data_fim IS NULL OR data_fim > NOW()))               AS assinaturas_ativas,
        (SELECT COUNT(*) FROM Assinaturas WHERE status = 'suspenso')  AS assinaturas_suspensas,
        (SELECT COUNT(*) FROM Assinaturas WHERE status = 'cancelado') AS assinaturas_canceladas,
        (SELECT COUNT(*) FROM Empresas e
          WHERE NOT EXISTS (SELECT 1 FROM Assinaturas a WHERE a.empresa_id = e.id)) AS sem_assinatura
    `);

    const expirando = await query(`
      SELECT e.id, e.razao_social, a.status, a.data_fim, p.nome AS plano_nome
      FROM Assinaturas a
      JOIN Empresas e ON e.id = a.empresa_id
      JOIN Planos   p ON p.id = a.plano_id
      WHERE a.data_fim IS NOT NULL
        AND a.data_fim > NOW()
        AND a.data_fim <= NOW() + INTERVAL '30 days'
        AND a.status IN ('trial','ativo')
      ORDER BY a.data_fim ASC
      LIMIT 10
    `);

    const recentes = await query(`
      SELECT e.id, e.razao_social, e.cnpj, e.ativo, e.criado_em,
             a.status AS assinatura_status, p.nome AS plano_nome
      FROM Empresas e
      LEFT JOIN Assinaturas a ON a.empresa_id = e.id
      LEFT JOIN Planos      p ON p.id = a.plano_id
      ORDER BY e.criado_em DESC
      LIMIT 8
    `);

    res.json({
      ...stats.recordset[0],
      expirando: expirando.recordset,
      recentes:  recentes.recordset,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao carregar dashboard SaaS.' });
  }
});

// ── EMPRESAS / TENANTS ────────────────────────────────────────────

// GET /api/saas/empresas
router.get('/empresas', async (req, res) => {
  try {
    const r = await query(`
      SELECT e.id, e.razao_social, e.cnpj, e.email, e.telefone, e.ativo, e.criado_em,
             COUNT(DISTINCT u.id) AS qtd_usuarios,
             a.id AS assinatura_id, a.status AS assinatura_status,
             a.data_inicio, a.data_fim,
             p.id AS plano_id, p.nome AS plano_nome, p.preco_mensal
      FROM Empresas e
      LEFT JOIN Usuarios    u ON u.empresa_id = e.id AND u.perfil != 'super_admin'
      LEFT JOIN Assinaturas a ON a.empresa_id = e.id
      LEFT JOIN Planos      p ON p.id = a.plano_id
      GROUP BY e.id, e.razao_social, e.cnpj, e.email, e.telefone, e.ativo, e.criado_em,
               a.id, a.status, a.data_inicio, a.data_fim, p.id, p.nome, p.preco_mensal
      ORDER BY e.id DESC
    `);
    res.json(r.recordset);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao listar empresas.' });
  }
});

// POST /api/saas/empresas
router.post('/empresas', async (req, res) => {
  try {
    const { razao_social, cnpj, email, telefone, plano_id, admin_nome, admin_email, admin_senha } = req.body;
    if (!razao_social) return res.status(400).json({ error: 'Razão social obrigatória.' });

    const rEmp = await query(`
      INSERT INTO Empresas (razao_social, cnpj, email, telefone)
      VALUES (@razao_social, @cnpj, @email, @telefone)
      RETURNING id
    `, { razao_social, cnpj: cnpj||null, email: email||null, telefone: telefone||null });

    const novaEmpId = rEmp.recordset[0].id;

    if (plano_id) {
      await query(`
        INSERT INTO Assinaturas (empresa_id, plano_id, status, data_fim)
        VALUES (@emp, @plano, 'trial', NOW() + INTERVAL '30 days')
      `, { emp: novaEmpId, plano: parseInt(plano_id) });
    }

    if (admin_nome && admin_email && admin_senha) {
      if (admin_senha.length < 6) return res.status(400).json({ error: 'Senha mínimo 6 caracteres.' });
      const hash = await bcrypt.hash(admin_senha, 10);
      await query(`
        INSERT INTO Usuarios (empresa_id, nome, email, senha_hash, perfil)
        VALUES (@emp, @nome, @email, @hash, 'admin')
      `, { emp: novaEmpId, nome: admin_nome, email: admin_email, hash });
    }

    res.status(201).json({ id: novaEmpId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao criar empresa.' });
  }
});

// PUT /api/saas/empresas/:id
router.put('/empresas/:id', async (req, res) => {
  try {
    const { razao_social, cnpj, email, telefone } = req.body;
    if (!razao_social) return res.status(400).json({ error: 'Razão social obrigatória.' });

    await query(`
      UPDATE Empresas
      SET razao_social=@razao_social, cnpj=@cnpj, email=@email, telefone=@telefone
      WHERE id=@id
    `, { razao_social, cnpj: cnpj||null, email: email||null, telefone: telefone||null, id: parseInt(req.params.id) });

    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao atualizar empresa.' });
  }
});

// PATCH /api/saas/empresas/:id/toggle
router.patch('/empresas/:id/toggle', async (req, res) => {
  try {
    await query(
      'UPDATE Empresas SET ativo = NOT ativo WHERE id=@id',
      { id: parseInt(req.params.id) }
    );
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao alterar status.' });
  }
});

// ── ASSINATURAS ───────────────────────────────────────────────────

// POST /api/saas/assinaturas
router.post('/assinaturas', async (req, res) => {
  try {
    const { empresa_id, plano_id, status, data_fim } = req.body;
    if (!empresa_id || !plano_id) return res.status(400).json({ error: 'Empresa e plano são obrigatórios.' });

    const existing = await query(
      'SELECT id FROM Assinaturas WHERE empresa_id=@emp',
      { emp: parseInt(empresa_id) }
    );

    if (existing.recordset.length > 0) {
      await query(`
        UPDATE Assinaturas
        SET plano_id=@plano, status=@status, data_fim=@fim
        WHERE empresa_id=@emp
      `, {
        plano: parseInt(plano_id),
        status: status || 'ativo',
        fim: data_fim || null,
        emp: parseInt(empresa_id),
      });
    } else {
      await query(`
        INSERT INTO Assinaturas (empresa_id, plano_id, status, data_fim)
        VALUES (@emp, @plano, @status, @fim)
      `, {
        emp:    parseInt(empresa_id),
        plano:  parseInt(plano_id),
        status: status || 'trial',
        fim:    data_fim || null,
      });
    }

    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao salvar assinatura.' });
  }
});

// ── PLANOS ────────────────────────────────────────────────────────

// GET /api/saas/planos
router.get('/planos', async (req, res) => {
  try {
    const r = await query(`
      SELECT p.id, p.nome, p.descricao, p.preco_mensal, p.max_usuarios, p.max_produtos, p.ativo, p.criado_em,
             COUNT(a.id) AS qtd_assinantes
      FROM Planos p
      LEFT JOIN Assinaturas a ON a.plano_id = p.id AND a.status IN ('trial','ativo')
      GROUP BY p.id, p.nome, p.descricao, p.preco_mensal, p.max_usuarios, p.max_produtos, p.ativo, p.criado_em
      ORDER BY p.preco_mensal ASC
    `);
    res.json(r.recordset);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao listar planos.' });
  }
});

// POST /api/saas/planos
router.post('/planos', async (req, res) => {
  try {
    const { nome, descricao, preco_mensal, max_usuarios, max_produtos } = req.body;
    if (!nome) return res.status(400).json({ error: 'Nome do plano obrigatório.' });

    const r = await query(`
      INSERT INTO Planos (nome, descricao, preco_mensal, max_usuarios, max_produtos)
      VALUES (@nome, @desc, @preco, @max_u, @max_p)
      RETURNING id
    `, {
      nome,
      desc:  descricao || null,
      preco: parseFloat(preco_mensal) || 0,
      max_u: parseInt(max_usuarios) || 5,
      max_p: parseInt(max_produtos) || 100,
    });

    res.status(201).json({ id: r.recordset[0].id });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao criar plano.' });
  }
});

// PUT /api/saas/planos/:id
router.put('/planos/:id', async (req, res) => {
  try {
    const { nome, descricao, preco_mensal, max_usuarios, max_produtos } = req.body;
    if (!nome) return res.status(400).json({ error: 'Nome do plano obrigatório.' });

    await query(`
      UPDATE Planos
      SET nome=@nome, descricao=@desc, preco_mensal=@preco, max_usuarios=@max_u, max_produtos=@max_p
      WHERE id=@id
    `, {
      nome,
      desc:  descricao || null,
      preco: parseFloat(preco_mensal) || 0,
      max_u: parseInt(max_usuarios) || 5,
      max_p: parseInt(max_produtos) || 100,
      id:    parseInt(req.params.id),
    });

    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao atualizar plano.' });
  }
});

// PATCH /api/saas/planos/:id/toggle
router.patch('/planos/:id/toggle', async (req, res) => {
  try {
    await query(
      'UPDATE Planos SET ativo = NOT ativo WHERE id=@id',
      { id: parseInt(req.params.id) }
    );
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao alterar status do plano.' });
  }
});

module.exports = router;
