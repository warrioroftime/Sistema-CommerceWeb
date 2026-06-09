# GestorFlex — Sistema de Gestão Não Fiscal (SaaS)

Sistema web multi-empresa para gerenciamento de produtos, clientes, estoque e vendas.
Backend Node.js + Express + SQL Server. Frontend HTML/JS puro (sem framework).

---

## Estrutura do Projeto

```
gestorflex/
├── backend/
│   ├── src/
│   │   ├── app.js                  ← Entry point da API
│   │   ├── db.js                   ← Conexão com SQL Server
│   │   ├── middleware/
│   │   │   └── auth.js             ← JWT middleware
│   │   └── routes/
│   │       ├── auth.js             ← Login / me / trocar-senha
│   │       ├── produtos.js         ← CRUD produtos + categorias
│   │       ├── clientes.js         ← CRUD clientes + histórico
│   │       ├── vendas.js           ← Criar venda + baixa de estoque
│   │       ├── estoque.js          ← Posição + movimentações + entrada
│   │       └── relatorios.js       ← Dashboard + relatório de vendas
│   ├── schema.sql                  ← Script de criação do banco
│   ├── .env.example                ← Template de variáveis de ambiente
│   └── package.json
└── frontend/
    ├── index.html                  ← Aplicação completa (SPA)
    └── api.js                      ← Camada de API (uso opcional)
```

---

## Pré-requisitos

- **Node.js** 18+ (`node --version`)
- **SQL Server** 2017+ (ou SQL Server Express, Azure SQL, etc.)
- Navegador moderno

---

## 1. Configurar o Banco de Dados

1. Abra o **SQL Server Management Studio** (SSMS) ou Azure Data Studio.
2. Conecte ao seu servidor SQL Server.
3. Abra o arquivo `backend/schema.sql` e execute-o.
   - Cria o banco `GestorFlex`
   - Cria todas as tabelas com índices
   - Insere dados iniciais: empresa demo + usuário admin
4. Login padrão criado: `admin@gestorflex.com` / `admin123`

---

## 2. Configurar o Backend

```bash
cd gestorflex/backend

# Copiar e editar as variáveis de ambiente
copy .env.example .env      # Windows
# ou: cp .env.example .env  # Linux/Mac

# Edite o .env com seus dados do SQL Server:
# DB_SERVER=seu_servidor
# DB_NAME=GestorFlex
# DB_USER=sa
# DB_PASSWORD=SuaSenha
# JWT_SECRET=chave_secreta_longa
```

### Instalar dependências (já instaladas se você rodou npm install)

```bash
npm install
```

### Iniciar o servidor

```bash
# Produção
npm start

# Desenvolvimento (reinicia ao salvar)
npm run dev
```

O servidor inicia em `http://localhost:3001`.
Teste: `http://localhost:3001/api/health` → deve retornar `{"status":"ok",...}`

---

## 3. Configurar o Frontend

Abra `frontend/index.html` em qualquer editor e localize a linha:

```javascript
window.GF_API_URL = 'http://localhost:3001/api';
```

- **Desenvolvimento local**: mantenha como está.
- **Produção**: troque pelo domínio real, ex: `https://api.meusite.com/api`

### Abrir o Frontend

Opção A — direto no navegador:
```
Abra frontend/index.html no navegador (duplo clique)
```

Opção B — servidor local (recomendado para evitar CORS em alguns navegadores):
```bash
# Com Python
python -m http.server 5500 --directory frontend

# Com Node
npx serve frontend -p 5500
```
Acesse: `http://localhost:5500`

---

## 4. CORS em Produção

Edite o `.env` e defina a origem do seu frontend:

```env
CORS_ORIGIN=https://meusite.com
```

---

## 5. Endpoints da API

### Autenticação
| Método | Rota | Descrição |
|--------|------|-----------|
| POST | `/api/auth/login` | Login, retorna JWT |
| GET | `/api/auth/me` | Dados do usuário logado |
| POST | `/api/auth/trocar-senha` | Troca a senha |

### Produtos
| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/produtos` | Listar (filtros: busca, categoria, status) |
| GET | `/api/produtos/categorias` | Lista categorias da empresa |
| GET | `/api/produtos/:id` | Detalhe |
| POST | `/api/produtos` | Criar |
| PUT | `/api/produtos/:id` | Atualizar |
| DELETE | `/api/produtos/:id` | Excluir / inativar |

### Clientes
| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/clientes` | Listar (filtro: busca) |
| GET | `/api/clientes/:id` | Detalhe |
| GET | `/api/clientes/:id/historico` | Histórico de compras |
| POST | `/api/clientes` | Criar |
| PUT | `/api/clientes/:id` | Atualizar |
| DELETE | `/api/clientes/:id` | Soft delete |

### Vendas
| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/vendas` | Listar (filtros: de, ate, pagamento, busca) |
| GET | `/api/vendas/:id` | Detalhe com itens |
| POST | `/api/vendas` | Criar venda + baixar estoque (transação) |

### Estoque
| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/estoque` | Posição atual (filtros: busca, filtro) |
| GET | `/api/estoque/movimentacoes` | Histórico (filtros: de, ate, tipo, busca) |
| POST | `/api/estoque/entrada` | Entrada manual de mercadoria |

### Relatórios
| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/relatorios/dashboard` | KPIs, top produtos, alertas |
| GET | `/api/relatorios/vendas` | Relatório por período |

---

## 6. Multi-Tenant

Cada empresa tem seus próprios dados isolados via `empresa_id`.
O `empresa_id` é extraído automaticamente do JWT em toda requisição autenticada.
Nunca é necessário passar `empresa_id` no body — o backend sempre usa o do token.

---

## 7. Segurança

- Senhas armazenadas com **bcrypt** (salt 10)
- Tokens **JWT** com expiração de 8h
- Todo acesso aos dados filtra por `empresa_id` do token
- Soft delete em clientes (preserva histórico)
- Produtos com vendas são apenas inativados, nunca deletados

---

## 8. Deploy Sugerido

| Camada | Sugestão |
|--------|----------|
| Backend | PM2 + VPS, ou Azure App Service, ou Railway |
| Banco | SQL Server Express local, ou Azure SQL |
| Frontend | Qualquer hospedagem estática (Vercel, Netlify, IIS, Nginx) |

### Exemplo com PM2

```bash
npm install -g pm2
cd gestorflex/backend
pm2 start src/app.js --name gestorflex-api
pm2 save
pm2 startup
```

---

## 9. Criar Novos Usuários

Execute diretamente no SQL Server (substitua a empresa_id e o hash):

```sql
-- Gere o hash no terminal: node -e "const b=require('bcryptjs');console.log(b.hashSync('senha123',10))"
INSERT INTO Usuarios (empresa_id, nome, email, senha_hash, perfil)
VALUES (1, 'Novo Usuário', 'novo@email.com', '$2a$10$...hash...', 'operador');
```

---

## Problemas Comuns

**"Login Failed for user 'sa'"**
→ Verifique DB_PASSWORD no .env e se o SQL Server está em modo de autenticação mista.

**CORS bloqueado no navegador**
→ Configure CORS_ORIGIN no .env com a origem exata do frontend.

**"Cannot connect to SQL Server"**
→ Verifique se o SQL Server Browser está rodando e se a porta 1433 está aberta.
→ Para instâncias nomeadas, use `DB_SERVER=SERVIDOR\INSTANCIA`.
