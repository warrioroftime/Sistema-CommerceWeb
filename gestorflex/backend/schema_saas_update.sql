-- ================================================================
-- CommerceWeb — Migração SaaS
-- Execute este script APÓS o schema.sql original
-- Adiciona: super_admin, Planos, Assinaturas e dados iniciais
-- ================================================================

USE GestorFlex;
GO

-- ----------------------------------------------------------------
-- 1. Remover CHECK constraint antiga de perfil (nome auto-gerado)
-- ----------------------------------------------------------------
DECLARE @ck NVARCHAR(200);
SELECT @ck = cc.name
FROM sys.check_constraints cc
INNER JOIN sys.columns col ON cc.parent_object_id = col.object_id
                          AND cc.parent_column_id = col.column_id
WHERE col.object_id = OBJECT_ID('Usuarios') AND col.name = 'perfil';
IF @ck IS NOT NULL
    EXEC('ALTER TABLE Usuarios DROP CONSTRAINT [' + @ck + ']');
GO

-- Adiciona nova CHECK incluindo super_admin
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints WHERE name = 'CK_usuarios_perfil'
    AND parent_object_id = OBJECT_ID('Usuarios')
)
ALTER TABLE Usuarios
    ADD CONSTRAINT CK_usuarios_perfil
    CHECK (perfil IN ('super_admin','admin','gerente','operador'));
GO

-- ----------------------------------------------------------------
-- 2. Tornar empresa_id opcional (NULL para super_admin)
-- ----------------------------------------------------------------
DECLARE @fk NVARCHAR(200);
SELECT @fk = name FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID('Usuarios')
  AND referenced_object_id = OBJECT_ID('Empresas');
IF @fk IS NOT NULL
    EXEC('ALTER TABLE Usuarios DROP CONSTRAINT [' + @fk + ']');
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('Usuarios') AND name = 'empresa_id'
      AND is_nullable = 0
)
ALTER TABLE Usuarios ALTER COLUMN empresa_id INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Usuarios_Empresas'
)
ALTER TABLE Usuarios
    ADD CONSTRAINT FK_Usuarios_Empresas
    FOREIGN KEY (empresa_id) REFERENCES Empresas(id);
GO

-- ----------------------------------------------------------------
-- 3. Tabela PLANOS
-- ----------------------------------------------------------------
IF OBJECT_ID('Planos') IS NULL
CREATE TABLE Planos (
    id           INT IDENTITY(1,1) PRIMARY KEY,
    nome         NVARCHAR(80)  NOT NULL,
    descricao    NVARCHAR(300),
    preco_mensal DECIMAL(10,2) NOT NULL DEFAULT 0,
    max_usuarios INT           NOT NULL DEFAULT 5,
    max_produtos INT           NOT NULL DEFAULT 100,
    ativo        BIT           NOT NULL DEFAULT 1,
    criado_em    DATETIME2     NOT NULL DEFAULT GETDATE()
);
GO

IF NOT EXISTS (SELECT 1 FROM Planos)
INSERT INTO Planos (nome, descricao, preco_mensal, max_usuarios, max_produtos) VALUES
    ('Gratuito',     'Plano gratuito para avaliação',            0.00,   1,    50),
    ('Básico',       'Ideal para pequenos negócios',            99.00,   3,   100),
    ('Profissional', 'Para negócios em crescimento',           199.00,  10,   500),
    ('Enterprise',   'Ilimitado para grandes operações',       499.00,  50,  5000);
GO

-- ----------------------------------------------------------------
-- 4. Tabela ASSINATURAS
-- ----------------------------------------------------------------
IF OBJECT_ID('Assinaturas') IS NULL
CREATE TABLE Assinaturas (
    id          INT IDENTITY(1,1) PRIMARY KEY,
    empresa_id  INT          NOT NULL REFERENCES Empresas(id),
    plano_id    INT          NOT NULL REFERENCES Planos(id),
    status      NVARCHAR(20) NOT NULL DEFAULT 'trial'
                CHECK (status IN ('trial','ativo','suspenso','cancelado')),
    data_inicio DATETIME2    NOT NULL DEFAULT GETDATE(),
    data_fim    DATETIME2    NULL,
    criado_em   DATETIME2    NOT NULL DEFAULT GETDATE()
);
GO

-- ----------------------------------------------------------------
-- 5. Super Admin da plataforma (sem empresa_id)
-- ----------------------------------------------------------------
-- Senha: super123
IF NOT EXISTS (SELECT 1 FROM Usuarios WHERE perfil = 'super_admin')
INSERT INTO Usuarios (empresa_id, nome, email, senha_hash, perfil)
VALUES (
    NULL,
    'Super Administrador',
    'super@commerceweb.com',
    '$2b$10$QWYVvEJ/rA5kzKeZQr1yeukS0f/7o5m8qmKMa/99ZOgrRTYlbuNJW',
    'super_admin'
);
GO

-- ----------------------------------------------------------------
-- 6. Assinatura inicial para a empresa demo (trial 30 dias)
-- ----------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM Assinaturas)
BEGIN
    DECLARE @demoEmp  INT = (SELECT TOP 1 id FROM Empresas WHERE razao_social = 'Empresa Demo Ltda.');
    DECLARE @planoPro INT = (SELECT TOP 1 id FROM Planos    WHERE nome = 'Profissional');
    IF @demoEmp IS NOT NULL AND @planoPro IS NOT NULL
        INSERT INTO Assinaturas (empresa_id, plano_id, status, data_fim)
        VALUES (@demoEmp, @planoPro, 'trial', DATEADD(DAY, 30, GETDATE()));
END
GO

PRINT '✅ Migração SaaS aplicada com sucesso.';
PRINT '   Super Admin: super@commerceweb.com / super123';
GO
