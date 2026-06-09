# =============================================================
#  GestorFlex — Instalador para Windows
#  Execute com: powershell -ExecutionPolicy Bypass -File instalar.ps1
# =============================================================

$ErrorActionPreference = 'Stop'

# ── Cores / helpers ──────────────────────────────────────────
function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║        GestorFlex — Instalador               ║" -ForegroundColor Cyan
    Write-Host "  ║        Sistema de Gestão Empresarial         ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step($n, $msg) {
    Write-Host ""
    Write-Host "  [$n] $msg" -ForegroundColor Yellow
    Write-Host "  $('─' * 50)" -ForegroundColor DarkGray
}

function Write-OK($msg)   { Write-Host "  [OK] $msg"    -ForegroundColor Green  }
function Write-WARN($msg) { Write-Host "  [!]  $msg"    -ForegroundColor Yellow }
function Write-ERR($msg)  { Write-Host "  [X]  $msg"    -ForegroundColor Red    }
function Write-INFO($msg) { Write-Host "       $msg"    -ForegroundColor Gray   }

function Pause-AndExit($code) {
    Write-Host ""
    Write-Host "  Pressione ENTER para sair..." -ForegroundColor DarkGray
    Read-Host | Out-Null
    exit $code
}

function Ask($prompt, $default) {
    $resp = Read-Host "       $prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($resp)) { return $default }
    return $resp.Trim()
}

function Ask-Password($prompt) {
    $resp = Read-Host "       $prompt" -AsSecureString
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($resp)
    )
}

# ── Início ────────────────────────────────────────────────────
Write-Header

Write-Host "  Este instalador irá:" -ForegroundColor White
Write-Host "    • Verificar / instalar Node.js" -ForegroundColor Gray
Write-Host "    • Copiar os arquivos do sistema" -ForegroundColor Gray
Write-Host "    • Instalar dependências (npm install)" -ForegroundColor Gray
Write-Host "    • Configurar a conexão com o banco de dados" -ForegroundColor Gray
Write-Host "    • Criar o banco de dados GestorFlex" -ForegroundColor Gray
Write-Host "    • Criar atalhos na Área de Trabalho" -ForegroundColor Gray
Write-Host ""
$confirm = Read-Host "  Deseja continuar? (S/N)"
if ($confirm -notmatch '^[Ss]') { exit 0 }

# ── PASSO 1 — Diretório de instalação ────────────────────────
Write-Step 1 "Diretório de instalação"

$defaultDir = "C:\GestorFlex"
$installDir = Ask "Diretório de instalação" $defaultDir

if (Test-Path $installDir) {
    Write-WARN "O diretório '$installDir' já existe."
    $over = Read-Host "       Sobrescrever? (S/N)"
    if ($over -notmatch '^[Ss]') {
        Write-ERR "Instalação cancelada."
        Pause-AndExit 1
    }
}

# ── PASSO 2 — Node.js ─────────────────────────────────────────
Write-Step 2 "Verificando Node.js"

$nodeOk = $false
try {
    $nodeVer = & node --version 2>$null
    if ($nodeVer -match 'v(\d+)') {
        $major = [int]$Matches[1]
        if ($major -ge 18) {
            Write-OK "Node.js $nodeVer encontrado."
            $nodeOk = $true
        } else {
            Write-WARN "Node.js $nodeVer é antigo (mínimo v18). Será atualizado."
        }
    }
} catch {}

if (-not $nodeOk) {
    Write-WARN "Node.js não encontrado. Tentando instalar via winget..."
    try {
        & winget install --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        $nodeVer = & node --version 2>$null
        Write-OK "Node.js $nodeVer instalado com sucesso."
    } catch {
        Write-ERR "Não foi possível instalar o Node.js automaticamente."
        Write-INFO "Acesse https://nodejs.org e instale a versão LTS manualmente."
        Write-INFO "Depois execute este instalador novamente."
        Pause-AndExit 1
    }
}

# ── PASSO 3 — Copiar arquivos ─────────────────────────────────
Write-Step 3 "Copiando arquivos do sistema"

$sourceDir = $PSScriptRoot
Write-INFO "Origem : $sourceDir"
Write-INFO "Destino: $installDir"

# Cria estrutura de diretórios
New-Item -ItemType Directory -Force -Path "$installDir\gestorflex\backend\src\routes"  | Out-Null
New-Item -ItemType Directory -Force -Path "$installDir\gestorflex\backend\src\middleware" | Out-Null
New-Item -ItemType Directory -Force -Path "$installDir\gestorflex\frontend" | Out-Null

# Copia backend (sem node_modules e .env)
$backendSrc = "$sourceDir\gestorflex\backend"
$backendDst = "$installDir\gestorflex\backend"

Get-ChildItem $backendSrc -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\node_modules\\' -and
    $_.Name -ne '.env' -and
    $_.Name -ne '__serve.js'
} | ForEach-Object {
    $rel = $_.FullName.Substring($backendSrc.Length + 1)
    $dst = Join-Path $backendDst $rel
    $dstDir = Split-Path $dst
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
    Copy-Item $_.FullName -Destination $dst -Force
}

# Copia frontend
Copy-Item "$sourceDir\gestorflex\frontend\index.html" -Destination "$installDir\gestorflex\frontend\index.html" -Force

Write-OK "Arquivos copiados."

# ── PASSO 4 — npm install ─────────────────────────────────────
Write-Step 4 "Instalando dependências do backend (npm install)"
Write-INFO "Isso pode levar alguns minutos..."

Push-Location "$installDir\gestorflex\backend"
try {
    $npmOut = & npm install 2>&1
    if ($LASTEXITCODE -ne 0) { throw "npm install falhou: $npmOut" }
    Write-OK "Dependências instaladas."
} catch {
    Write-ERR "Erro no npm install: $_"
    Pop-Location
    Pause-AndExit 1
}
Pop-Location

# ── PASSO 5 — Configurar banco de dados ──────────────────────
Write-Step 5 "Configuração do banco de dados (SQL Server)"

Write-INFO "Certifique-se de que o SQL Server está instalado e em execução."
Write-INFO "Se usar SQL Server Express, a instância padrão é: .\SQLEXPRESS"
Write-Host ""

$dbServer   = Ask "Servidor SQL Server"  ".\SQLEXPRESS"
$dbName     = Ask "Nome do banco"        "GestorFlex"
$dbUser     = Ask "Usuário SQL"          "sa"
$dbPassword = Ask-Password "Senha SQL"

Write-INFO "Testando conexão com o SQL Server..."

# Testa conexão usando sqlcmd
$testSql = "SELECT 1 AS ok"
$testOut = & sqlcmd -S $dbServer -U $dbUser -P $dbPassword -Q $testSql -b 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-WARN "sqlcmd retornou erro. Verifique se o SQL Server está acessível."
    Write-INFO "Saída: $testOut"
    $cont = Read-Host "       Continuar mesmo assim? (S/N)"
    if ($cont -notmatch '^[Ss]') { Pause-AndExit 1 }
} else {
    Write-OK "Conexão com SQL Server estabelecida."
}

# ── PASSO 6 — Criar banco e executar schema ───────────────────
Write-Step 6 "Criando banco de dados e tabelas"

# Cria o banco se não existir
$createDb = "IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'$dbName') CREATE DATABASE [$dbName];"
& sqlcmd -S $dbServer -U $dbUser -P $dbPassword -Q $createDb -b 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-OK "Banco '$dbName' verificado/criado."
} else {
    Write-ERR "Não foi possível criar o banco de dados."
    Pause-AndExit 1
}

# Executa o schema
$schemaFile = "$installDir\gestorflex\backend\schema.sql"
Write-INFO "Executando schema.sql..."
$schemaOut = & sqlcmd -S $dbServer -U $dbUser -P $dbPassword -d $dbName -i $schemaFile -b 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-WARN "Aviso ao executar schema (pode ser normal se tabelas já existirem)."
    Write-INFO ($schemaOut | Select-Object -Last 5 | Out-String)
} else {
    Write-OK "Schema executado com sucesso."
}

# ── PASSO 7 — Criar .env ──────────────────────────────────────
Write-Step 7 "Gerando arquivo de configuração (.env)"

$jwtSecret = -join ((65..90)+(97..122)+(48..57) | Get-Random -Count 48 | ForEach-Object { [char]$_ })

$envContent = @"
# GestorFlex - Configuração gerada pelo instalador
PORT=3001
NODE_ENV=production

# SQL Server
DB_SERVER=$dbServer
DB_PORT=
DB_NAME=$dbName
DB_USER=$dbUser
DB_PASSWORD=$dbPassword
DB_ENCRYPT=false
DB_TRUST_CERT=true

# JWT
JWT_SECRET=$jwtSecret
JWT_EXPIRES_IN=8h

# CORS
CORS_ORIGIN=http://localhost:5500
"@

Set-Content -Path "$installDir\gestorflex\backend\.env" -Value $envContent -Encoding UTF8
Write-OK ".env criado com JWT_SECRET gerado automaticamente."

# ── PASSO 8 — Criar servidor frontend ────────────────────────
Write-Step 8 "Criando servidor do frontend"

$serveJs = @'
const http = require('http');
const fs   = require('fs');
const path = require('path');
const dir  = __dirname;
const mime = {
  '.html':'text/html','.css':'text/css','.js':'application/javascript',
  '.json':'application/json','.png':'image/png','.jpg':'image/jpeg',
  '.svg':'image/svg+xml','.ico':'image/x-icon',
  '.woff2':'font/woff2','.woff':'font/woff','.ttf':'font/ttf'
};
http.createServer((req, res) => {
  const p = path.join(dir, req.url === '/' ? 'index.html' : req.url);
  if (!fs.existsSync(p) || fs.statSync(p).isDirectory()) {
    res.writeHead(404); res.end('Not found'); return;
  }
  const ext = path.extname(p);
  res.writeHead(200, { 'Content-Type': mime[ext] || 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
}).listen(5500, () => console.log('Frontend: http://localhost:5500'));
'@

Set-Content -Path "$installDir\gestorflex\frontend\serve.js" -Value $serveJs -Encoding UTF8
Write-OK "Servidor frontend criado."

# ── PASSO 9 — Criar scripts de iniciar/parar ─────────────────
Write-Step 9 "Criando scripts de iniciar e parar o sistema"

$iniciarBat = @"
@echo off
title GestorFlex
echo.
echo   Iniciando GestorFlex...
echo.

cd /d "$installDir"

:: Backend
start "GestorFlex Backend" /min cmd /c "cd gestorflex\backend && node src/app.js"

:: Aguarda backend subir
timeout /t 4 /nobreak > nul

:: Frontend
start "GestorFlex Frontend" /min cmd /c "cd gestorflex\frontend && node serve.js"

:: Aguarda frontend subir
timeout /t 3 /nobreak > nul

:: Abre navegador
start http://localhost:5500

echo   Sistema iniciado!
echo   Frontend: http://localhost:5500
echo   Backend:  http://localhost:3001
echo.
echo   Feche esta janela para manter o sistema rodando.
echo   Use parar.bat para encerrar os servidores.
pause
"@

$pararBat = @"
@echo off
title Parando GestorFlex
echo.
echo   Encerrando GestorFlex...
taskkill /FI "WINDOWTITLE eq GestorFlex Backend*" /F /T > nul 2>&1
taskkill /FI "WINDOWTITLE eq GestorFlex Frontend*" /F /T > nul 2>&1
echo   [OK] Servidores encerrados.
echo.
timeout /t 2 /nobreak > nul
"@

Set-Content -Path "$installDir\iniciar.bat" -Value $iniciarBat -Encoding Default
Set-Content -Path "$installDir\parar.bat"   -Value $pararBat   -Encoding Default
Write-OK "iniciar.bat e parar.bat criados em '$installDir'."

# ── PASSO 10 — Atalhos na Área de Trabalho ────────────────────
Write-Step 10 "Criando atalhos na Área de Trabalho"

$desktop = [Environment]::GetFolderPath("Desktop")
$wsh     = New-Object -ComObject WScript.Shell

# Atalho Iniciar
$lnkStart = $wsh.CreateShortcut("$desktop\GestorFlex - Iniciar.lnk")
$lnkStart.TargetPath       = "$installDir\iniciar.bat"
$lnkStart.WorkingDirectory = $installDir
$lnkStart.Description      = "Iniciar o sistema GestorFlex"
$lnkStart.Save()

# Atalho Parar
$lnkStop = $wsh.CreateShortcut("$desktop\GestorFlex - Parar.lnk")
$lnkStop.TargetPath       = "$installDir\parar.bat"
$lnkStop.WorkingDirectory = $installDir
$lnkStop.Description      = "Parar os servidores GestorFlex"
$lnkStop.Save()

Write-OK "Atalhos criados na Área de Trabalho."

# ── Conclusão ─────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║   Instalação concluída com sucesso!          ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Instalado em : $installDir" -ForegroundColor White
Write-Host "  Frontend     : http://localhost:5500" -ForegroundColor Cyan
Write-Host "  Backend      : http://localhost:3001" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Como usar:" -ForegroundColor White
Write-Host "    • Duplo clique em 'GestorFlex - Iniciar' na Área de Trabalho" -ForegroundColor Gray
Write-Host "    • Ou execute: $installDir\iniciar.bat" -ForegroundColor Gray
Write-Host ""

$iniciar = Read-Host "  Deseja iniciar o sistema agora? (S/N)"
if ($iniciar -match '^[Ss]') {
    Start-Process "$installDir\iniciar.bat"
}

Pause-AndExit 0
