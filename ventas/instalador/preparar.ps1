# ============================================================
# preparar.ps1 — arma el instalador de Ventas para Windows
#
# Uso (desde la raiz del proyecto):
#   powershell -ExecutionPolicy Bypass -File instalador\preparar.ps1
#
# Que hace:
#   1. Comprueba que esten compilados server.exe,
#      web_server.exe, el build web y ventas.exe (Windows)
#   2. Descarga los instaladores de PostgreSQL y Ollama a deps\
#   3. Arma staging\servidor\ con .env, web, contexto, doc,
#      iniciar.bat y crear_bd.ps1
#   4. Compila Ventas.iss con Inno Setup (lo instala con
#      winget si no esta) y deja el .exe en salida\
# ============================================================
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$raiz     = Split-Path -Parent $MyInvocation.MyCommand.Path
$proyecto = Split-Path -Parent $raiz
$stag     = Join-Path $raiz 'staging\servidor'
$deps     = Join-Path $raiz 'deps'
$salida   = Join-Path $raiz 'salida'

# ---------- CONFIGURACION (unica fuente de verdad) ----------
# La misma clave se usa en: .env del servidor, instalacion
# silenciosa de PostgreSQL (--superpassword) y crear_bd.ps1
$ClaveDB          = 'ventas2026'
$VersionApp       = '1.0.0'
$PgMayoria        = '17'
$PgInstalador     = 'postgresql-17.11-1-windows-x64.exe'
$PgUrl            = "https://get.enterprisedb.com/postgresql/$PgInstalador"
$OllamaInstalador = 'OllamaSetup.exe'
$OllamaUrl        = 'https://ollama.com/download/OllamaSetup.exe'
# ---------------------------------------------------------------

function Paso($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Falta($msg){ Write-Host "    FALTA: $msg" -ForegroundColor Yellow }

New-Item -ItemType Directory -Force -Path $stag, $deps, $salida | Out-Null

# --- 1) Artefactos compilados ------------------------------------
Paso 'Comprobando compilaciones (Dart/Flutter)...'
$fallos = 0
$apiExe   = Join-Path $stag 'api\bundle\bin\server.exe'
$frontExe = Join-Path $stag 'webserver\bundle\bin\serve_web.exe'
if (Test-Path $apiExe) { Ok 'server.exe (API)' }
else { $fallos++; Falta 'api\bundle\bin\server.exe' }
if (Test-Path $frontExe) { Ok 'serve_web.exe (web)' }
else { $fallos++; Falta 'webserver\bundle\bin\serve_web.exe' }
if (Test-Path (Join-Path $proyecto 'frontend\build\web\index.html')) { Ok 'frontend\build\web' }
else { $fallos++; Falta 'frontend\build\web  (flutter build web --release)' }
if (Test-Path (Join-Path $proyecto 'frontend\build\windows\x64\runner\Release\ventas.exe')) { Ok 'ventas.exe (Windows)' }
else { $fallos++; Falta 'ventas.exe  (flutter build windows --release)' }

if ($fallos -gt 0) {
    Write-Host ''
    Write-Host 'Compila lo que falta con estos comandos y vuelve a ejecutar preparar.ps1:' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '    cd backend' -ForegroundColor White
    Write-Host '    dart build cli -t bin/server.dart -o ..\instalador\staging\servidor\api' -ForegroundColor White
    Write-Host '    cd ..\frontend' -ForegroundColor White
    Write-Host '    dart build cli -t tool\serve_web.dart -o ..\instalador\staging\servidor\webserver' -ForegroundColor White
    Write-Host '    flutter build web --release' -ForegroundColor White
    Write-Host '    flutter build windows --release' -ForegroundColor White
    exit 1
}

# --- 2) Instaladores de PostgreSQL y Ollama ----------------------
Paso 'Descargando instaladores de PostgreSQL y Ollama (solo la primera vez)...'
function Bajar($url, $destino) {
    if (Test-Path $destino) { Ok "$(Split-Path -Leaf $destino) ya descargado"; return }
    $tmp = "$destino.part"
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
    Move-Item $tmp $destino -Force
    Ok "$(Split-Path -Leaf $destino) ($([math]::Round((Get-Item $destino).Length/1MB)) MB)"
}
Bajar $PgUrl (Join-Path $deps $PgInstalador)
Bajar $OllamaUrl (Join-Path $deps $OllamaInstalador)

# --- 3) Staging del servidor -------------------------------------
Paso 'Preparando archivos del servidor...'
$webDest = Join-Path $stag 'web'
if (Test-Path $webDest) { Remove-Item $webDest -Recurse -Force }
Copy-Item (Join-Path $proyecto 'frontend\build\web') -Destination $webDest -Recurse

$ctxDest = Join-Path $stag 'contexto'
if (Test-Path $ctxDest) { Remove-Item $ctxDest -Recurse -Force }
Copy-Item (Join-Path $proyecto 'backend\contexto') -Destination $ctxDest -Recurse

New-Item -ItemType Directory -Force -Path (Join-Path $stag 'doc') | Out-Null
Copy-Item (Join-Path $proyecto 'backend\doc\openapi.json') (Join-Path $stag 'doc\openapi.json') -Force
Ok 'web + contexto + doc copiados'

# --- 3b) Modelo de Ollama (para instalar en PC sin internet) -----
# Se copia el store completo de .ollama\models (manifests + blobs);
# en la PC destino se instala en %USERPROFILE%\.ollama\models, que es
# la ubicacion por defecto de Ollama: el asistente queda listo sin
# necesitar internet ni "ollama create".
$origenModelos = Join-Path $env:USERPROFILE '.ollama\models'
$modeloDest    = Join-Path $raiz 'staging\ollama-modelos'
$manifesto = Join-Path $origenModelos 'manifests\registry.ollama.ai\library\ventas-qwen2.5-1.5b\latest'
if (Test-Path $manifesto) {
    Paso 'Copiando el modelo de Ollama al paquete (1 GB)...'
    if (Test-Path $modeloDest) { Remove-Item $modeloDest -Recurse -Force }
    Copy-Item $origenModelos -Destination $modeloDest -Recurse
    Ok 'modelo ventas-qwen2.5-1.5b listo para el USB'
} else {
    Falta 'modelo ventas-qwen2.5-1.5b local: sin el, la PC destino lo descargara desde el chat'
    if (Test-Path $modeloDest) { Remove-Item $modeloDest -Recurse -Force }
}

# --- 4) .env de produccion ---------------------------------------
$pgDump = "C:\Program Files\PostgreSQL\$PgMayoria\bin\pg_dump.exe"
$envContenido = @"
# Generado por instalador\preparar.ps1 — entorno de produccion
HOST=0.0.0.0
PORT=8080
APP_ENV=production
DOCS_ENABLED=true
CORS_ORIGINS=
LOGIN_RATE_MAX=10
LOGIN_RATE_WINDOW=300
BODY_MAX_MB=5

DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=ventas
DB_USER=postgres
DB_PASSWORD=$ClaveDB
DB_SSL_MODE=disable
DB_POOL_MAX=10
PG_DUMP_BIN=$pgDump

OLLAMA_URL=http://127.0.0.1:11434
CHAT_MODEL=ventas-qwen2.5-1.5b
MODELOS_DIR=models
CHAT_HF_URL=https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf
CHAT_CONTEXTO=contexto/asistente.md

UPLOADS_DIR=uploads
BACKUPS_DIR=backups
"@
Set-Content -Path (Join-Path $stag '.env') -Value $envContenido -Encoding ASCII
Ok ".env generado (DB_PASSWORD=$ClaveDB)"

# --- 5) iniciar.ps1 (lanzador oculto: sin ventanas de consola) ---
Remove-Item (Join-Path $stag 'iniciar.bat') -Force -ErrorAction SilentlyContinue
$ps1 = @'
# Inicia la API y la web OCULTAS (sin ventanas) y abre la app de escritorio.
# Los logs de los servidores quedan en logs\ por si hay que diagnosticar.
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($d in 'models', 'uploads', 'backups', 'logs') {
    $ruta = Join-Path $raiz $d
    if (-not (Test-Path $ruta)) { New-Item -ItemType Directory -Path $ruta -ErrorAction SilentlyContinue | Out-Null }
}
function PuertoLibre($puerto) {
    $conn = Get-NetTCPConnection -LocalPort $puerto -State Listen -ErrorAction SilentlyContinue
    return $null -eq $conn
}
if (PuertoLibre 8080) {
    Start-Process -FilePath (Join-Path $raiz 'api\bundle\bin\server.exe') `
        -WorkingDirectory $raiz -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $raiz 'logs\api.log') `
        -RedirectStandardError (Join-Path $raiz 'logs\api.err.log')
}
if (PuertoLibre 8081) {
    Start-Process -FilePath (Join-Path $raiz 'webserver\bundle\bin\serve_web.exe') `
        -WorkingDirectory $raiz -ArgumentList '--dir', 'web' -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $raiz 'logs\web.log') `
        -RedirectStandardError (Join-Path $raiz 'logs\web.err.log')
}
if (PuertoLibre 11434) {
    $ollama = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
        'C:\Program Files\Ollama\ollama.exe'
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($ollama) {
        Start-Process -FilePath $ollama -ArgumentList 'serve' -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $raiz 'logs\ollama.log') `
            -RedirectStandardError (Join-Path $raiz 'logs\ollama.err.log')
    }
}
Start-Sleep -Seconds 3
$desktop = Join-Path $raiz 'app\ventas.exe'
if (Test-Path $desktop) {
    Start-Process -FilePath $desktop -WorkingDirectory (Join-Path $raiz 'app')
} else {
    Start-Process 'http://localhost:8081'
}
'@
$ps1 = ($ps1 -split "`n" | ForEach-Object { $_.TrimEnd("`r") }) -join "`r`n"
Set-Content -Path (Join-Path $stag 'iniciar.ps1') -Value $ps1 -Encoding UTF8
Ok 'iniciar.ps1 generado (lanzamiento oculto)'

# --- 6) crear_bd.ps1 (se ejecuta en la PC destino tras PG) -------
$crearBd = @'
# Crea la BD "ventas" si no existe (reintenta mientras PG arranca)
param([string]$Clave = '')
$bin = 'C:\Program Files\PostgreSQL\__PGMAJ__\bin'
$env:PGPASSWORD = $Clave
for ($i = 0; $i -lt 45; $i++) {
    if (Test-Path "$bin\psql.exe") {
        $existe = & "$bin\psql.exe" -U postgres -h localhost -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='ventas'" 2>$null
        if ("$existe".Trim() -eq '1') { exit 0 }
        & "$bin\createdb.exe" -U postgres -h localhost ventas 2>$null
        if ($LASTEXITCODE -eq 0) { exit 0 }
    }
    Start-Sleep -Seconds 2
}
exit 0
'@
$crearBd = $crearBd.Replace('__PGMAJ__', $PgMayoria)
$crearBd = ($crearBd -split "`n" | ForEach-Object { $_.TrimEnd("`r") }) -join "`r`n"
Set-Content -Path (Join-Path $stag 'crear_bd.ps1') -Value $crearBd -Encoding UTF8
Ok 'crear_bd.ps1 generado'

# --- 7) config.iss (defines compartidos con Ventas.iss) --------
$configIss = @"
#define AppVersion "$VersionApp"
#define ClaveDB "$ClaveDB"
#define PgInstalador "$PgInstalador"
#define PgMayoria "$PgMayoria"
"@
Set-Content -Path (Join-Path $raiz 'config.iss') -Value $configIss -Encoding ASCII
Ok 'config.iss generado'

# --- 8) Inno Setup ------------------------------------------------
Paso 'Buscando Inno Setup...'
function BuscarISCC {
    @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
$iscc = BuscarISCC
if (-not $iscc) {
    Paso 'Instalando Inno Setup con winget (solo la primera vez)...'
    winget install --id JRSoftware.InnoSetup --exact --silent --accept-package-agreements --accept-source-agreements | Out-Null
    $iscc = BuscarISCC
}
if (-not $iscc) {
    Write-Host 'No encontre ISCC.exe. Instala Inno Setup 6 desde https://jrsoftware.org/isdl.php y vuelve a ejecutar.' -ForegroundColor Red
    exit 1
}
Ok "ISCC: $iscc"

# --- 9) Compilar el instalador ------------------------------------
Paso 'Compilando Ventas-Setup.exe (esto tarda unos minutos)...'
& $iscc (Join-Path $raiz 'Ventas.iss')
if ($LASTEXITCODE -ne 0) {
    Write-Host 'ISCC fallo, revisa los errores de arriba.' -ForegroundColor Red
    exit 1
}

$setup = Join-Path $salida "Ventas-Setup-$VersionApp.exe"
if (-not (Test-Path $setup)) { Write-Host 'No salio el .exe, revisa ISCC.' -ForegroundColor Red; exit 1 }
$mb = [math]::Round((Get-Item $setup).Length / 1MB, 1)
Write-Host ''
Write-Host "LISTO: $setup  ($mb MB)" -ForegroundColor Green
Write-Host 'Copia ese .exe a la otra PC y ejecutalo (doble clic).' -ForegroundColor Green
