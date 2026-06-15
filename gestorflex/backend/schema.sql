-- ================================================================
-- CommerceWeb — Schema PostgreSQL
-- Execute: psql -U sa -f schema.sql
-- ================================================================

-- Criar banco (execute conectado ao postgres)
-- CREATE DATABASE commerceweb ENCODING 'UTF8';
-- \c commerceweb

-- ----------------------------------------------------------------
-- EMPRESAS (multi-tenant: cada empresa é um tenant)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Empresas (
    id           SERIAL PRIMARY KEY,
    razao_social VARCHAR(150) NOT NULL,
    cnpj         VARCHAR(20),
    email        VARCHAR(150),
    telefone     VARCHAR(20),
    ativo        BOOLEAN NOT NULL DEFAULT TRUE,
    criado_em    TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------
-- USUÁRIOS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Usuarios (
    id          SERIAL PRIMARY KEY,
    empresa_id  INT REFERENCES Empresas(id),
    nome        VARCHAR(120) NOT NULL,
    email       VARCHAR(150) NOT NULL,
    senha_hash  VARCHAR(255) NOT NULL,
    perfil      VARCHAR(20) NOT NULL DEFAULT 'operador'
                CHECK (perfil IN ('super_admin','admin','gerente','operador')),
    foto        TEXT,
    ativo       BOOLEAN NOT NULL DEFAULT TRUE,
    criado_em   TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_usuarios_email UNIQUE (empresa_id, email)
);

-- ----------------------------------------------------------------
-- CATEGORIAS (por empresa)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Categorias (
    id         SERIAL PRIMARY KEY,
    empresa_id INT NOT NULL REFERENCES Empresas(id),
    nome       VARCHAR(80) NOT NULL,
    CONSTRAINT uq_cat_nome UNIQUE (empresa_id, nome)
);

-- ----------------------------------------------------------------
-- CLIENTES
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Clientes (
    id            SERIAL PRIMARY KEY,
    empresa_id    INT NOT NULL REFERENCES Empresas(id),
    nome          VARCHAR(150) NOT NULL,
    nome_fantasia VARCHAR(150),
    documento     VARCHAR(20),
    telefone      VARCHAR(20),
    email         VARCHAR(150),
    cep           VARCHAR(10),
    endereco      VARCHAR(250),
    numero        VARCHAR(20),
    bairro        VARCHAR(100),
    cidade        VARCHAR(100),
    estado        CHAR(2),
    ativo         BOOLEAN NOT NULL DEFAULT TRUE,
    criado_em     TIMESTAMP NOT NULL DEFAULT NOW(),
    atualizado_em TIMESTAMP
);

-- ----------------------------------------------------------------
-- PRODUTOS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Produtos (
    id               SERIAL PRIMARY KEY,
    empresa_id       INT NOT NULL REFERENCES Empresas(id),
    codigo           VARCHAR(30) NOT NULL,
    descricao        VARCHAR(200) NOT NULL,
    categoria_id     INT REFERENCES Categorias(id),
    preco_custo      NUMERIC(15,2) NOT NULL DEFAULT 0,
    preco_venda      NUMERIC(15,2) NOT NULL DEFAULT 0,
    estoque          INT NOT NULL DEFAULT 0,
    estoque_min      INT NOT NULL DEFAULT 5,
    status           VARCHAR(10) NOT NULL DEFAULT 'ativo'
                     CHECK (status IN ('ativo','inativo')),
    controla_estoque BOOLEAN NOT NULL DEFAULT TRUE,
    foto             TEXT,
    criado_em        TIMESTAMP NOT NULL DEFAULT NOW(),
    atualizado_em    TIMESTAMP,
    CONSTRAINT uq_prod_codigo UNIQUE (empresa_id, codigo)
);

-- ----------------------------------------------------------------
-- MOVIMENTAÇÕES DE ESTOQUE
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS MovimentacoesEstoque (
    id            SERIAL PRIMARY KEY,
    empresa_id    INT NOT NULL REFERENCES Empresas(id),
    produto_id    INT NOT NULL REFERENCES Produtos(id),
    tipo          VARCHAR(10) NOT NULL CHECK (tipo IN ('entrada','saida')),
    quantidade    INT NOT NULL,
    saldo_anterior INT NOT NULL,
    saldo_atual   INT NOT NULL,
    origem        VARCHAR(200),
    usuario_id    INT REFERENCES Usuarios(id),
    criado_em     TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------
-- FORMAS DE PAGAMENTO
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS FormasPagamento (
    id   SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL
);

INSERT INTO FormasPagamento (nome)
SELECT v FROM (VALUES
    ('dinheiro'),('pix'),('debito'),('credito'),('transferencia'),('fiado')
) t(v)
WHERE NOT EXISTS (SELECT 1 FROM FormasPagamento);

-- ----------------------------------------------------------------
-- VENDAS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Vendas (
    id                   SERIAL PRIMARY KEY,
    empresa_id           INT NOT NULL REFERENCES Empresas(id),
    cliente_id           INT REFERENCES Clientes(id),
    forma_pagamento_id   INT REFERENCES FormasPagamento(id),
    subtotal             NUMERIC(15,2) NOT NULL DEFAULT 0,
    desconto             NUMERIC(15,2) NOT NULL DEFAULT 0,
    total                NUMERIC(15,2) NOT NULL DEFAULT 0,
    observacao           VARCHAR(500),
    usuario_id           INT REFERENCES Usuarios(id),
    status_cobranca      VARCHAR(20) DEFAULT 'recebido',
    data_vencimento      TIMESTAMP,
    data_recebimento     TIMESTAMP,
    criado_em            TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------
-- ITENS DE VENDA
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ItensVenda (
    id          SERIAL PRIMARY KEY,
    venda_id    INT NOT NULL REFERENCES Vendas(id) ON DELETE CASCADE,
    produto_id  INT NOT NULL REFERENCES Produtos(id),
    quantidade  INT NOT NULL,
    preco_unit  NUMERIC(15,2) NOT NULL,
    subtotal    NUMERIC(15,2) NOT NULL
);

-- ----------------------------------------------------------------
-- CONTAS A RECEBER
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ContasReceber (
    id             SERIAL PRIMARY KEY,
    empresa_id     INT NOT NULL REFERENCES Empresas(id),
    venda_id       INT REFERENCES Vendas(id),
    cliente_id     INT REFERENCES Clientes(id),
    parcela_num    INT NOT NULL DEFAULT 1,
    parcelas_total INT NOT NULL DEFAULT 1,
    valor          NUMERIC(15,2) NOT NULL,
    data_vencimento TIMESTAMP,
    status         VARCHAR(20) NOT NULL DEFAULT 'pendente'
                   CHECK (status IN ('pendente','recebido','cancelado')),
    data_recebimento TIMESTAMP,
    valor_recebido NUMERIC(15,2),
    observacao     TEXT,
    criado_em      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------
-- PLANOS (SaaS)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Planos (
    id           SERIAL PRIMARY KEY,
    nome         VARCHAR(80) NOT NULL,
    descricao    VARCHAR(300),
    preco_mensal NUMERIC(10,2) NOT NULL DEFAULT 0,
    max_usuarios INT NOT NULL DEFAULT 5,
    max_produtos INT NOT NULL DEFAULT 100,
    ativo        BOOLEAN NOT NULL DEFAULT TRUE,
    criado_em    TIMESTAMP NOT NULL DEFAULT NOW()
);

INSERT INTO Planos (nome, descricao, preco_mensal, max_usuarios, max_produtos)
SELECT nome, descricao, preco_mensal, max_usuarios, max_produtos
FROM (VALUES
    ('Gratuito',     'Plano gratuito para avaliação',            0.00::numeric,   1,    50),
    ('Básico',       'Ideal para pequenos negócios',            99.00::numeric,   3,   100),
    ('Profissional', 'Para negócios em crescimento',           199.00::numeric,  10,   500),
    ('Enterprise',   'Ilimitado para grandes operações',       499.00::numeric,  50,  5000)
) t(nome, descricao, preco_mensal, max_usuarios, max_produtos)
WHERE NOT EXISTS (SELECT 1 FROM Planos);

-- ----------------------------------------------------------------
-- ASSINATURAS (SaaS)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Assinaturas (
    id          SERIAL PRIMARY KEY,
    empresa_id  INT NOT NULL REFERENCES Empresas(id),
    plano_id    INT NOT NULL REFERENCES Planos(id),
    status      VARCHAR(20) NOT NULL DEFAULT 'trial'
                CHECK (status IN ('trial','ativo','suspenso','cancelado')),
    data_inicio TIMESTAMP NOT NULL DEFAULT NOW(),
    data_fim    TIMESTAMP,
    criado_em   TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------
-- ÍNDICES de performance
-- ----------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_vendas_empresa_data  ON Vendas(empresa_id, criado_em DESC);
CREATE INDEX IF NOT EXISTS ix_produtos_empresa     ON Produtos(empresa_id, status);
CREATE INDEX IF NOT EXISTS ix_clientes_empresa     ON Clientes(empresa_id, ativo);
CREATE INDEX IF NOT EXISTS ix_movestoque_empresa   ON MovimentacoesEstoque(empresa_id, criado_em DESC);
CREATE INDEX IF NOT EXISTS ix_itensvenda_venda     ON ItensVenda(venda_id);
CREATE INDEX IF NOT EXISTS ix_contasrec_empresa    ON ContasReceber(empresa_id, status);

-- ----------------------------------------------------------------
-- DADOS INICIAIS — Empresa demo + admin + super_admin
-- ----------------------------------------------------------------
DO $$
DECLARE
  emp_id  INT;
  plan_id INT;
BEGIN
  -- Empresa demo
  IF NOT EXISTS (SELECT 1 FROM Empresas WHERE razao_social = 'Empresa Demo Ltda.') THEN
    INSERT INTO Empresas (razao_social, cnpj, email, telefone)
    VALUES ('Empresa Demo Ltda.', '00.000.000/0001-00', 'demo@commerceweb.com', '(00) 0000-0000')
    RETURNING id INTO emp_id;

    -- Admin da empresa demo (senha: admin123)
    INSERT INTO Usuarios (empresa_id, nome, email, senha_hash, perfil)
    VALUES (
      emp_id,
      'Administrador',
      'admin@commerceweb.com',
      '$2b$10$vBZJBrt.l4Dsr5NUf9rbSOdyIzBxLOq/2/7.oq04h8jCH7LFJodKa',
      'admin'
    );

    -- Categorias demo
    INSERT INTO Categorias (empresa_id, nome) VALUES
      (emp_id,'Eletrônicos'), (emp_id,'Escritório'), (emp_id,'Outros'),
      (emp_id,'Higiene'), (emp_id,'Limpeza'), (emp_id,'Alimentos');

    -- Assinatura trial 30 dias
    SELECT id INTO plan_id FROM Planos WHERE nome = 'Profissional' LIMIT 1;
    IF plan_id IS NOT NULL THEN
      INSERT INTO Assinaturas (empresa_id, plano_id, status, data_fim)
      VALUES (emp_id, plan_id, 'trial', NOW() + INTERVAL '30 days');
    END IF;

    RAISE NOTICE 'Empresa demo criada. Login: admin@commerceweb.com / admin123';
  END IF;

  -- Super Admin da plataforma (senha: super123)
  IF NOT EXISTS (SELECT 1 FROM Usuarios WHERE perfil = 'super_admin') THEN
    INSERT INTO Usuarios (empresa_id, nome, email, senha_hash, perfil)
    VALUES (
      NULL,
      'Super Administrador',
      'super@commerceweb.com',
      '$2b$10$rzm6X3mN.Ww/8p9qtOvE/uumVKBWwj1ijffqFE2I2.kDzfVyrIcLK',
      'super_admin'
    );
    RAISE NOTICE 'Super Admin criado. Login: super@commerceweb.com / super123';
  END IF;
END $$;
