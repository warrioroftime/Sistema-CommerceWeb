// frontend/api.js
// Camada de comunicação com o backend GestorFlex
// Importe este arquivo antes do app.js no HTML

const API_URL = window.GF_API_URL || 'http://localhost:3001/api';

// ── Token management ──────────────────────────────────────────
const Auth = {
  getToken:  ()  => localStorage.getItem('gf_token'),
  setToken:  (t) => localStorage.setItem('gf_token', t),
  clearToken:()  => localStorage.removeItem('gf_token'),
  getUser:   ()  => { try { return JSON.parse(localStorage.getItem('gf_user')||'null'); } catch { return null; } },
  setUser:   (u) => localStorage.setItem('gf_user', JSON.stringify(u)),
  clearUser: ()  => localStorage.removeItem('gf_user'),
  isLogged:  ()  => !!localStorage.getItem('gf_token'),
};

// ── Base fetch ────────────────────────────────────────────────
async function apiFetch(path, options = {}) {
  const token = Auth.getToken();
  const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) };
  if (token) headers['Authorization'] = `Bearer ${token}`;

  const res = await fetch(API_URL + path, { ...options, headers });

  if (res.status === 401) {
    Auth.clearToken();
    Auth.clearUser();
    window.dispatchEvent(new Event('gf:unauthorized'));
    throw new Error('Sessão expirada. Faça login novamente.');
  }

  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `Erro ${res.status}`);
  return data;
}

const api = {
  get:    (path)         => apiFetch(path),
  post:   (path, body)   => apiFetch(path, { method: 'POST',   body: JSON.stringify(body) }),
  put:    (path, body)   => apiFetch(path, { method: 'PUT',    body: JSON.stringify(body) }),
  delete: (path)         => apiFetch(path, { method: 'DELETE' }),
};

// ── Auth ──────────────────────────────────────────────────────
const AuthAPI = {
  login: async (email, senha) => {
    const data = await api.post('/auth/login', { email, senha });
    Auth.setToken(data.token);
    Auth.setUser(data.user);
    return data.user;
  },
  logout: () => {
    Auth.clearToken();
    Auth.clearUser();
  },
  me: () => api.get('/auth/me'),
  trocarSenha: (body) => api.post('/auth/trocar-senha', body),
};

// ── Produtos ──────────────────────────────────────────────────
const ProdutosAPI = {
  listar:     (params = {}) => api.get('/produtos?' + new URLSearchParams(params)),
  categorias: ()             => api.get('/produtos/categorias'),
  buscar:     (id)           => api.get(`/produtos/${id}`),
  criar:      (body)         => api.post('/produtos', body),
  atualizar:  (id, body)     => api.put(`/produtos/${id}`, body),
  excluir:    (id)           => api.delete(`/produtos/${id}`),
};

// ── Clientes ──────────────────────────────────────────────────
const ClientesAPI = {
  listar:    (params = {}) => api.get('/clientes?' + new URLSearchParams(params)),
  buscar:    (id)           => api.get(`/clientes/${id}`),
  historico: (id)           => api.get(`/clientes/${id}/historico`),
  criar:     (body)         => api.post('/clientes', body),
  atualizar: (id, body)     => api.put(`/clientes/${id}`, body),
  excluir:   (id)           => api.delete(`/clientes/${id}`),
};

// ── Vendas ────────────────────────────────────────────────────
const VendasAPI = {
  listar:  (params = {}) => api.get('/vendas?' + new URLSearchParams(params)),
  buscar:  (id)           => api.get(`/vendas/${id}`),
  criar:   (body)         => api.post('/vendas', body),
};

// ── Estoque ───────────────────────────────────────────────────
const EstoqueAPI = {
  posicao:        (params = {}) => api.get('/estoque?' + new URLSearchParams(params)),
  movimentacoes:  (params = {}) => api.get('/estoque/movimentacoes?' + new URLSearchParams(params)),
  entrada:        (body)         => api.post('/estoque/entrada', body),
};

// ── Relatórios ────────────────────────────────────────────────
const RelatoriosAPI = {
  dashboard: (periodo = 30) => api.get(`/relatorios/dashboard?periodo=${periodo}`),
  vendas:    (params = {})  => api.get('/relatorios/vendas?' + new URLSearchParams(params)),
};

// Exportar para uso global no HTML
window.GF = { Auth, AuthAPI, ProdutosAPI, ClientesAPI, VendasAPI, EstoqueAPI, RelatoriosAPI };
