// src/middleware/auth.js
const jwt = require('jsonwebtoken');

function auth(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Token não fornecido.' });
  }
  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.user = payload; // { id, empresa_id, nome, email, perfil }
    next();
  } catch {
    return res.status(401).json({ error: 'Token inválido ou expirado.' });
  }
}

function adminOnly(req, res, next) {
  if (!['admin','super_admin'].includes(req.user.perfil)) {
    return res.status(403).json({ error: 'Acesso restrito a administradores.' });
  }
  next();
}

function superAdminOnly(req, res, next) {
  if (req.user.perfil !== 'super_admin') {
    return res.status(403).json({ error: 'Acesso restrito ao super administrador da plataforma.' });
  }
  next();
}

module.exports = { auth, adminOnly, superAdminOnly };
