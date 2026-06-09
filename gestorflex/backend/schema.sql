-- ================================================================
-- GestorFlex — Schema SQL Server
-- Execute este script UMA vez para criar o banco e todas as tabelas
-- ================================================================

-- 1. Criar banco (execute conectado ao master)
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'GestorFlex')
BEGIN
    CREATE DATABASE GestorFlex
    COLLATE Latin1_General_CI_AI;
    PRINT 'Banco GestorFlex criado.';
END
GO

USE GestorFlex;
GO

-- ----------------------------------------------------------------
-- EMPRESAS (multi-tenant: cada empresa é um tenant)
-- ----------------------------------------------------------------
IF OBJECT_ID('Empresas') IS NULL
CREATE TABLE Empresas (
    id            INT IDENTITY(1,1) PRIMARY KEY,
    razao_social  NVARCHAR(150) NOT NULL,
    cnpj          NVARCHAR(20),
    email         NVARCHAR(150),
    telefone      NVARCHAR(20),
    ativo         BIT NOT NULL DEFAULT 1,
    criado_em     DATETIME2 NOT NULL DEFAULT GETDATE()
);
GO

-- ----------------------------------------------------------------
-- USUÁRIOS
-- ----------------------------------------------------------------
IF OBJECT_ID('Usuarios') IS NULL
CREATE TABLE Usuarios (
    id           INT IDENTITY(1,1) PRIMARY KEY,
    empresa_id   INT NOT NULL REFERENCES Empresas(id),
    nome         NVARCHAR(120) NOT NULL,
    email        NVARCHAR(150) NOT NULL,
    senha_hash   NVARCHAR(255) NOT NULL,
    perfil       NVARCHAR(20) NOT NULL DEFAULT 'operador'
                 CHECK (perfil IN ('admin','gerente','operador')),
    foto         NVARCHAR(MAX) NULL,
    ativo        BIT NOT NULL DEFAULT 1,
    criado_em    DATETIME2 NOT NULL DEFAULT GETDATE(),
    CONSTRAINT UQ_usuarios_email UNIQUE (empresa_id, email)
);
GO

-- Adiciona coluna foto se já existir a tabela sem ela
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('Usuarios') AND name='foto')
  ALTER TABLE Usuarios ADD foto NVARCHAR(MAX) NULL;
GO

-- ----------------------------------------------------------------
-- CATEGORIAS (por empresa)
-- ----------------------------------------------------------------
IF OBJECT_ID('Categorias') IS NULL
CREATE TABLE Categorias (
    id          INT IDENTITY(1,1) PRIMARY KEY,
    empresa_id  INT NOT NULL REFERENCES Empresas(id),
    nome        NVARCHAR(80) NOT NULL,
    CONSTRAINT UQ_cat_nome UNIQUE (empresa_id, nome)
);
GO

-- ----------------------------------------------------------------
-- CLIENTES
-- ----------------------------------------------------------------
IF OBJECT_ID('Clientes') IS NULL
CREATE TABLE Clientes (
    id           INT IDENTITY(1,1) PRIMARY KEY,
    empresa_id   INT NOT NULL REFERENCES Empresas(id),
    nome         NVARCHAR(150) NOT NULL,
    documento    NVARCHAR(20),           -- CPF ou CNPJ
    telefone     NVARCHAR(20),
    email        NVARCHAR(150),
    endereco     NVARCHAR(250),
    cidade       NVARCHAR(100),
    estado       CHAR(2),
    ativo        BIT NOT NULL DEFAULT 1,
    criado_em    DATETIME2 NOT NULL DEFAULT GETDATE(),
    atualizado_em DATETIME2
);
GO

-- ----------------------------------------------------------------
-- PRODUTOS
-- ----------------------------------------------------------------
IF OBJECT_ID('Produtos') IS NULL
CREATE TABLE Produtos (
    id            INT IDENTITY(1,1) PRIMARY KEY,
    empresa_id    INT NOT NULL REFERENCES Empresas(id),
    codigo        NVARCHAR(30) NOT NULL,
    descricao     NVARCHAR(200) NOT NULL,
    categoria_id  INT REFERENCES Categorias(id),
    preco_custo   DECIMAL(15,2) NOT NULL DEFAULT 0,
    preco_venda   DECIMAL(15,2) NOT NULL DEFAULT 0,
    estoque       INT NOT NULL DEFAULT 0,
    estoque_min   INT NOT NULL DEFAULT 5,
    status        NVARCHAR(10) NOT NULL DEFAULT 'ativo'
                  CHECK (status IN ('ativo','inativo')),
    criado_em     DATETIME2 NOT NULL DEFAULT GETDATE(),
    atualizado_em DATETIME2,
    CONSTRAINT UQ_prod_codigo UNIQUE (empresa_id, codigo)
);
GO

-- ----------------------------------------------------------------
-- MOVIMENTAÇÕES DE ESTOQUE
-- ----------------------------------------------------------------
IF OBJECT_ID('MovimentacoesEstoque') IS NULL
CREATE TABLE MovimentacoesEstoque (
    id            INT IDENTITY(1,1) PRIMARY KEY,
    empresa_id    INT NOT NULL REFERENCES Empresas(id),
    produto_id    INT NOT NULL REFERENCES Produtos(id),
    tipo          NVARCHAR(10) NOT NULL CHECK (tipo IN ('entrada','saida')),
    quantidade    INT NOT NULL,
    saldo_anterior INT NOT NULL,
    saldo_atual   INT NOT NULL,
    origem        NVARCHAR(200),         -- ex: "Venda #1042", "Compra fornecedor"
    usuario_id    INT REFERENCES Usuarios(id),
    criado_em     DATETIME2 NOT NULL DEFAULT GETDATE()
);
GO

-- ----------------------------------------------------------------
-- FORMAS DE PAGAMENTO
-- ----------------------------------------------------------------
IF OBJECT_ID('FormasPagamento') IS NULL
CREATE TABLE FormasPagamento (
    id    INT IDENTITY(1,1) PRIMARY KEY,
    nome  NVARCHAR(50) NOT NULL
);
GO
INSERT INTO FormasPagamento (nome)
SELECT v FROM (VALUES
    ('dinheiro'),('pix'),('debito'),('credito'),('transferencia'),('fiado')
) t(v)
WHERE NOT EXISTS (SELECT 1 FROM FormasPagamento);
GO

-- ----------------------------------------------------------------
-- VENDAS
-- ----------------------------------------------------------------
IF OBJECT_ID('Vendas') IS NULL
CREATE TABLE Vendas (
    id                   INT IDENTITY(1,1) PRIMARY KEY,
    empresa_id           INT NOT NULL REFERENCES Empresas(id),
    cliente_id           INT REFERENCES Clientes(id),
    forma_pagamento_id   INT REFERENCES FormasPagamento(id),
    subtotal             DECIMAL(15,2) NOT NULL DEFAULT 0,
    desconto             DECIMAL(15,2) NOT NULL DEFAULT 0,
    total                DECIMAL(15,2) NOT NULL DEFAULT 0,
    observacao           NVARCHAR(500),
    usuario_id           INT REFERENCES Usuarios(id),
    criado_em            DATETIME2 NOT NULL DEFAULT GETDATE()
);
GO

-- ----------------------------------------------------------------
-- ITENS DE VENDA
-- ----------------------------------------------------------------
IF OBJECT_ID('ItensVenda') IS NULL
CREATE TABLE ItensVenda (
    id          INT IDENTITY(1,1) PRIMARY KEY,
    venda_id    INT NOT NULL REFERENCES Vendas(id) ON DELETE CASCADE,
    produto_id  INT NOT NULL REFERENCES Produtos(id),
    quantidade  INT NOT NULL,
    preco_unit  DECIMAL(15,2) NOT NULL,
    subtotal    DECIMAL(15,2) NOT NULL
);
GO

-- ----------------------------------------------------------------
-- ÍNDICES de performance
-- ----------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Vendas_empresa_data')
    CREATE INDEX IX_Vendas_empresa_data     ON Vendas(empresa_id, criado_em DESC);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Produtos_empresa')
    CREATE INDEX IX_Produtos_empresa        ON Produtos(empresa_id, status);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Clientes_empresa')
    CREATE INDEX IX_Clientes_empresa        ON Clientes(empresa_id, ativo);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_MovEstoque_empresa')
    CREATE INDEX IX_MovEstoque_empresa      ON MovimentacoesEstoque(empresa_id, criado_em DESC);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_ItensVenda_venda')
    CREATE INDEX IX_ItensVenda_venda        ON ItensVenda(venda_id);
GO

-- ----------------------------------------------------------------
-- DADOS INICIAIS — Empresa demo + admin
-- ----------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM Empresas WHERE razao_social = 'Empresa Demo Ltda.')
BEGIN
    INSERT INTO Empresas (razao_social, cnpj, email, telefone)
    VALUES ('Empresa Demo Ltda.', '00.000.000/0001-00', 'demo@gestorflex.com', '(00) 0000-0000');

    -- Senha padrão: admin123  (bcrypt hash gerado externamente)
    -- Para gerar outro hash: node -e "const b=require('bcryptjs');console.log(b.hashSync('admin123',10))"
    DECLARE @emp INT = SCOPE_IDENTITY();

    INSERT INTO Usuarios (empresa_id, nome, email, senha_hash, perfil)
    VALUES (
        @emp,
        'Administrador',
        'admin@gestorflex.com',
        '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lF/.',  -- admin123
        'admin'
    );

    INSERT INTO Categorias (empresa_id, nome) VALUES
        (@emp,'Eletrônicos'), (@emp,'Escritório'), (@emp,'Outros'),
        (@emp,'Higiene'), (@emp,'Limpeza'), (@emp,'Alimentos');

    PRINT 'Dados iniciais inseridos. Login: admin@gestorflex.com / admin123';
END
GO

PRINT 'Schema GestorFlex aplicado com sucesso.';
GO
