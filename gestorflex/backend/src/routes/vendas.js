// src/routes/vendas.js
const router = require('express').Router();
const { query, withTransaction } = require('../db');
const { auth } = require('../middleware/auth');

// GET /api/vendas?de=&ate=&pagamento=&cliente_id=&busca=&page=1&limit=50
router.get('/', auth, async (req, res) => {
  try {
    const { de, ate, pagamento, cliente_id, busca = '', page = 1, limit = 100 } = req.query;
    let where = `v.empresa_id = @emp`;
    const params = { emp: req.user.empresa_id };

    if (de)         { where += ` AND v.criado_em >= @de`;   params.de  = new Date(de + 'T00:00:00'); }
    if (ate)        { where += ` AND v.criado_em <= @ate`;  params.ate = new Date(ate + 'T23:59:59'); }
    if (pagamento)  { where += ` AND fp.nome = @pgto`;      params.pgto = pagamento; }
    if (cliente_id) { where += ` AND v.cliente_id = @cid`;  params.cid  = parseInt(cliente_id); }
    if (busca)      { where += ` AND (CAST(v.id AS TEXT) ILIKE @b OR c.nome ILIKE @b)`; params.b = `%${busca}%`; }

    const offset = (parseInt(page) - 1) * parseInt(limit);

    const r = await query(`
      SELECT v.id, v.criado_em, v.subtotal, v.desconto, v.total, v.observacao,
             fp.nome AS pagamento,
             c.id   AS cliente_id,
             c.nome AS cliente_nome,
             (SELECT COUNT(*) FROM ItensVenda WHERE venda_id = v.id) AS qtd_itens
      FROM Vendas v
      LEFT JOIN Clientes          c  ON c.id  = v.cliente_id
      LEFT JOIN FormasPagamento   fp ON fp.id = v.forma_pagamento_id
      WHERE ${where}
      ORDER BY v.criado_em DESC
      LIMIT ${parseInt(limit)} OFFSET ${offset}
    `, params);

    const tot = await query(
      `SELECT COUNT(*) AS n FROM Vendas v
       LEFT JOIN Clientes c ON c.id=v.cliente_id
       LEFT JOIN FormasPagamento fp ON fp.id=v.forma_pagamento_id
       WHERE ${where}`, params
    );

    res.json({ data: r.recordset, total: parseInt(tot.recordset[0].n) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao listar vendas.' });
  }
});

// GET /api/vendas/:id
router.get('/:id', auth, async (req, res) => {
  try {
    const id = parseInt(req.params.id);

    const venda = await query(`
      SELECT v.id, v.criado_em, v.subtotal, v.desconto, v.total, v.observacao,
             fp.nome AS pagamento,
             c.id AS cliente_id, c.nome AS cliente_nome, c.documento AS cliente_doc
      FROM Vendas v
      LEFT JOIN Clientes        c  ON c.id  = v.cliente_id
      LEFT JOIN FormasPagamento fp ON fp.id = v.forma_pagamento_id
      WHERE v.id = @id AND v.empresa_id = @emp
    `, { id, emp: req.user.empresa_id });

    if (!venda.recordset[0]) return res.status(404).json({ error: 'Venda não encontrada.' });

    const itens = await query(`
      SELECT iv.id, iv.quantidade, iv.preco_unit, iv.subtotal,
             p.id AS produto_id, p.codigo, p.descricao
      FROM ItensVenda iv
      JOIN Produtos p ON p.id = iv.produto_id
      WHERE iv.venda_id = @id
    `, { id });

    res.json({ ...venda.recordset[0], itens: itens.recordset });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao buscar venda.' });
  }
});

// POST /api/vendas — cria venda + baixa estoque (transação PostgreSQL)
router.post('/', auth, async (req, res) => {
  try {
    const { cliente_id, pagamento, itens, desconto = 0, observacao = '',
            data_vencimento, parcelas } = req.body;

    if (!itens || !itens.length) {
      return res.status(400).json({ error: 'A venda precisa ter pelo menos um item.' });
    }
    if (!pagamento) {
      return res.status(400).json({ error: 'Forma de pagamento obrigatória.' });
    }
    if (pagamento === 'fiado' && !cliente_id) {
      return res.status(400).json({ error: 'Venda a prazo (fiado) exige um cliente selecionado.' });
    }

    const isFiado = pagamento === 'fiado';
    const numParcelas = isFiado ? (parseInt(parcelas) || 1) : 1;

    const result = await withTransaction(async (tq) => {
      // Resolver forma de pagamento
      const fpR = await tq('SELECT id FROM FormasPagamento WHERE nome=@pgto', { pgto: pagamento });
      if (!fpR.recordset.length) throw Object.assign(new Error('Forma de pagamento inválida.'), { status: 400 });
      const fpId = fpR.recordset[0].id;

      // Verificar e calcular itens
      let subtotal = 0;
      const itensPreco = [];
      for (const item of itens) {
        const pR = await tq(
          `SELECT preco_venda, estoque, descricao, controla_estoque
           FROM Produtos WHERE id=@pid AND empresa_id=@emp AND status='ativo'`,
          { pid: item.produto_id, emp: req.user.empresa_id }
        );
        if (!pR.recordset.length) {
          throw Object.assign(new Error(`Produto ID ${item.produto_id} não encontrado ou inativo.`), { status: 400 });
        }
        const prod = pR.recordset[0];
        if (prod.controla_estoque && prod.estoque < item.quantidade) {
          throw Object.assign(new Error(`Estoque insuficiente para "${prod.descricao}". Disponível: ${prod.estoque}.`), { status: 400 });
        }
        const sub = parseFloat(prod.preco_venda) * item.quantidade;
        subtotal += sub;
        itensPreco.push({ ...item, preco_unit: parseFloat(prod.preco_venda), subtotal: sub, controla: prod.controla_estoque, estoque: prod.estoque });
      }

      const desc  = parseFloat(desconto) || 0;
      const total = Math.max(subtotal - desc, 0);

      // Inserir venda
      const vR = await tq(`
        INSERT INTO Vendas
          (empresa_id, cliente_id, forma_pagamento_id, subtotal, desconto, total, observacao, usuario_id,
           status_cobranca, data_vencimento, data_recebimento)
        VALUES (@emp, @cid, @fp, @sub, @desc, @tot, @obs, @uid, @stcob, @dvenc, @drec)
        RETURNING id
      `, {
        emp:   req.user.empresa_id,
        cid:   cliente_id || null,
        fp:    fpId,
        sub:   subtotal,
        desc,
        tot:   total,
        obs:   observacao || null,
        uid:   req.user.id,
        stcob: isFiado ? 'pendente' : 'recebido',
        dvenc: data_vencimento ? new Date(data_vencimento) : null,
        drec:  isFiado ? null : new Date(),
      });
      const vendaId = vR.recordset[0].id;

      // Inserir itens + baixar estoque
      for (const item of itensPreco) {
        await tq(
          'INSERT INTO ItensVenda (venda_id,produto_id,quantidade,preco_unit,subtotal) VALUES (@vid,@pid,@qty,@pu,@sub)',
          { vid: vendaId, pid: item.produto_id, qty: item.quantidade, pu: item.preco_unit, sub: item.subtotal }
        );

        if (item.controla) {
          const saldoAnt  = item.estoque;
          const saldoAtual = saldoAnt - item.quantidade;
          await tq(
            'UPDATE Produtos SET estoque=estoque-@qty, atualizado_em=NOW() WHERE id=@pid AND empresa_id=@emp',
            { qty: item.quantidade, pid: item.produto_id, emp: req.user.empresa_id }
          );
          await tq(
            `INSERT INTO MovimentacoesEstoque (empresa_id,produto_id,tipo,quantidade,saldo_anterior,saldo_atual,origem,usuario_id)
             VALUES (@emp,@pid,'saida',@qty,@sant,@sat,@orig,@uid)`,
            { emp: req.user.empresa_id, pid: item.produto_id, qty: item.quantidade,
              sant: saldoAnt, sat: saldoAtual, orig: `Venda #${vendaId}`, uid: req.user.id }
          );
        }
      }

      return { vendaId, total, numParcelas };
    });

    // Gerar parcelas (fora da transação — ContasReceber não é crítico)
    if (isFiado) {
      const valorParcela = +(result.total / result.numParcelas).toFixed(2);
      const primeiroVenc = data_vencimento ? new Date(data_vencimento) : new Date(Date.now() + 30*86400000);
      for (let i = 0; i < result.numParcelas; i++) {
        const venc = new Date(primeiroVenc);
        venc.setMonth(venc.getMonth() + i);
        const valor = i === result.numParcelas - 1
          ? +(result.total - valorParcela * (result.numParcelas - 1)).toFixed(2)
          : valorParcela;
        await query(
          `INSERT INTO ContasReceber (empresa_id,venda_id,cliente_id,parcela_num,parcelas_total,valor,data_vencimento,status,observacao)
           VALUES (@emp,@vid,@cid,@pn,@pt,@val,@dvenc,'pendente',@obs)`,
          { emp: req.user.empresa_id, vid: result.vendaId, cid: cliente_id||null,
            pn: i+1, pt: result.numParcelas, val: valor, dvenc: venc, obs: observacao||null }
        );
      }
    }

    const full = await query(`
      SELECT v.id, v.criado_em, v.subtotal, v.desconto, v.total, v.observacao,
             fp.nome AS pagamento,
             c.id AS cliente_id, c.nome AS cliente_nome
      FROM Vendas v
      LEFT JOIN Clientes c ON c.id=v.cliente_id
      LEFT JOIN FormasPagamento fp ON fp.id=v.forma_pagamento_id
      WHERE v.id=@id
    `, { id: result.vendaId });

    const itensR = await query(`
      SELECT iv.quantidade, iv.preco_unit, iv.subtotal, p.codigo, p.descricao
      FROM ItensVenda iv JOIN Produtos p ON p.id=iv.produto_id
      WHERE iv.venda_id=@id
    `, { id: result.vendaId });

    res.status(201).json({ ...full.recordset[0], itens: itensR.recordset });
  } catch (err) {
    console.error(err);
    res.status(err.status || 500).json({ error: err.message || 'Erro ao registrar venda.' });
  }
});

module.exports = router;
