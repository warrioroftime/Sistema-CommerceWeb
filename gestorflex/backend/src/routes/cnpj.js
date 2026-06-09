// src/routes/cnpj.js
const router = require('express').Router();
const { auth } = require('../middleware/auth');

function apenasNumeros(str) {
  return String(str).replace(/\D/g, '');
}

function validarCNPJ(cnpj) {
  if (cnpj.length !== 14) return false;
  if (/^(\d)\1+$/.test(cnpj)) return false;

  const calc = (cnpj, tam) => {
    let soma = 0, pos = tam - 7;
    for (let i = tam; i >= 1; i--) {
      soma += parseInt(cnpj[tam - i]) * pos--;
      if (pos < 2) pos = 9;
    }
    const res = soma % 11 < 2 ? 0 : 11 - (soma % 11);
    return res === parseInt(cnpj[tam]);
  };

  return calc(cnpj, 12) && calc(cnpj, 13);
}

// GET /api/cnpj/:cnpj
router.get('/:cnpj', auth, async (req, res) => {
  const cnpj = apenasNumeros(req.params.cnpj);

  if (!validarCNPJ(cnpj)) {
    return res.status(400).json({ error: 'CNPJ inválido.' });
  }

  try {
    const resp = await fetch(`https://brasilapi.com.br/api/cnpj/v1/${cnpj}`, {
      headers: { 'Accept': 'application/json', 'User-Agent': 'GestorFlex/1.0' },
      signal: AbortSignal.timeout(8000),
    });

    if (resp.status === 404 || resp.status === 400) {
      return res.status(404).json({ error: 'CNPJ não encontrado na Receita Federal.' });
    }
    if (!resp.ok) {
      return res.status(502).json({ error: 'Serviço de consulta CNPJ indisponível.' });
    }

    const d = await resp.json();

    // Normaliza para o formato usado pelo sistema
    const telefone = d.ddd_telefone_1
      ? `(${d.ddd_telefone_1.trim().slice(0, 2)}) ${d.ddd_telefone_1.trim().slice(2)}`
      : null;

    const endereco = [d.logradouro, d.numero, d.complemento]
      .filter(Boolean).join(', ');

    res.json({
      cnpj:          d.cnpj,
      razao_social:  d.razao_social,
      nome_fantasia: d.nome_fantasia || null,
      situacao:      d.descricao_situacao_cadastral,
      email:         d.email ? d.email.toLowerCase() : null,
      telefone,
      endereco,
      bairro:        d.bairro   || null,
      cidade:        d.municipio || null,
      estado:        d.uf       || null,
      cep:           d.cep      || null,
      porte:         d.porte    || null,
      abertura:      d.data_inicio_atividade || null,
    });
  } catch (err) {
    if (err.name === 'TimeoutError') {
      return res.status(504).json({ error: 'Tempo de resposta da consulta CNPJ esgotado.' });
    }
    console.error('Erro consulta CNPJ:', err);
    res.status(500).json({ error: 'Erro ao consultar CNPJ.' });
  }
});

module.exports = router;
