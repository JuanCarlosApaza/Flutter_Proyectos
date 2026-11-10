# Smoke test de la API de la tienda (backend Dart + Shelf + PostgreSQL).
#
# Recorre TODOS los grupos de endpoints contra el servidor en marcha y
# comprueba códigos de estado y reglas de negocio. No borra datos: crea un
# conjunto de prueba con sufijo "[smoke]".
#
# Uso:
#   .\scripts\smoke_test.ps1 -Usuario maria.elena.quispe1 -Contrasena 'secreto123'
#   .\scripts\smoke_test.ps1 -Base http://localhost:9000 -Usuario ... -Contrasena ...
#
# Desde la terminal también valen las variables de entorno SMOKE_USUARIO y
# SMOKE_CONTRASENA (evita que la contraseña quede en el historial).
#
# Todas las rutas de la API exigen sesión, así que el script primero hace
# login y luego repite el resto de comprobaciones con `Authorization: Bearer`.
param(
  [string]$Base = 'http://localhost:8080',
  [string]$Usuario = $env:SMOKE_USUARIO,
  [string]$Contrasena = $env:SMOKE_CONTRASENA
)

$ErrorActionPreference = 'Stop'
$script:ok = 0
$script:fail = 0
$script:token = $null

function Api([string]$Method, [string]$Path, $Body = $null) {
  $params = @{ Uri = "$Base$Path"; Method = $Method; UseBasicParsing = $true; TimeoutSec = 20 }
  if ($null -ne $Body) {
    $params.Body = ($Body | ConvertTo-Json -Depth 8)
    $params.ContentType = 'application/json'
  }
  if ($script:token) {
    $params.Headers = @{ Authorization = "Bearer $script:token" }
  }
  try {
    $resp = Invoke-WebRequest @params
    return @{ status = [int]$resp.StatusCode; body = $resp.Content }
  } catch {
    $response = $_.Exception.Response
    if ($response) {
      $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
      return @{ status = [int]$response.StatusCode; body = $reader.ReadToEnd() }
    }
    return @{ status = 0; body = $_.Exception.Message }
  }
}

function Check([string]$name, [int]$actual, [int]$expected, [string]$detail = '') {
  if ($actual -eq $expected) {
    $script:ok++
    "  OK   $name -> $actual"
  } else {
    $script:fail++
    "  FAIL $name -> $actual (esperado $expected) $detail"
  }
}

function Id-De([string]$json) { return ($json | ConvertFrom-Json).id }

Write-Host "`n=== Esperando al servidor en $Base ===" -ForegroundColor Cyan
$disponible = $false
for ($i = 0; $i -lt 30; $i++) {
  $health = Api GET '/api/v1/health'
  if ($health.status -eq 200) { $disponible = $true; break }
  Start-Sleep -Seconds 1
}
if (-not $disponible) {
  Write-Host "No responde. Arranca el backend: dart run bin/server.dart" -ForegroundColor Red
  exit 1
}
Check 'GET /api/v1/health' $health.status 200

# --- Autenticación ----------------------------------------------------------
Write-Host "`n=== Autenticación ===" -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($Usuario) -or [string]::IsNullOrWhiteSpace($Contrasena)) {
  Write-Host "AVISO: faltan -Usuario/-Contrasena (o SMOKE_USUARIO/SMOKE_CONTRASENA)." -ForegroundColor Yellow
  Write-Host "       Se omiten las pruebas de login; el resto fallará con 401." -ForegroundColor Yellow
} else {
  # Sin token -> 401 en cualquier ruta protegida
  $r = Api GET '/api/v1/usuarios'
  Check 'Acceso sin token' $r.status 401

  # Login con contraseña incorrecta -> 401
  $r = Api POST '/api/v1/auth/login' @{ nombreUsuario = $Usuario; contrasena = "mala-$([guid]::NewGuid().ToString('N'))" }
  Check 'Login con contraseña incorrecta' $r.status 401

  # Login correcto -> 200 y token
  $r = Api POST '/api/v1/auth/login' @{ nombreUsuario = $Usuario; contrasena = $Contrasena }
  Check 'Login correcto' $r.status 200
  if ($r.status -eq 200) {
    $script:token = ($r.body | ConvertFrom-Json).token
    if ($script:token) { "  OK   Token emitido" ; $script:ok++ }
    else { "  FAIL Login sin token en la respuesta" ; $script:fail++ }
  }

  if ($script:token) {
    $r = Api GET '/api/v1/auth/me'
    Check 'GET /auth/me con sesión' $r.status 200

    # Logout -> 200 y token invalidado en el servidor
    $r = Api POST '/api/v1/auth/logout'
    Check 'POST /auth/logout' $r.status 200

    $r = Api GET '/api/v1/auth/me'
    Check 'Token invalidado tras logout' $r.status 401

    # Re-login: el resto de grupos necesita sesión
    $r = Api POST '/api/v1/auth/login' @{ nombreUsuario = $Usuario; contrasena = $Contrasena }
    if ($r.status -eq 200) {
      $script:token = ($r.body | ConvertFrom-Json).token
      "  OK   Re-login para el resto de pruebas" ; $script:ok++
    } else {
      "  FAIL Re-login -> $($r.status)" ; $script:fail++
    }
  }
}

# --- Categorías, tallas y colores -------------------------------------------
Write-Host "`n=== Categorías, tallas y colores ===" -ForegroundColor Cyan
$r = Api POST '/api/v1/categorias' @{ nombre = 'Analgésicos [smoke]'; estado = 'ACTIVO' }
Check 'POST /categorias' $r.status 201
$catId = Id-De $r.body

Check 'POST /categorias con estado inválido (400)' (Api POST '/api/v1/categorias' @{ nombre = 'X'; estado = 'FALSO' }).status 400
Check 'POST /categorias sin nombre (400)' (Api POST '/api/v1/categorias' @{ estado = 'ACTIVO' }).status 400
Check 'POST /categorias nombre de 1 letra (400)' (Api POST '/api/v1/categorias' @{ nombre = 'A' }).status 400
Check 'GET /categorias' (Api GET '/api/v1/categorias').status 200
Check 'GET /categorias inexistente (404)' (Api GET "/api/v1/categorias/999999").status 404
Check 'PUT /categorias/{id}' (Api PUT "/api/v1/categorias/$catId" @{ estado = 'INACTIVO' }).status 200
Check 'DELETE /categorias/{id}' (Api DELETE "/api/v1/categorias/$catId").status 204

# Borrado lógico: la fila NO se borra, solo pasa a estado ELIMINADO.
$oculta = Api GET "/api/v1/categorias/$catId"
Check 'GET /categorias/{id} oculta sigue en la BD (200)' $oculta.status 200
if ($oculta.body -match '"estado":"ELIMINADO"') {
  $script:ok++; "  OK   GET /categorias/{id} -> estado ELIMINADO"
} else {
  $script:fail++; "  FAIL GET /categorias/{id} estado ELIMINADO -> $($oculta.body)"
}
$lista = Api GET '/api/v1/categorias?limit=200'
if ($lista.body -match "`"id`":$catId,") {
  $script:fail++; "  FAIL el listado no debe mostrar el registro oculto ($catId)"
} else {
  $script:ok++; "  OK   listado oculta el registro ($catId)"
}
Check 'GET /categorias?estado=ELIMINADO' (Api GET '/api/v1/categorias?estado=ELIMINADO').status 200
Check 'DELETE repetido del registro oculto (404)' (Api DELETE "/api/v1/categorias/$catId").status 404

# Tallas y colores: el catálogo de la prenda (sustituye a las antiguas
# «presentaciones», fuera del esquema desde la migración 017_ropa). Los nombres
# son únicos en la BD, así que se randomizan para no chocar con lo que dejó una
# corrida anterior.
$sufijo = [guid]::NewGuid().ToString('N').Substring(0, 6)
$r = Api POST '/api/v1/tallas' @{ nombre = "T $sufijo [smoke]"; orden = 99 }
Check 'POST /tallas' $r.status 201
$tallaId = Id-De $r.body
Check 'GET /tallas' (Api GET '/api/v1/tallas').status 200
Check 'GET /tallas/{id}' (Api GET "/api/v1/tallas/$tallaId").status 200
Check 'POST /tallas sin nombre (400)' (Api POST '/api/v1/tallas' @{ orden = 1 }).status 400
Check 'PUT /tallas/{id}' (Api PUT "/api/v1/tallas/$tallaId" @{ orden = 98 }).status 200
Check 'DELETE /tallas/{id}' (Api DELETE "/api/v1/tallas/$tallaId").status 204
Check 'DELETE /tallas inexistente (404)' (Api DELETE '/api/v1/tallas/999999').status 404

$r = Api POST '/api/v1/colores' @{ nombre = "C $sufijo [smoke]"; codigoHex = '#336699' }
Check 'POST /colores' $r.status 201
$colorId = Id-De $r.body
Check 'GET /colores' (Api GET '/api/v1/colores').status 200
Check 'GET /colores/{id}' (Api GET "/api/v1/colores/$colorId").status 200
Check 'POST /colores sin nombre (400)' (Api POST '/api/v1/colores' @{ codigoHex = '#000000' }).status 400
Check 'PUT /colores/{id}' (Api PUT "/api/v1/colores/$colorId" @{ codigoHex = '#112233' }).status 200
Check 'DELETE /colores/{id}' (Api DELETE "/api/v1/colores/$colorId").status 204
Check 'DELETE /colores inexistente (404)' (Api DELETE '/api/v1/colores/999999').status 404

# --- Personas --------------------------------------------------------------
Write-Host "`n=== Personas ===" -ForegroundColor Cyan
$ci = Get-Random -Minimum 10000000 -Maximum 99999999
$r = Api POST '/api/v1/proveedores' @{ nombre = 'Distribuidora Salud [smoke]'; ciudad = 'Lima' }
Check 'POST /proveedores' $r.status 201
$provId = Id-De $r.body
Check 'GET /proveedores' (Api GET '/api/v1/proveedores').status 200
Check 'PUT /proveedores/{id}' (Api PUT "/api/v1/proveedores/$provId" @{ telefono = '555-1234' }).status 200
Check 'DELETE /proveedores/{id}' (Api DELETE "/api/v1/proveedores/$provId").status 204

$r = Api POST '/api/v1/clientes' @{ nombre = 'María Pérez [smoke]'; apellido = 'Pérez'; ci = "$ci"; genero = 'F' }
Check 'POST /clientes' $r.status 201
$cliId = Id-De $r.body
Check 'POST /clientes sin apellido (400)' (Api POST '/api/v1/clientes' @{ nombre = 'Sin Apellido' }).status 400
Check 'POST /clientes con género inválido (400)' (Api POST '/api/v1/clientes' @{ nombre = 'Xz'; apellido = 'Yz'; genero = 'Z' }).status 400
Check 'POST /clientes con CI de 6 dígitos (400)' (Api POST '/api/v1/clientes' @{ nombre = 'CI Corto'; apellido = 'Corto'; ci = '123456' }).status 400
Check 'POST /clientes con teléfono con letras (400)' (Api POST '/api/v1/clientes' @{ nombre = 'Tel Malo'; apellido = 'Mal'; telefono = 'llamar-33' }).status 400
Check 'POST /clientes nombre de 1 letra (400)' (Api POST '/api/v1/clientes' @{ nombre = 'A'; apellido = 'Mal' }).status 400
$ciValido = Get-Random -Minimum 10000000 -Maximum 99999999
$r = Api POST '/api/v1/clientes' @{ nombre = 'Cliente Valido [smoke]'; apellido = 'Válido'; ci = "$ciValido"; telefono = '+51 999 888 777' }
Check 'POST /clientes con CI y teléfono válidos (201)' $r.status 201
if ($r.status -eq 201) {
  Check 'DELETE cliente de validación (204)' (Api DELETE "/api/v1/clientes/$(Id-De $r.body)").status 204
}
Check 'GET /clientes' (Api GET '/api/v1/clientes').status 200
Check 'PUT /clientes/{id} (parcial)' (Api PUT "/api/v1/clientes/$cliId" @{ ciudad = 'Arequipa' }).status 200
Check 'PUT /clientes/{id} apellido vacío (400)' (Api PUT "/api/v1/clientes/$cliId" @{ apellido = '' }).status 400
Check 'DELETE /clientes/{id}' (Api DELETE "/api/v1/clientes/$cliId").status 204

$r = Api POST '/api/v1/empleados' @{ nombre = 'Juan Vargas [smoke]'; apellido = 'Vargas'; ciudad = 'Cochabamba'; edad = 25 }
Check 'POST /empleados' $r.status 201
$empId = Id-De $r.body
Check 'POST /empleados sin apellido (400)' (Api POST '/api/v1/empleados' @{ nombre = 'Sin Apellido' }).status 400
Check 'POST /empleados con edad < 18 (400)' (Api POST '/api/v1/empleados' @{ nombre = 'Edad Baja'; apellido = 'Baja'; edad = 15 }).status 400
Check 'GET /empleados' (Api GET '/api/v1/empleados').status 200
Check 'GET /empleados?estado=ACTIVO (enum propio)' (Api GET '/api/v1/empleados?estado=ACTIVO').status 200
Check 'GET /empleados?estado=VACACIONES' (Api GET '/api/v1/empleados?estado=VACACIONES').status 200
# `cargo` dejó de existir (la ficha del empleado son nombre, contacto y estado).
Check 'PUT /empleados/{id}' (Api PUT "/api/v1/empleados/$empId" @{ ciudad = 'La Paz' }).status 200
Check 'PUT /empleados/{id} sin campos (400)' (Api PUT "/api/v1/empleados/$empId" @{}).status 400

# --- Usuarios --------------------------------------------------------------
Write-Host "`n=== Usuarios ===" -ForegroundColor Cyan
# El nivel de acceso ya no es texto libre: se asigna por `rolId` (catálogo
# en GET /roles). Se toma el id del rol ADMIN sembrado por la migración 009.
$rolesBody = (Api GET '/api/v1/roles').body | ConvertFrom-Json
$rolAdminId = [int](($rolesBody.items | Where-Object { $_.nombre -eq 'ADMIN' }).id)
Check 'GET /roles' (Api GET '/api/v1/roles').status 200
Check 'GET /roles devuelve permisos' ([int]($rolesBody.items[0].permisos.Count -gt 0)) 1
$usuNombre = "cjaime$(Get-Random -Minimum 10000 -Maximum 99999)_smoke"
$r = Api POST '/api/v1/usuarios' @{
  nombreUsuario = $usuNombre
  contrasena = 'secreto123'
  rolId = $rolAdminId
  empleadoId = [int]$empId
}
Check 'POST /usuarios' $r.status 201
Check 'POST /usuarios con nombre de usuario corto (400)' (Api POST '/api/v1/usuarios' @{ nombreUsuario = 'ab'; contrasena = 'secreto123'; rolId = $rolAdminId }).status 400
Check 'POST /usuarios con contraseña corta (400)' (Api POST '/api/v1/usuarios' @{ nombreUsuario = 'usuario.valido.smoke'; contrasena = '123'; rolId = $rolAdminId }).status 400
Check 'POST /usuarios sin rolId (400)' (Api POST '/api/v1/usuarios' @{ nombreUsuario = 'sinrol.smoke'; contrasena = 'secreto123' }).status 400
Check 'POST /usuarios con rol inexistente (404)' (Api POST '/api/v1/usuarios' @{ nombreUsuario = 'rolfalso.smoke'; contrasena = 'secreto123'; rolId = 999999 }).status 404
$usuId = Id-De $r.body
$listaUsuarios = (Api GET '/api/v1/usuarios').body
if ($listaUsuarios -match 'contrasena') {
  $script:fail++
  '  FAIL GET /usuarios no debe exponer "contrasena"'
} else {
  $script:ok++
  '  OK   GET /usuarios no expone la contraseña'
}
# Cambiar la contraseña exige `claveAdmin` con la clave del propio actor.
Check 'PUT /usuarios/{id} (cambiar contraseña)' (Api PUT "/api/v1/usuarios/$usuId" @{ contrasena = 'secreto456'; claveAdmin = $Contrasena }).status 200
Check 'PUT /usuarios/{id} cambiar contraseña sin claveAdmin (400)' (Api PUT "/api/v1/usuarios/$usuId" @{ contrasena = 'secreto789' }).status 400

# --- Roles (RBAC) -----------------------------------------------------------
Write-Host "`n=== Roles ===" -ForegroundColor Cyan
# El nombre del rol es único en la BD (también entre los ocultos), así que se
# randomiza: una corrida anterior que dejó su «SMOKE ROL» no lo tumba.
$r = Api POST '/api/v1/roles' @{ nombre = "SMOKE ROL $([guid]::NewGuid().ToString('N').Substring(0, 6))"; descripcion = 'Rol de prueba'; permisos = @('ventas.ver', 'ventas.crear') }
Check 'POST /roles' $r.status 201
$rolId = Id-De $r.body
Check 'PUT /roles/{id} (permisos)' (Api PUT "/api/v1/roles/$rolId" @{ permisos = @('ventas.ver') }).status 200
Check 'PUT /roles/{id} con permiso desconocido (400)' (Api PUT "/api/v1/roles/$rolId" @{ permisos = @('nada.hacer') }).status 400
Check 'PUT /roles ADMIN (409)' (Api PUT "/api/v1/roles/$rolAdminId" @{ descripcion = 'x' }).status 409
Check 'POST /roles duplicado (409)' (Api POST '/api/v1/roles' @{ nombre = 'ADMIN' }).status 409
Check 'DELETE /roles ADMIN es de sistema (409)' (Api DELETE "/api/v1/roles/$rolAdminId").status 409
# El rol creado no tiene usuarios: su borrado lógico debe salir bien.
$sinUsuarios = (Api GET '/api/v1/usuarios?limit=200').body | ConvertFrom-Json
if (-not ($sinUsuarios.items | Where-Object { $_.rolId -eq $rolId })) {
  Check 'DELETE /roles/{id} sin uso' (Api DELETE "/api/v1/roles/$rolId").status 204
}

# --- Archivos (imágenes) -----------------------------------------------------
Write-Host "`n=== Archivos (imágenes) ===" -ForegroundColor Cyan
# PNG mínimo: la API valida los magic bytes, no la extensión declarada.
# La subida exige sesión (solo la lectura GET es pública), así que sin token
# se omiten las comprobaciones de POST.
[byte[]]$contenido = [byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A) + (New-Object byte[] 128)
if ($script:token) {
  $r = Api POST '/api/v1/archivos/imagenes' @{ nombre = 'smoke.png'; datos = [Convert]::ToBase64String($contenido) }
  Check 'POST /archivos/imagenes' $r.status 201
  $rutaImagen = ($r.body | ConvertFrom-Json).ruta
  Check 'GET /archivos/imagenes/{nombre}' (Api GET $rutaImagen).status 200
  Check 'POST /archivos/imagenes sin datos (400)' (Api POST '/api/v1/archivos/imagenes' @{ nombre = 'x.png' }).status 400
  Check 'POST /archivos/imagenes con binario no imagen (400)' (Api POST '/api/v1/archivos/imagenes' @{ nombre = 'x.png'; datos = 'aGVsbG8=' }).status 400
} else {
  Check 'POST /archivos/imagenes sin sesión (401)' (Api POST '/api/v1/archivos/imagenes' @{ nombre = 'smoke.png'; datos = [Convert]::ToBase64String($contenido) }).status 401
}
Check 'GET /archivos/imagenes inexistente (404)' (Api GET '/api/v1/archivos/imagenes/noexiste12345.jpg').status 404

# --- Productos -------------------------------------------------------------
Write-Host "`n=== Productos ===" -ForegroundColor Cyan
$r = Api POST '/api/v1/products' @{
  nombre = 'Camiseta básica 600 [smoke]'
  imagen = $rutaImagen
  precioVenta = 2.45
  precioCompra = 1.20
  stock = 20
  categoriaId = $null
  estado = 'DISPONIBLE'
}
Check 'POST /products' $r.status 201
$prodId = Id-De $r.body
Check 'POST /products con precio negativo (400)' (Api POST '/api/v1/products' @{ nombre = 'X'; precioVenta = -1 }).status 400
Check 'POST /products sin precioVenta (400)' (Api POST '/api/v1/products' @{ nombre = 'X' }).status 400
Check 'GET /products' (Api GET '/api/v1/products').status 200
Check 'GET /products?estado=DISPONIBLE' (Api GET '/api/v1/products?estado=DISPONIBLE').status 200
Check 'GET /products?estado=INVALIDO (400)' (Api GET '/api/v1/products?estado=INVALIDO').status 400
Check 'GET /products/{id}' (Api GET "/api/v1/products/$prodId").status 200
Check 'GET /products inexistente (404)' (Api GET '/api/v1/products/999999').status 404
# El stock ya no se edita en el producto: es el agregado de sus variantes.
Check 'PUT /products/{id} (parcial)' (Api PUT "/api/v1/products/$prodId" @{ stockMinimo = 5 }).status 200
Check 'PUT /products/{id} no admite stock (400)' (Api PUT "/api/v1/products/$prodId" @{ stock = 12 }).status 400
Check 'PUT /products/{id} con estado inválido (400)' (Api PUT "/api/v1/products/$prodId" @{ estado = 'POR_VENCER' }).status 400

# --- Validaciones de precios, stock y nombres --------------------------------
Check 'POST /products precioVenta = 0 (400)' (Api POST '/api/v1/products' @{ nombre = 'X'; precioVenta = 0 }).status 400
Check 'POST /products venta menor que compra (400)' (Api POST '/api/v1/products' @{ nombre = 'X'; precioVenta = 2.00; precioCompra = 3.50 }).status 400
Check 'POST /products con unidad distinta de UN (400)' (Api POST '/api/v1/products' @{ nombre = 'X'; precioVenta = 1.50; unidad = 'KG' }).status 400
Check 'POST /products stock negativo (400)' (Api POST '/api/v1/products' @{ nombre = 'X'; precioVenta = 1.50; stock = -1 }).status 400
Check 'POST /products nombre de 1 letra (400)' (Api POST '/api/v1/products' @{ nombre = 'A'; precioVenta = 1.50 }).status 400
Check 'PUT /products precioVenta = 0 (400)' (Api PUT "/api/v1/products/$prodId" @{ precioVenta = 0 }).status 400
Check 'PUT /products solo compra > venta (400)' (Api PUT "/api/v1/products/$prodId" @{ precioCompra = 999 }).status 400

# --- Variantes (talla + color: el stock real, migración 017_ropa) ------------
Write-Host "`n=== Variantes de producto (talla + color) ===" -ForegroundColor Cyan
$rVar = Api POST '/api/v1/products' @{
  nombre = 'Pantalón con variantes [smoke]'
  precioVenta = 10.0
  stock = 4
  estado = 'DISPONIBLE'
}
Check 'POST /products con su variante única (201)' $rVar.status 201
$prodVar = Id-De $rVar.body
$rListaVars = Api GET "/api/v1/productos/$prodVar/variantes"
Check 'GET /productos/{id}/variantes' $rListaVars.status 200
$vars = $rListaVars.body | ConvertFrom-Json
if ($vars.items.Count -eq 1 -and [math]::Abs($vars.items[0].stock - 4) -lt 0.001) {
  $script:ok++; "  OK   el producto nace con una variante (talla '$($vars.items[0].talla)', color '$($vars.items[0].color)') con stock 4"
} else {
  $script:fail++; "  FAIL variantes iniciales: $($vars | ConvertTo-Json -Depth 5 -Compress)"
}

# La segunda combinación se arma con el catálogo sembrado (sin «Única»: esa
# ya la ocupó la variante automática del producto).
$tallasCat = (Api GET '/api/v1/tallas?limit=200').body | ConvertFrom-Json
$coloresCat = (Api GET '/api/v1/colores?limit=200').body | ConvertFrom-Json
$tallaNueva = $tallasCat.items | Where-Object { $_.nombre -ne 'Única' } | Select-Object -First 1
$colorNuevo = $coloresCat.items | Where-Object { $_.nombre -ne 'Único' } | Select-Object -First 1

Check 'POST /variantes sin talla/color (400)' (Api POST "/api/v1/productos/$prodVar/variantes" @{ stock = 1 }).status 400
Check 'POST /variantes con talla inexistente (400)' (Api POST "/api/v1/productos/$prodVar/variantes" @{ tallaId = 999999; colorId = [int]$colorNuevo.id; stock = 1 }).status 400
$rNuevaVar = Api POST "/api/v1/productos/$prodVar/variantes" @{ tallaId = [int]$tallaNueva.id; colorId = [int]$colorNuevo.id; stock = 7 }
Check 'POST /productos/{id}/variantes (201)' $rNuevaVar.status 201
$nuevaVarId = Id-De $rNuevaVar.body
Check 'POST /variantes duplicada (409)' (Api POST "/api/v1/productos/$prodVar/variantes" @{ tallaId = [int]$tallaNueva.id; colorId = [int]$colorNuevo.id; stock = 1 }).status 409

# El stock del producto es la suma de sus variantes visibles (4 + 7).
$stockProdVar = [double]((Api GET "/api/v1/products/$prodVar").body | ConvertFrom-Json).stock
if ([math]::Abs($stockProdVar - 11) -lt 0.001) {
  $script:ok++; "  OK   stock del producto = suma de variantes (4 + 7 = $stockProdVar)"
} else {
  $script:fail++; "  FAIL stock del producto: $stockProdVar (esperado 11)"
}

Check 'PUT /variantes/{id} (stock)' (Api PUT "/api/v1/variantes/$nuevaVarId" @{ stock = 6 }).status 200
Check 'PUT /variantes/{id} con stock negativo (400)' (Api PUT "/api/v1/variantes/$nuevaVarId" @{ stock = -1 }).status 400
Check 'DELETE /variantes con stock (409)' (Api DELETE "/api/v1/variantes/$nuevaVarId").status 409
Check 'DELETE /variantes inexistente (404)' (Api DELETE '/api/v1/variantes/999999').status 404

# Con dos variantes ya no se puede adivinar cuál vender: el item pide
# `varianteId` (400) mientras que el producto simple sigue vendiéndose solo.
Check 'POST /ordenes sin varianteId con 2 variantes (400)' (Api POST '/api/v1/ordenes' @{
  pagos = @(@{ metodoPago = 'EFECTIVO'; monto = 10.0 })
  items = @(@{ productoId = [int]$prodVar; cantidad = 1 })
}).status 400

Check 'PUT /variantes/{id} (stock a 0)' (Api PUT "/api/v1/variantes/$nuevaVarId" @{ stock = 0 }).status 200
Check 'DELETE /variantes/{id} (204)' (Api DELETE "/api/v1/variantes/$nuevaVarId").status 204
Check 'DELETE /products variantes (204)' (Api DELETE "/api/v1/products/$prodVar").status 204

# El código de producto es único en la BD (también entre los ocultos), así que
# se randomiza: repetirlo es un 409, no un duplicado a escondidas.
$codSmoke = "SMOKE-DUP-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$rCod1 = Api POST '/api/v1/products' @{
  nombre = 'Codigo A [smoke]'; precioVenta = 1; codigo = $codSmoke; estado = 'DISPONIBLE'
}
Check 'POST /products con código (201)' $rCod1.status 201
$rCod2 = Api POST '/api/v1/products' @{
  nombre = 'Codigo B [smoke]'; precioVenta = 1; codigo = $codSmoke; estado = 'DISPONIBLE'
}
Check 'POST /products código repetido (409)' $rCod2.status 409
if ($rCod1.status -eq 201) {
  Check 'DELETE /products código (204)' (Api DELETE "/api/v1/products/$(Id-De $rCod1.body)").status 204
}

# Redondeo a 2 decimales de los importes (columnas NUMERIC(10, 2))
$r = Api POST '/api/v1/products' @{ nombre = 'Redondeo [smoke]'; precioVenta = 2.456; precioCompra = 2.454; stock = 1; estado = 'DISPONIBLE' }
Check 'POST /products con precios de 3 decimales' $r.status 201
$red = $r.body | ConvertFrom-Json
if ($null -ne $red.id) {
  if ([math]::Abs($red.precioVenta - 2.46) -lt 0.001 -and [math]::Abs($red.precioCompra - 2.45) -lt 0.001) {
    $script:ok++; "  OK   importes redondeados (2.456 -> $($red.precioVenta), 2.454 -> $($red.precioCompra))"
  } else {
    $script:fail++; "  FAIL redondeo: venta=$($red.precioVenta) (esperado 2.46), compra=$($red.precioCompra) (esperado 2.45)"
  }
  Check 'DELETE /products redondeo (204)' (Api DELETE "/api/v1/products/$($red.id)").status 204
}

# --- Ventas ----------------------------------------------------------------
Write-Host "`n=== Ventas (órdenes, detalles y facturas) ===" -ForegroundColor Cyan
$r = Api POST '/api/v1/ordenes' @{
  pagos = @(@{ metodoPago = 'EFECTIVO'; monto = 7.35 })
  clienteId = $null
  nombreCliente = 'Cliente mostrador'
  items = @(@{ productoId = [int]$prodId; cantidad = 3 })
}
Check 'POST /ordenes' $r.status 201
$ordenId = ($r.body | ConvertFrom-Json).id
$total = ($r.body | ConvertFrom-Json).total
if ([math]::Abs($total - 7.35) -lt 0.001) {
  $script:ok++; "  OK   total de la orden = $total (3 x 2.45)"
} else {
  $script:fail++; "  FAIL total de la orden = $total (esperado 7.35)"
}
Check 'POST /ordenes sin items (400)' (Api POST '/api/v1/ordenes' @{ pagos = @(@{ metodoPago = 'EFECTIVO'; monto = 1.0 }); items = @() }).status 400
Check 'POST /ordenes sin pagos (400)' (Api POST '/api/v1/ordenes' @{ items = @(@{ productoId = [int]$prodId; cantidad = 1 }) }).status 400
Check 'POST /ordenes con pago que no cuadra (400)' (Api POST '/api/v1/ordenes' @{ pagos = @(@{ metodoPago = 'EFECTIVO'; monto = 1.0 }); items = @(@{ productoId = [int]$prodId; cantidad = 3 }) }).status 400
Check 'POST /ordenes con producto inexistente (404)' (Api POST '/api/v1/ordenes' @{ pagos = @(@{ metodoPago = 'EFECTIVO'; monto = 1.0 }); items = @(@{ productoId = 999999; cantidad = 1 }) }).status 404
Check 'POST /ordenes con más stock del disponible (409)' (Api POST '/api/v1/ordenes' @{ pagos = @(@{ metodoPago = 'EFECTIVO'; monto = 1.0 }); items = @(@{ productoId = [int]$prodId; cantidad = 9999 }) }).status 409
Check 'GET /ordenes' (Api GET '/api/v1/ordenes').status 200
Check 'GET /ordenes/{id}' (Api GET "/api/v1/ordenes/$ordenId").status 200
Check 'GET /ordenes/{id}/detalles' (Api GET "/api/v1/ordenes/$ordenId/detalles").status 200
# La clave de la línea es (variante, orden): el id de la variante lo pide el
# servidor, no se deduce del producto.
$varianteProd = [int](((Api GET "/api/v1/ordenes/$ordenId/detalles").body | ConvertFrom-Json).items[0].varianteId)
Check 'DELETE /detalle en orden no pagada (204)' (Api DELETE "/api/v1/ordenes/$ordenId/detalles/$varianteProd").status 204
Check 'DELETE /detalle que no está en la orden (404)' (Api DELETE "/api/v1/ordenes/$ordenId/detalles/999999").status 404

# se borró la línea: se vuelve a crear con 3 unidades
$r = Api POST "/api/v1/ordenes/$ordenId/detalles" @{ productoId = [int]$prodId; cantidad = 3 }
Check 'POST /ordenes/{id}/detalles' $r.status 201

$stockAntes = ((Api GET "/api/v1/products/$prodId").body | ConvertFrom-Json).stock
Check 'PUT /ordenes/{id}/estado -> PAGADO' (Api PUT "/api/v1/ordenes/$ordenId/estado" @{ estado = 'PAGADO' }).status 200
$stockDespues = ((Api GET "/api/v1/products/$prodId").body | ConvertFrom-Json).stock
if ($stockAntes - $stockDespues -eq 3) {
  $script:ok++; "  OK   el cobro descuenta stock ($stockAntes -> $stockDespues)"
} else {
  $script:fail++; "  FAIL stock tras cobro: $stockAntes -> $stockDespues (esperado -3)"
}
Check 'PUT /detalle sobre orden PAGADA (409)' (Api POST "/api/v1/ordenes/$ordenId/detalles" @{ productoId = [int]$prodId; cantidad = 1 }).status 409
Check 'PUT /ordenes/{id}/estado inválido (400)' (Api PUT "/api/v1/ordenes/$ordenId/estado" @{ estado = 'INVENTADO' }).status 400

# La factura no pide importes: copia subtotal, rebaja e IVA ya cobrados de la
# orden (antes eran «boletas», renombradas en la migración 010_facturas).
$r = Api POST '/api/v1/facturas' @{ ordenId = [int]$ordenId }
Check 'POST /facturas' $r.status 201
$facturaId = Id-De $r.body
Check 'POST /facturas sin ordenId (400)' (Api POST '/api/v1/facturas' @{}).status 400
Check 'POST /facturas duplicada (409)' (Api POST '/api/v1/facturas' @{ ordenId = [int]$ordenId }).status 409
Check 'GET /facturas' (Api GET '/api/v1/facturas').status 200
Check 'GET /facturas/{id}' (Api GET "/api/v1/facturas/$facturaId").status 200
Check 'DELETE /ordenes PAGADA (409)' (Api DELETE "/api/v1/ordenes/$ordenId").status 409
Check 'DELETE /facturas EMITIDA (409)' (Api DELETE "/api/v1/facturas/$facturaId").status 409
Check 'PUT /facturas/{id}/estado -> ANULADA' (Api PUT "/api/v1/facturas/$facturaId/estado" @{ estado = 'ANULADA' }).status 200
Check 'DELETE /facturas ANULADA (204)' (Api DELETE "/api/v1/facturas/$facturaId").status 204
Check 'PUT /ordenes/{id}/estado -> CANCELADO (repona stock)' (Api PUT "/api/v1/ordenes/$ordenId/estado" @{ estado = 'CANCELADO' }).status 200
$stockFinal = ((Api GET "/api/v1/products/$prodId").body | ConvertFrom-Json).stock
if ($stockFinal -eq $stockAntes) {
  $script:ok++; "  OK   al cancelar se repone el stock ($stockDespues -> $stockFinal)"
} else {
  $script:fail++; "  FAIL stock tras cancelar: $stockFinal (esperado $stockAntes)"
}
Check 'DELETE /ordenes/{id} (204)' (Api DELETE "/api/v1/ordenes/$ordenId").status 204

# --- Cotizaciones ------------------------------------------------------------
Write-Host "`n=== Cotizaciones ===" -ForegroundColor Cyan
$stockAntesCot = ((Api GET "/api/v1/products/$prodId").body | ConvertFrom-Json).stock
$r = Api POST '/api/v1/cotizaciones' @{
  nombreCliente = 'Cliente mostrador'
  empleadoId = 999 # el body NO decide el creador: manda la sesión
  items = @(@{ productoId = [int]$prodId; cantidad = 2 })
}
Check 'POST /cotizaciones' $r.status 201
$cot = $r.body | ConvertFrom-Json
$cotId = $cot.id
if ([math]::Abs($cot.total - 4.90) -lt 0.001) {
  $script:ok++; "  OK   total de la cotización = $($cot.total) (2 x 2.45, precio de BD)"
} else {
  $script:fail++; "  FAIL total de la cotización = $($cot.total) (esperado 4.90)"
}
$me = Api GET '/api/v1/auth/me'
$empleadoSesion = ($me.body | ConvertFrom-Json).usuario.empleadoId
if ($null -ne $empleadoSesion -and $cot.empleadoId -eq $empleadoSesion) {
  $script:ok++; "  OK   el creador es el empleado de la sesión ($($cot.empleadoId)), no el del body"
} elseif ($null -eq $empleadoSesion -and $null -eq $cot.empleadoId) {
  $script:ok++; '  OK   la sesión no tiene empleado y la cotización tampoco: el empleadoId 999 del body se ignoró'
} else {
  $script:fail++; "  FAIL creador = $($cot.empleadoId) (esperado el de la sesión: $empleadoSesion)"
}
Check 'POST /cotizaciones sin items (400)' (Api POST '/api/v1/cotizaciones' @{ items = @() }).status 400
Check 'POST /cotizaciones con item duplicado (400)' (Api POST '/api/v1/cotizaciones' @{ items = @(@{ productoId = [int]$prodId; cantidad = 1 }; @{ productoId = [int]$prodId; cantidad = 1 }) }).status 400
Check 'POST /cotizaciones producto inexistente (404)' (Api POST '/api/v1/cotizaciones' @{ items = @(@{ productoId = 999999; cantidad = 1 }) }).status 404

# Cotizar más de lo que hay está permitido: no reserva stock (201 y el
# stock del producto no se mueve).
$rGrande = Api POST '/api/v1/cotizaciones' @{
  nombreCliente = 'Cliente mostrador'
  items = @(@{ productoId = [int]$prodId; cantidad = 999 })
}
Check 'POST /cotizaciones con más stock del que existe (201: no reserva)' $rGrande.status 201
$cotGrandeId = Id-De $rGrande.body
$stockDespuesCot = ((Api GET "/api/v1/products/$prodId").body | ConvertFrom-Json).stock
if ($stockDespuesCot -eq $stockAntesCot) {
  $script:ok++; "  OK   las cotizaciones no tocan el stock ($stockAntesCot -> $stockDespuesCot)"
} else {
  $script:fail++; "  FAIL stock tras cotizar: $stockAntesCot -> $stockDespuesCot (esperado sin cambios)"
}

Check 'GET /cotizaciones' (Api GET '/api/v1/cotizaciones').status 200
Check 'GET /cotizaciones?estado=ACEPTADA' (Api GET '/api/v1/cotizaciones?estado=ACEPTADA').status 200
$cotDetalle = Api GET "/api/v1/cotizaciones/$cotId"
Check 'GET /cotizaciones/{id}' $cotDetalle.status 200
$cotFull = $cotDetalle.body | ConvertFrom-Json
if ($cotFull.detalles.Count -eq 1 -and [math]::Abs($cotFull.detalles[0].precioVenta - 2.45) -lt 0.001) {
  $script:ok++; "  OK   el detalle trae la línea con su precio congelado"
} else {
  $script:fail++; "  FAIL detalle de la cotización: $($cotDetalle.body)"
}
Check 'PUT /cotizaciones/{id}/estado -> ACEPTADA' (Api PUT "/api/v1/cotizaciones/$cotId/estado" @{ estado = 'ACEPTADA' }).status 200
Check 'PUT /cotizaciones/{id}/estado inválido (400)' (Api PUT "/api/v1/cotizaciones/$cotId/estado" @{ estado = 'INVENTADO' }).status 400
Check 'DELETE /cotizaciones/{id} (204)' (Api DELETE "/api/v1/cotizaciones/$cotId").status 204
$cotOculta = Api GET "/api/v1/cotizaciones/$cotId"
Check 'GET /cotizaciones/{id} oculta sigue en la BD (200)' $cotOculta.status 200
if ($cotOculta.body -match '"estado":"ELIMINADO"') {
  $script:ok++; "  OK   GET /cotizaciones/{id} -> estado ELIMINADO"
} else {
  $script:fail++; "  FAIL GET /cotizaciones/{id} estado ELIMINADO -> $($cotOculta.body)"
}
$listaCot = Api GET '/api/v1/cotizaciones'
if ($listaCot.body -match "`"id`":$cotId,") {
  $script:fail++; "  FAIL el listado no debe mostrar la cotización oculta ($cotId)"
} else {
  $script:ok++; "  OK   listado oculta la cotización ($cotId)"
}
Check 'DELETE /cotizaciones grande (204)' (Api DELETE "/api/v1/cotizaciones/$cotGrandeId").status 204

# --- Reportes del dashboard -------------------------------------------------
Write-Host "`n=== Reportes agregados ===" -ForegroundColor Cyan
Check 'GET /reportes/productos-vendidos' (Api GET '/api/v1/reportes/productos-vendidos?limite=6&orden=desc').status 200
Check 'GET /reportes/productos-vendidos (asc)' (Api GET '/api/v1/reportes/productos-vendidos?limite=6&orden=asc').status 200
Check 'GET /reportes/productos-vendidos orden inválido (400)' (Api GET '/api/v1/reportes/productos-vendidos?orden=loquesea').status 400
Check 'GET /reportes/productos-vendidos límite inválido (400)' (Api GET '/api/v1/reportes/productos-vendidos?limite=999').status 400

# --- Ajustes globales (solo ADMIN escribe) ---------------------------------
Write-Host "`n=== Ajustes globales ===" -ForegroundColor Cyan
Check 'GET /ajustes' (Api GET '/api/v1/ajustes').status 200
$listaAjustes = Api GET '/api/v1/ajustes'
if ($listaAjustes.body -match '"total":') {
  $script:ok++; '  OK   GET /ajustes -> listado {total, items}'
} else {
  $script:fail++; "  FAIL GET /ajustes no devuelve {total, items} ($($listaAjustes.body))"
}

# El nivel de la cuenta decide qué se puede comprobar: cualquiera lee los
# ajustes, pero solo quien tiene el permiso `ajustes.editar` los guarda (y si
# no lo es, eso es un 403 `permiso_denegado`).
$nivel = ''
if ($script:token) {
  $me = Api GET '/api/v1/auth/me'
  if ($me.status -eq 200) { $nivel = ($me.body | ConvertFrom-Json).usuario.nivelUsuario }
}
if ($nivel -eq 'ADMIN') {
  # `porPagina = 10` es el valor de fábrica: guardarlo deja la BD como estaba.
  Check 'PUT /ajustes (permiso ajustes.editar)' (Api PUT '/api/v1/ajustes' @{ valores = @{ porPagina = '10' } }).status 200
  Check 'PUT /ajustes con clave desconocida (400)' (Api PUT '/api/v1/ajustes' @{ valores = @{ claveRara = 'x' } }).status 400
  Check 'PUT /ajustes con número fuera de rango (400)' (Api PUT '/api/v1/ajustes' @{ valores = @{ porPagina = '999' } }).status 400
  Check 'PUT /ajustes con valor vacío donde no cabe (400)' (Api PUT '/api/v1/ajustes' @{ valores = @{ tipoPagoPorDefecto = '' } }).status 400
  Check 'PUT /ajustes sin "valores" (400)' (Api PUT '/api/v1/ajustes' @{}).status 400
} else {
  Check 'PUT /ajustes sin permiso ajustes.editar (403)' (Api PUT '/api/v1/ajustes' @{ valores = @{ porPagina = '10' } }).status 403
}

# --- Respaldos de la BD (pg_dump) --------------------------------------------
# Solo ADMIN: el listado exige `ajustes.ver` y la creación `ajustes.editar`.
# `POST` ejecuta `pg_dump -Fc` de verdad y deja el .dump en BACKUPS_DIR
# (se conservan los 30 más recientes; no se borra para no tocar la carpeta).
Write-Host "`n=== Respaldos de la BD ===" -ForegroundColor Cyan
if ($nivel -eq 'ADMIN') {
  Check 'GET /respaldos' (Api GET '/api/v1/respaldos').status 200
  $listaRespaldos = Api GET '/api/v1/respaldos'
  if ($listaRespaldos.body -match '"total":') {
    $script:ok++; '  OK   GET /respaldos -> listado {total, items}'
  } else {
    $script:fail++; "  FAIL GET /respaldos no devuelve {total, items} ($($listaRespaldos.body))"
  }

  $r = Api POST '/api/v1/respaldos'
  Check 'POST /respaldos (pg_dump)' $r.status 201
  if ($r.status -eq 201) {
    $nombreRespaldo = ($r.body | ConvertFrom-Json).nombre
    if ($nombreRespaldo -match '^respaldo_\d{4}-\d{2}-\d{2}_\d{6}(_\d+)?\.dump$') {
      $script:ok++; "  OK   POST /respaldos -> $nombreRespaldo"
    } else {
      $script:fail++; "  FAIL POST /respaldos devuelve un nombre raro ($($r.body))"
    }
    # El listado debe incluirlo y la descarga debe devolver bytes.
    $trasCreate = (Api GET '/api/v1/respaldos').body
    if ($trasCreate -match [regex]::Escape($nombreRespaldo)) {
      $script:ok++; '  OK   GET /respaldos incluye el recién creado'
    } else {
      $script:fail++; '  FAIL GET /respaldos no incluye el recién creado'
    }
    Check 'GET /respaldos/{nombre}/descarga' (Api GET "/api/v1/respaldos/$nombreRespaldo/descarga").status 200
    Check 'GET /respaldos inexistente (404)' (Api GET '/api/v1/respaldos/respaldo_1999-01-01_000000.dump/descarga').status 404
    Check 'GET /respaldos con nombre fuera de patrón (404)' (Api GET '/api/v1/respaldos/no-es-un-respaldo/descarga').status 404
  }
} else {
  Check 'POST /respaldos sin permiso ajustes.editar (403)' (Api POST '/api/v1/respaldos').status 403
}

# --- Concurrencia ------------------------------------------------------------
# Peticiones simultáneas sobre los mismos registros: comprueba que las
# transacciones con `FOR UPDATE` (cobros, guardia de versión) serializan lo
# que hay que serializar y que jamás sale un 5xx ni un stock negativo.
# Cada petición corre en su propio `Start-Job` (proceso PowerShell aparte =>
# concurrencia real; funciona en Windows PowerShell 5.1 y en pwsh).
Write-Host "`n=== Concurrencia (peticiones simultáneas) ===" -ForegroundColor Cyan

function EjecutarEnParalelo([array]$Peticiones) {
  $trabajos = @()
  foreach ($p in $Peticiones) {
    $trabajos += Start-Job -ScriptBlock {
      param($base, $token, $metodo, $ruta, $cuerpo)
      $params = @{ Uri = "$base$ruta"; Method = $metodo; UseBasicParsing = $true; TimeoutSec = 20 }
      if ($token) { $params.Headers = @{ Authorization = "Bearer $token" } }
      if ($null -ne $cuerpo) {
        $params.Body = ($cuerpo | ConvertTo-Json -Depth 8)
        $params.ContentType = 'application/json'
      }
      try {
        $resp = Invoke-WebRequest @params
        return [int]$resp.StatusCode
      } catch {
        $respuesta = $_.Exception.Response
        if ($respuesta) { return [int]$respuesta.StatusCode }
        return 0
      }
    } -ArgumentList $Base, $script:token, $p.metodo, $p.ruta, $p.cuerpo
  }
  $estados = @()
  foreach ($t in $trabajos) {
    Wait-Job $t | Out-Null
    $salida = Receive-Job $t -ErrorAction SilentlyContinue
    $estados += $(if ($salida -is [int]) { $salida } else { 0 })
    Remove-Job $t -Force
  }
  return $estados
}

# --- A: seis cobros simultáneos de la MISMA orden -----------------------------
$r = Api POST '/api/v1/products' @{
  nombre = "Concurrencia cobro [smoke]"
  precioVenta = 5.0
  stock = 10
  estado = 'DISPONIBLE'
}
$prodConc = Id-De $r.body
$r = Api POST '/api/v1/ordenes' @{
  pagos = @(@{ metodoPago = 'EFECTIVO'; monto = 10.0 })
  items = @(@{ productoId = [int]$prodConc; cantidad = 2 })
}
Check 'Concurrencia: POST /ordenes de prueba' $r.status 201
$ordenConc = Id-De $r.body

$cobrosParalelos = @()
for ($i = 0; $i -lt 6; $i++) {
  $cobrosParalelos += @{
    metodo = 'PUT'
    ruta = "/api/v1/ordenes/$ordenConc/estado"
    cuerpo = @{ estado = 'PAGADO' }
  }
}
$estadosCobro = @(EjecutarEnParalelo $cobrosParalelos)
$sin5xx = @($estadosCobro | Where-Object { $_ -lt 200 -or $_ -ge 500 })
if ($estadosCobro.Count -eq 6 -and $sin5xx.Count -eq 0) {
  $script:ok++; "  OK   6 cobros simultáneos sin 5xx -> $($estadosCobro -join ', ')"
} else {
  $script:fail++; "  FAIL cobros simultáneos -> $($estadosCobro -join ', ') (0 = sin respuesta)"
}
$stockTrasCobro = ((Api GET "/api/v1/products/$prodConc").body | ConvertFrom-Json).stock
if ($stockTrasCobro -eq 8) {
  $script:ok++; "  OK   stock descontado UNA sola vez con 6 cobros (10 -> $stockTrasCobro)"
} else {
  $script:fail++; "  FAIL stock tras 6 cobros simultáneos: $stockTrasCobro (esperado 8)"
}

# --- B: dos órdenes rivales por las últimas unidades --------------------------
$r = Api POST '/api/v1/products' @{
  nombre = "Rivas por stock [smoke]"
  precioVenta = 5.0
  stock = 5
  estado = 'DISPONIBLE'
}
$prodRival = Id-De $r.body
# Ambas creaciones ven stock = 5 (la reserva es al cobrar), así que las dos
# órdenes existen y solo una podrá descontar 4 unidades.
$ordenRival1 = Id-De (Api POST '/api/v1/ordenes' @{
  pagos = @(@{ metodoPago = 'EFECTIVO'; monto = 20.0 })
  items = @(@{ productoId = [int]$prodRival; cantidad = 4 })
}).body
$ordenRival2 = Id-De (Api POST '/api/v1/ordenes' @{
  pagos = @(@{ metodoPago = 'EFECTIVO'; monto = 20.0 })
  items = @(@{ productoId = [int]$prodRival; cantidad = 4 })
}).body

$estadosRival = @(EjecutarEnParalelo @(
  @{ metodo = 'PUT'; ruta = "/api/v1/ordenes/$ordenRival1/estado"; cuerpo = @{ estado = 'PAGADO' } },
  @{ metodo = 'PUT'; ruta = "/api/v1/ordenes/$ordenRival2/estado"; cuerpo = @{ estado = 'PAGADO' } }
))
$pagadas = @($estadosRival | Where-Object { $_ -eq 200 })
$rechazadas = @($estadosRival | Where-Object { $_ -eq 409 })
if ($pagadas.Count -eq 1 -and $rechazadas.Count -eq 1) {
  $script:ok++; "  OK   rivales por el stock: una paga (200) y otra recibe 409 -> $($estadosRival -join ', ')"
} else {
  $script:fail++; "  FAIL rivales por el stock -> $($estadosRival -join ', ') (esperado 200 y 409)"
}
$stockRival = ((Api GET "/api/v1/products/$prodRival").body | ConvertFrom-Json).stock
if ($stockRival -eq 1) {
  $script:ok++; "  OK   stock de los rivales nunca negativo (5 -> $stockRival)"
} else {
  $script:fail++; "  FAIL stock de los rivales: $stockRival (esperado 1)"
}
# La orden ganadora se cancela antes de ocultarla (repone sus 4 unidades).
$ganadora = if ($estadosRival[0] -eq 200) { $ordenRival1 } else { $ordenRival2 }
$perdedora = if ($estadosRival[0] -eq 200) { $ordenRival2 } else { $ordenRival1 }
Api PUT "/api/v1/ordenes/$ganadora/estado" @{ estado = 'CANCELADO' } | Out-Null
Api DELETE "/api/v1/ordenes/$ganadora" | Out-Null
Api DELETE "/api/v1/ordenes/$perdedora" | Out-Null

# --- C: dos ediciones del mismo producto con la misma versionLeida -----------
$r = Api GET "/api/v1/products/$prodConc"
$versionLeida = [int](($r.body | ConvertFrom-Json).version)
$estadosVersion = @(EjecutarEnParalelo @(
  @{ metodo = 'PUT'; ruta = "/api/v1/products/$prodConc"; cuerpo = @{ precioVenta = 5.1; versionLeida = $versionLeida } },
  @{ metodo = 'PUT'; ruta = "/api/v1/products/$prodConc"; cuerpo = @{ precioVenta = 5.2; versionLeida = $versionLeida } }
))
$ganadas = @($estadosVersion | Where-Object { $_ -eq 200 }).Count
$perdidas = @($estadosVersion | Where-Object { $_ -eq 409 }).Count
if ($ganadas -eq 1 -and $perdidas -eq 1) {
  $script:ok++; "  OK   guardia de versión: una edición gana (200) y la otra recibe 409 -> $($estadosVersion -join ', ')"
} else {
  $script:fail++; "  FAIL guardia de versión -> $($estadosVersion -join ', ') (esperado 200 y 409)"
}

# Limpieza de la sección: se cancela lo cobrado (repone stock) y se oculta
# todo lo creado aquí; los DELETE son borrado lógico, como en el resto.
Api PUT "/api/v1/ordenes/$ordenConc/estado" @{ estado = 'CANCELADO' } | Out-Null
Api DELETE "/api/v1/ordenes/$ordenConc" | Out-Null
Check 'Concurrencia: DELETE /products cobro (204)' (Api DELETE "/api/v1/products/$prodConc").status 204
Check 'Concurrencia: DELETE /products rival (204)' (Api DELETE "/api/v1/products/$prodRival").status 204

# --- Auditoría --------------------------------------------------------------
Write-Host "`n=== Auditoría ===" -ForegroundColor Cyan
$aud = Api GET '/api/v1/auditoria?limit=20'
Check 'GET /auditoria' $aud.status 200
Check '  hay eventos registrados' ([int](($aud.body | ConvertFrom-Json).total -gt 0)) 1
# Una corrida deja cientos de eventos: los hitos antiguos hay que buscarlos con
# los filtros de la propia API, no en las últimas 20 filas.
$audLogin = Api GET '/api/v1/auditoria?accion=LOGIN&limit=200'
Check '  registra el LOGIN del principio' ([int](($audLogin.status -eq 200 -and ($audLogin.body | ConvertFrom-Json).total -gt 0))) 1
$audRoles = Api GET '/api/v1/auditoria?entidad=roles&limit=200'
Check '  registra operaciones sobre roles' ([int](($audRoles.status -eq 200 -and ($audRoles.body | ConvertFrom-Json).total -gt 0))) 1
$audClave = Api GET '/api/v1/auditoria?accion=RESTABLECER_CONTRASENA&limit=200'
Check '  registra el RESTABLECER_CONTRASENA del usuario' ([int](($audClave.status -eq 200 -and ($audClave.body | ConvertFrom-Json).total -gt 0))) 1
# Purga por antigüedad inofensiva (nada es anterior a 2000): no toca el histórico.
$purga = Api DELETE '/api/v1/auditoria/antes-de/2000-01-01'
Check 'DELETE /auditoria/antes-de/2000-01-01' $purga.status 200
Check '  no había eventos tan antiguos' ([int](($purga.body | ConvertFrom-Json).eliminados -eq 0)) 1
Check 'DELETE /auditoria/antes-de con fecha inválida (400)' (Api DELETE '/api/v1/auditoria/antes-de/nofecha').status 400

# --- Errores generales -----------------------------------------------------
Write-Host "`n=== Errores y documentación ===" -ForegroundColor Cyan
Check 'GET /ruta-inexistente (404)' (Api GET '/api/v1/nada').status 404
Check 'GET /api/v1/ordenes/abc (400)' (Api GET '/api/v1/ordenes/abc').status 400
Check 'GET / (índice)' (Api GET '/').status 200
Check 'GET /openapi.json' (Api GET '/openapi.json').status 200
Check 'GET /docs' (Api GET '/docs').status 200

# --- Limpieza: solo lo que este script creó -------------------------------
Write-Host "`n=== Limpieza de los datos [smoke] ===" -ForegroundColor Cyan
Check 'DELETE /products/{id}' (Api DELETE "/api/v1/products/$prodId").status 204
Check 'DELETE /usuarios/{id}' (Api DELETE "/api/v1/usuarios/$usuId").status 204
Check 'DELETE /empleados/{id}' (Api DELETE "/api/v1/empleados/$empId").status 204
# (el cliente ya se borró en la sección de Personas)
if ($script:token) {
  Check 'POST /auth/logout (final)' (Api POST '/api/v1/auth/logout').status 200
}

# --- Resumen ---------------------------------------------------------------
Write-Host "`n================ RESULTADO ================" -ForegroundColor Cyan
Write-Host "Correctos: $script:ok   Fallos: $script:fail" -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
if ($script:fail -gt 0) { exit 1 }
