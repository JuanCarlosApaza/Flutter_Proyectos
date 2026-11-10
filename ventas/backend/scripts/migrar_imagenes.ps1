<#
.SYNOPSIS
  Migra las imágenes de los productos de URL externa (picsum.photos) a
  almacenamiento local en el backend.

.DESCRIPTION
  Para cada producto cuya columna `imagen` es una URL http(s):
    1. descarga el binario,
    2. lo sube como base64 a POST /api/v1/archivos/imagenes,
    3. reescribe el producto con PUT /api/v1/productos/{id} usando la ruta
       local devuelta (/api/v1/archivos/imagenes/<fichero>).

  Los productos sin imagen o con imagen ya local se tocan. Se puede ejecutar
  tantas veces como haga falta (es idempotente).

.EXAMPLE
  .\scripts\migrar_imagenes.ps1
  .\scripts\migrar_imagenes.ps1 -Base http://localhost:8080 -DryRun
#>
param(
  [string]$Base = 'http://localhost:8080',
  [int]$Limit = 200,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'migrar_imagenes'
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

function Invoke-Curl([string[]]$ArgumentList) {
  $out = & curl.exe --noproxy '*' -s @ArgumentList
  if ($LASTEXITCODE -ne 0) { throw "curl falló ($LASTEXITCODE): $($ArgumentList -join ' ')" }
  return ($out -join '')
}

Write-Host "Consultando productos en $Base ..." -ForegroundColor Cyan
$productos = Invoke-Curl @('-H', 'accept: application/json', "$Base/api/v1/productos?limit=$Limit") |
  ConvertFrom-Json

$pendientes = @($productos.items | Where-Object {
  $_.imagen -and $_.imagen -match '^https?://'
})

Write-Host "Productos con imagen externa: $($pendientes.Count) de $($productos.items.Count)"

$migradas = 0
$fallidas = 0
$omitidas = 0

foreach ($p in $pendientes) {
  if ($DryRun) {
    Write-Host "  [dry-run] #$($p.id) $($p.nombre) -> $($p.imagen)" -ForegroundColor DarkGray
    $omitidas++
    continue
  }

  $rutaImagen = Join-Path $tmp "producto-$($p.id).img"
  & curl.exe --noproxy '*' -sL -o $rutaImagen $p.imagen
  $descargada = (Test-Path $rutaImagen) -and ((Get-Item $rutaImagen).Length -gt 0)
  if ($LASTEXITCODE -ne 0 -or -not $descargada) {
    Write-Host "  FALLA descarga #$($p.id) $($p.imagen)" -ForegroundColor Red
    $fallidas++
    continue
  }

  try {
    $bytes = [System.IO.File]::ReadAllBytes($rutaImagen)
    $cuerpo = @{ nombre = "producto-$($p.id).jpg"; datos = [Convert]::ToBase64String($bytes) } |
      ConvertTo-Json -Compress

    $rutaJson = Join-Path $tmp "upload-$($p.id).json"
    [System.IO.File]::WriteAllText($rutaJson, $cuerpo)

    $subida = Invoke-Curl @(
      '-X', 'POST', "$Base/api/v1/archivos/imagenes",
      '-H', 'content-type: application/json',
      "--data-binary", "@$rutaJson"
    ) | ConvertFrom-Json

    $rutaLocal = $subida.ruta
    $actualizacion = @{ imagen = $rutaLocal } | ConvertTo-Json -Compress
    $rutaPut = Join-Path $tmp "put-$($p.id).json"
    [System.IO.File]::WriteAllText($rutaPut, $actualizacion)

    Invoke-Curl @(
      '-X', 'PUT', "$Base/api/v1/productos/$($p.id)",
      '-H', 'content-type: application/json',
      "--data-binary", "@$rutaPut"
    ) | Out-Null

    Write-Host "  OK #$($p.id) $($p.nombre) -> $rutaLocal" -ForegroundColor Green
    $migradas++
  } catch {
    Write-Host "  FALLA #$($p.id) $($p.nombre): $($_.Exception.Message)" -ForegroundColor Red
    $fallidas++
  } finally {
    Remove-Item -Path $rutaImagen -ErrorAction SilentlyContinue
  }
}

Write-Host ""
Write-Host "Migradas: $migradas   Fallidas: $fallidas   Ya locales/sin imagen: $($productos.items.Count - $pendientes.Count)" -ForegroundColor Cyan
if ($fallidas -gt 0) { exit 1 }
