// src/routes/relatorios.js
const router = require('express').Router();
const { query } = require('../db');
const { auth } = require('../middleware/auth');

// GET /api/relatorios/dashboard?periodo=30
router.get('/dashboard', auth, async (req, res) => {
  try {
    const dias   = parseInt(req.query.periodo) || 30;
    const emp    = req.user.empresa_id;
    const cutoff = new Date(Date.now() - dias * 24 * 3600 * 1000);

    const kpis = await query(`
      SELECT
        COUNT(*)                    AS qtd_vendas,
        COALESCE(SUM(total), 0)     AS faturamento,
        COALESCE(AVG(total), 0)     AS ticket_medio,
        COALESCE(SUM(desconto), 0)  AS total_descontos
      FROM Vendas
      WHERE empresa_id = @emp AND criado_em >= @cutoff
    `, { emp, cutoff });

    const estoque = await query(`
      SELECT
        COALESCE(SUM(estoque), 0)                                           AS total_itens,
        SUM(CASE WHEN estoque = 0 THEN 1 ELSE 0 END)                        AS em_falta,
        SUM(CASE WHEN estoque > 0 AND estoque <= estoque_min THEN 1 ELSE 0 END) AS critico
      FROM Produtos WHERE empresa_id=@emp AND status='ativo'
    `, { emp });

    const topProd = await query(`
      SELECT p.descricao, SUM(iv.quantidade) AS qtd_vendida
      FROM ItensVenda iv
      JOIN Produtos p ON p.id  = iv.produto_id
      JOIN Vendas   v ON v.id  = iv.venda_id
      WHERE v.empresa_id = @emp AND v.criado_em >= @cutoff
      GROUP BY p.id, p.descricao
      ORDER BY qtd_vendida DESC
      LIMIT 6
    `, { emp, cutoff });

    const ultimasVendas = await query(`
      SELECT v.id, v.criado_em, v.total, fp.nome AS pagamento,
             COALESCE(c.nome, 'Consumidor') AS cliente,
             (SELECT COUNT(*) FROM ItensVenda WHERE venda_id=v.id) AS qtd_itens
      FROM Vendas v
      LEFT JOIN Clientes c ON c.id=v.cliente_id
      LEFT JOIN FormasPagamento fp ON fp.id=v.forma_pagamento_id
      WHERE v.empresa_id=@emp
      ORDER BY v.criado_em DESC
      LIMIT 5
    `, { emp });

    const alertas = await query(`
      SELECT id, codigo, descricao, estoque, estoque_min,
        CASE WHEN estoque=0 THEN 'falta' ELSE 'critico' END AS tipo
      FROM Produtos
      WHERE empresa_id=@emp AND status='ativo' AND estoque <= estoque_min
      ORDER BY estoque ASC
      LIMIT 10
    `, { emp });

    res.json({
      kpis:           kpis.recordset[0],
      estoque:        estoque.recordset[0],
      top_produtos:   topProd.recordset,
      ultimas_vendas: ultimasVendas.recordset,
      alertas:        alertas.recordset,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao gerar dashboard.' });
  }
});

// GET /api/relatorios/vendas?de=&ate=
router.get('/vendas', auth, async (req, res) => {
  try {
    const emp = req.user.empresa_id;
    const de  = req.query.de  || new Date(Date.now() - 30 * 86400000).toISOString().split('T')[0];
    const ate = req.query.ate || new Date().toISOString().split('T')[0];
    const deD  = new Date(de  + 'T00:00:00');
    const ateD = new Date(ate + 'T23:59:59');

    const porPgto = await query(`
      SELECT fp.nome AS pagamento, COUNT(*) AS qtd, SUM(v.total) AS total
      FROM Vendas v
      JOIN FormasPagamento fp ON fp.id=v.forma_pagamento_id
      WHERE v.empresa_id=@emp AND v.criado_em BETWEEN @de AND @ate
      GROUP BY fp.nome
      ORDER BY total DESC
    `, { emp, de: deD, ate: ateD });

    const topProd = await query(`
      SELECT p.descricao, SUM(iv.quantidade) AS qtd_vendida, SUM(iv.subtotal) AS faturado
      FROM ItensVenda iv
      JOIN Produtos p ON p.id=iv.produto_id
      JOIN Vendas   v ON v.id=iv.venda_id
      WHERE v.empresa_id=@emp AND v.criado_em BETWEEN @de AND @ate
      GROUP BY p.id, p.descricao
      ORDER BY qtd_vendida DESC
      LIMIT 5
    `, { emp, de: deD, ate: ateD });

    const resumo = await query(`
      SELECT
        COUNT(*)                    AS qtd_vendas,
        COALESCE(SUM(total),0)      AS faturamento,
        COALESCE(SUM(desconto),0)   AS total_descontos,
        COALESCE(AVG(total),0)      AS ticket_medio,
        (SELECT COALESCE(SUM(iv.quantidade),0)
         FROM ItensVenda iv
         JOIN Vendas v2 ON v2.id = iv.venda_id
         WHERE v2.empresa_id=@emp AND v2.criado_em BETWEEN @de AND @ate) AS itens_vendidos
      FROM Vendas v
      WHERE empresa_id=@emp AND criado_em BETWEEN @de AND @ate
    `, { emp, de: deD, ate: ateD });

    const extrato = await query(`
      SELECT
        criado_em::DATE AS data,
        COUNT(*)        AS qtd_vendas,
        SUM(total)      AS total,
        (SELECT SUM(iv.quantidade)
         FROM ItensVenda iv
         JOIN Vendas v2 ON v2.id=iv.venda_id
         WHERE v2.empresa_id=@emp AND v2.criado_em::DATE = v.criado_em::DATE) AS itens_vendidos
      FROM Vendas v
      WHERE empresa_id=@emp AND criado_em BETWEEN @de AND @ate
      GROUP BY criado_em::DATE
      ORDER BY data DESC
    `, { emp, de: deD, ate: ateD });

    res.json({
      por_pagamento: porPgto.recordset,
      top_produtos:  topProd.recordset,
      resumo:        resumo.recordset[0],
      extrato:       extrato.recordset,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao gerar relatório.' });
  }
});

module.exports = router;
