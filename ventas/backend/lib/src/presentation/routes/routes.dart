import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../data/services/clasificador_ia.dart';
import '../../data/services/descargador_modelo.dart';
import '../../data/services/narrador.dart';
import '../../data/services/ollama_service.dart';
import '../../data/services/resolvedor_intencion.dart';
import '../../data/storage/almacenamiento_imagenes.dart';
import '../../domain/usecases/ajuste_usecases.dart';
import '../../domain/usecases/auditoria_usecases.dart';
import '../../domain/usecases/categoria_usecases.dart';
import '../../domain/usecases/color_usecases.dart';
import '../../domain/usecases/auth_usecases.dart';
import '../../domain/usecases/cotizacion_usecases.dart';
import '../../domain/usecases/get_health_status.dart';
import '../../domain/usecases/marca_usecases.dart';
import '../../domain/usecases/persona_usecases.dart';
import '../../domain/usecases/producto_usecases.dart';
import '../../domain/usecases/reporte_usecases.dart';
import '../../domain/usecases/respaldo_usecases.dart';
import '../../domain/usecases/rol_usecases.dart';
import '../../domain/usecases/usuario_usecases.dart';
import '../../domain/usecases/unidad_medida_usecases.dart';
import '../../domain/usecases/venta_usecases.dart';
import '../docs/swagger_docs.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';
import '../http/rate_limit.dart';
import 'ajuste_routes.dart';
import 'archivo_routes.dart';
import 'auditoria_routes.dart';
import 'auth_routes.dart';
import 'categoria_routes.dart';
import 'chat_routes.dart';
import 'color_routes.dart';
import 'cotizacion_routes.dart';
import 'marca_routes.dart';
import 'persona_routes.dart';
import 'producto_routes.dart';
import 'reporte_routes.dart';
import 'respaldo_routes.dart';
import 'rol_routes.dart';
import 'usuario_routes.dart';
import 'unidad_medida_routes.dart';
import 'venta_routes.dart';

/// Reglas de enrutado (capa `presentation`).
///
/// Este archivo es el **compositor**: junta los registradores de cada módulo,
/// añade el índice, la documentación y el 404. Las rutas concretas viven en
/// `*_routes.dart`, y cada una solo orquesta: recibe la request, delega en un
/// caso de uso y devuelve la respuesta. Ninguna contiene SQL ni reglas de
/// negocio.
Handler buildRoutes({
  required GetHealthStatus getHealthStatus,
  required Autenticar autenticar,
  required Productos productos,
  required Categorias categorias,
  required Presentaciones presentaciones,
  required Colores colores,
  required Marcas marcas,
  required Unidades unidades,
  required Clientes clientes,
  required Proveedores proveedores,
  required Empleados empleados,
  required Usuarios usuarios,
  required Roles roles,
  required Ordenes ordenes,
  required Facturas facturas,
  required Cotizaciones cotizaciones,
  required Reportes reportes,
  required Ajustes ajustes,
  required Auditorias auditorias,
  required AlmacenamientoImagenes almacenImagenes,
  required Respaldos respaldos,
  required ModeloConversacion ollama,
  required ResolvedorIntencion resolvedorChat,
  required ClasificadorIA clasificadorChat,
  required Narrador narradorChat,
  required DescargadorModelo descargadorModelo,
  Future<void> Function()? alCrearRespaldo,
  Future<void> Function()? alGuardarAjustes,
  SwaggerDocs? docs,
  RateLimiter? rateLimiter,
}) {
  final router = Router()
    // GET /api/v1/health -> estado del servicio y de la BD
    ..get('/api/v1/health', (Request request) async {
      final status = await getHealthStatus();
      return jsonResponse(200, {
        'status': status.databaseConnected ? 'ok' : 'degraded',
        ...status.toJson(),
      });
    })
    // GET /api/v1/network -> IPs locales de esta máquina (QR de acceso móvil)
    //
    // El frontend web la usa para armar la URL que debe escanear el celular
    // cuando la página se abrió en `localhost`: `localhost` desde el teléfono
    // apuntaría al propio teléfono, hace falta la IP real de la PC en la LAN.
    //
    // En Windows se le pregunta a PowerShell por las interfaces **activas**
    // (la de la ruta por defecto primero): `NetworkInterface.list` devuelve
    // también la IP que el sistema conserva en adaptadores desconectados
    // (p. ej. el Ethernet sin cable con su dirección vieja), que no sirve
    // desde el celular y salía como primera opción. Sin PowerShell (Android,
    // Linux) o si el comando falla, se usa la lista del sistema tal cual.
    ..get('/api/v1/network', (Request request) async {
      final activas = await _interfacesActivas();
      if (activas != null) {
        final porInterfaz = <Map<String, Object>>[];
        final orden = <String>[];
        final ipsPorNombre = <String, List<String>>{};
        final todas = <String>[];
        for (final entrada in activas) {
          final (nombre, ip) = entrada;
          todas.add(ip);
          final lista = ipsPorNombre[nombre];
          if (lista != null) {
            lista.add(ip);
          } else {
            ipsPorNombre[nombre] = [ip];
            orden.add(nombre);
          }
        }
        for (final nombre in orden) {
          porInterfaz.add({'name': nombre, 'ipv4': ipsPorNombre[nombre]!});
        }
        return jsonResponse(200, {'ipv4': todas, 'interfaces': porInterfaz});
      }

      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );

      final porInterfazFallback = <Map<String, Object>>[];
      final todasFallback = <String>[];
      for (final interfaz in interfaces) {
        final ipv4 = [
          for (final addr in interfaz.addresses)
            if (addr.type == InternetAddressType.IPv4) addr.address,
        ];
        if (ipv4.isEmpty) continue;
        porInterfazFallback.add({'name': interfaz.name, 'ipv4': ipv4});
        todasFallback.addAll(ipv4);
      }

      return jsonResponse(200, {
        'ipv4': _ordenarRedesPrivadas(todasFallback),
        'interfaces': porInterfazFallback,
      });
    })
    // POST /api/v1/network/hotspot -> enciende el punto de acceso de la PC
    //
    // Para que el celular pueda entrar por QR cuando **no hay internet**: la PC
    // comparte su propia red y el QR apunta a [ipPuntoAcceso].
    //
    // Se intenta primero encenderlo desde aquí (el hotspot moderno de Windows
    // reutiliza la configuración que el usuario ya tenga guardada, así que la
    // app no fija SSID ni clave). Si Windows no lo permite —permisos o driver—
    // se abre la página de Ajustes correspondiente: encender el interruptor es
    // un clic y ahí queda garantizado el camino.
    ..post('/api/v1/network/hotspot', (Request request) async {
      asegurarPermiso(request, 'ajustes', 'editar');

      // `abrirAjustes` = no se pudo encender desde aquí, así que se abre la
      // página de Windows para que lo haga el usuario con el interruptor.
      var abrirAjustes = false;
      if (Platform.isWindows && !await _encenderPuntoAcceso()) {
        abrirAjustes = true;
        _abrirAjustesPuntoAcceso();
      }

      final ip = await _ipPuntoAcceso();
      return jsonResponse(200, {
        'estado': ip == null ? 'apagado' : 'activo',
        'ip': ?ip,
        if (abrirAjustes) 'accion': 'abrir_ajustes',
      });
    })
    // GET / -> índice con enlaces útiles
    ..get('/', (Request request) {
      return jsonResponse(200, {
        'name': 'ventas-api',
        'version': '0.1.0',
        'docs': '/docs',
        'openapi': '/openapi.json',
        'endpoints': _endpoints,
      });
    });

  // Módulos de la API
  addAuthRoutes(router, autenticar: autenticar, rateLimiter: rateLimiter);
  addProductoRoutes(router, productos: productos);
  addCategoriaRoutes(
    router,
    categorias: categorias,
    presentaciones: presentaciones,
  );

  // Colores: la variante nueva de la página Categorías (pestaña «Colores»);
  // reutiliza los permisos del módulo `categorias`.
  addColorRoutes(router, colores: colores);

  // Marcas: pestaña «Marcas» de la misma página; también permisos `categorias`.
  addMarcaRoutes(router, marcas: marcas);

  // Unidades de medida: el catálogo que decide qué se vende y con cuántos
  // decimales (alimenta el desplegable «Unidad de venta» del producto).
  addUnidadMedidaRoutes(router, unidades: unidades);
  addPersonaRoutes(
    router,
    clientes: clientes,
    proveedores: proveedores,
    empleados: empleados,
  );
  addUsuarioRoutes(router, usuarios: usuarios);

  // Roles y permisos (RBAC): quién puede ver/crear/editar/eliminar.
  addRolRoutes(router, roles: roles);
  addVentaRoutes(router, ordenes: ordenes, facturas: facturas);

  // Cotizaciones: propuestas de precio (el creador sale de la sesión).
  addCotizacionRoutes(router, cotizaciones: cotizaciones);

  // Ajustes globales del sistema (lectura abierta, escritura solo ADMIN).
  // Al guardarlos se recalcula el próximo respaldo automático.
  addAjusteRoutes(router, ajustes: ajustes, alGuardar: alGuardarAjustes);

  // Respaldos de la BD con pg_dump: crear, listar y descargar.
  addRespaldoRoutes(router, respaldos: respaldos, alCrear: alCrearRespaldo);

  // Auditoría de cambios: consulta (auditoria.ver) y purga (auditoria.eliminar).
  addAuditoriaRoutes(router, auditorias: auditorias);

  // Reportes agregados (permiso propio `reportes.ver`): rankings del
  // dashboard e informe de ventas por rango de la pantalla «Reportes».
  addReporteRoutes(router, reportes: reportes);

  // Imágenes: subida (base64) y descarga de ficheros locales.
  addArchivoRoutes(router, almacen: almacenImagenes);

  // Asistente IA local (Ollama): estado, chat y descarga del modelo.
  // Sin rutas públicas ⇒ el middleware exige sesión para las cuatro, y
  // `ajustes` filtra además qué roles pueden preguntar (ajuste `iaRoles`).
  addChatRoutes(
    router,
    ollama: ollama,
    resolvedor: resolvedorChat,
    clasificador: clasificadorChat,
    narrador: narradorChat,
    descargador: descargadorModelo,
    ajustes: ajustes,
  );

  // Documentación (Swagger UI + especificación), si está habilitada.
  // Debe montarse antes del 404 para que `/docs` no caiga en el catch-all.
  final docsUi = docs?.ui;
  if (docsUi != null) {
    router.mount('/docs', docsUi);
  }
  final docsSpec = docs?.spec;
  if (docsSpec != null) {
    router.get('/openapi.json', docsSpec);
  }

  // Cualquier otra ruta -> 404 en JSON
  router.all('/<path|.*>', (Request request) {
    return errorResponse(
      404,
      'Ruta no encontrada: ${request.method} ${request.requestedUri.path}',
      code: 'not_found',
    );
  });

  return router.call;
}

/// Consulta a Windows las interfaces IPv4 **activas**, con la de la ruta
/// por defecto primero. Devuelve `null` cuando no se pudo (fuera de Windows,
/// PowerShell ausente, error o timeout) y el llamador usa
/// `NetworkInterface.list` como respaldo.
Future<List<(String, String)>?> _interfacesActivas() async {
  if (!Platform.isWindows) return null;
  try {
    final proceso = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      _scriptInterfacesActivas,
    ], stdoutEncoding: utf8).timeout(const Duration(seconds: 5));
    if (proceso.exitCode != 0) return null;
    return interfacesDesdePowerShell(proceso.stdout as String);
  } catch (_) {
    return null;
  }
}

/// IP que Windows asigna al **punto de acceso** (hotspot) de la PC.
///
/// Es la subred por defecto de ICS y es la misma en cualquier equipo y
/// cualquier red: no es la IP de esta máquina, es una constante del sistema
/// operativo. Por eso sirve para reconocer el hotspot en `GET /network` y para
/// que el QR sepa qué candidata priorizar cuando el celular se conecta a él.
///
/// El frontend declara el mismo valor (`qr_acceso.dart`): la API no expone una
/// bandera por interfaz, así que ambos lados comparan contra esta constante.
const String ipPuntoAcceso = '192.168.137.1';

/// Enciende el punto de acceso de la PC y devuelve `true` si quedó activo.
///
/// Solo Windows. Usa la configuración que el usuario ya tenga guardada en
/// Ajustes (SSID y clave), así que la app no fija ningún valor: si no está
/// configurado o el sistema no lo permite, devuelve `false` y la ruta abre la
/// página de Ajustes correspondiente.
Future<bool> _encenderPuntoAcceso() async {
  if (!Platform.isWindows) return false;
  try {
    final proceso = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      _scriptEncenderPuntoAcceso,
    ], stdoutEncoding: utf8).timeout(const Duration(seconds: 8));
    return proceso.exitCode == 0 &&
        (proceso.stdout as String).trimRight().endsWith('OK');
  } catch (_) {
    return false;
  }
}

/// `ipPuntoAcceso` si el hotspot está activo (la interfaz tiene esa IP);
/// `null` si está apagado o no se pudo consultar.
Future<String?> _ipPuntoAcceso() async {
  final activas = await _interfacesActivas();
  if (activas != null) {
    for (final (_, ip) in activas) {
      if (ip == ipPuntoAcceso) return ip;
    }
    return null;
  }

  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final interfaz in interfaces) {
      for (final direccion in interfaz.addresses) {
        if (direccion.type == InternetAddressType.IPv4 &&
            direccion.address == ipPuntoAcceso) {
          return ipPuntoAcceso;
        }
      }
    }
  } catch (_) {
    // Sin interfaces no hay forma de saberlo: se reporta como apagado.
  }
  return null;
}

/// Abre la página de Ajustes del punto de acceso para que el usuario lo
/// encienda con el interruptor.
///
/// Es el camino garantizado: la activación directa depende de permisos y del
/// driver. Se dispara sin esperar (no se bloquea la respuesta) y su fallo no
/// es un error: el usuario siempre puede llegar ahí a mano.
void _abrirAjustesPuntoAcceso() {
  if (!Platform.isWindows) return;
  unawaited(_abrirAjustesPuntoAccesoAsync());
}

Future<void> _abrirAjustesPuntoAccesoAsync() async {
  try {
    await Process.run('cmd.exe', [
      '/c',
      'start',
      'ms-settings:network-mobilehotspot',
    ]).timeout(const Duration(seconds: 5));
  } catch (_) {
    // Si Windows no abrió la página, se queda en el aviso de la propia
    // pantalla de Ajustes («conéctalo a mano»).
  }
}

/// Enciende el hotspot moderno de Windows por WinRT y espera a que pase a
/// `On`. Una línea `OK` si se consiguió; si no, el motivo.
///
/// No se usa `StartAccessPointAsync`: no existe en esta API (los métodos son
/// `StartTetheringAsync`/`StopTetheringAsync`) y su resultado es un
/// `IAsyncOperation<T>` que PowerShell no sabe resolver en `AsTask` sin
/// hacer genérico el método a mano. En su lugar se dispara la operación y se
/// sondea `TetheringOperationalState`, que es lo que de verdad dice si el
/// hotspot está encendido.
const String _scriptEncenderPuntoAcceso = r'''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue
try {
  $perfil = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()
  if ($null -eq $perfil) { Write-Output 'SIN_PERFIL'; exit 0 }
  $gestor = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]::CreateFromConnectionProfile($perfil)
  if ($gestor.TetheringOperationalState.ToString() -eq 'On') { Write-Output 'OK'; exit 0 }
  $null = $gestor.StartTetheringAsync()
  for ($i = 0; $i -lt 6; $i++) {
    Start-Sleep -Milliseconds 500
    if ($gestor.TetheringOperationalState.ToString() -eq 'On') { Write-Output 'OK'; exit 0 }
  }
  Write-Output ('ESTADO:' + $gestor.TetheringOperationalState.ToString())
} catch {
  Write-Output ('ERROR:' + $_.Exception.Message)
}
''';

/// Adaptadores IPv4 con estado `Up` (sin APIPA 169.254.*), con el de la
/// ruta por defecto (`0.0.0.0/0`, menor métrica) al principio; una línea
/// `alias|ip` por dirección.
const String _scriptInterfacesActivas = r'''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$def = (Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
  Sort-Object -Property @{Expression={$_.InterfaceMetric + $_.RouteMetric}} |
  Select-Object -First 1).ifIndex
Get-NetIPConfiguration |
  Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address } |
  Sort-Object -Property @{Expression={ if ($null -ne $def -and $_.InterfaceIndex -eq $def) { 0 } else { 1 } }} |
  ForEach-Object {
    $alias = $_.InterfaceAlias
    $_.IPv4Address | Where-Object { $_.IPAddress -notlike '169.254.*' } | ForEach-Object { "$alias|$($_.IPAddress)" }
  }
''';

/// Convierte la salida del script de interfaces activas (una línea
/// `alias|ip[,ip...]` por dirección) en pares (nombre, ip), conservando el
/// orden; lo que no tenga esa forma se ignora.
List<(String, String)> interfacesDesdePowerShell(String salida) {
  final resultado = <(String, String)>[];
  for (final linea in salida.split(RegExp(r'\r?\n'))) {
    final partes = linea.trim().split('|');
    if (partes.length != 2) continue;
    final nombre = partes[0].trim();
    if (nombre.isEmpty) continue;
    for (final candidata in partes[1].split(',')) {
      final ip = candidata.trim();
      if (ip.isNotEmpty) resultado.add((nombre, ip));
    }
  }
  return resultado;
}

/// Ordena las IPs poniendo primero las redes privadas de LAN
/// (`192.168.x`, `10.x`, `172.16-31.x`): son las que un celular en la misma
/// red Wi-Fi puede alcanzar; las públicas o de VPN van al final.
List<String> _ordenarRedesPrivadas(List<String> ips) {
  int prioridad(String ip) {
    if (ip.startsWith('192.168.')) return 0;
    if (ip.startsWith('10.')) return 1;
    final segmento = RegExp(r'^172\.(\d+)\.').firstMatch(ip);
    if (segmento != null) {
      final n = int.tryParse(segmento.group(1)!) ?? 0;
      if (n >= 16 && n <= 31) return 2;
    }
    return 3;
  }

  return [...ips]..sort((a, b) => prioridad(a).compareTo(prioridad(b)));
}

/// Índice de endpoints publicado en `GET /`.
///
/// Todas las rutas (salvo las públicas: `health`, `network`, `auth/login`,
/// `docs` y las imágenes) exigen la cabecera `Authorization: Bearer <token>`
/// obtenida en `POST /api/v1/auth/login`.
///
/// Nota: en todas las tablas `DELETE` es **borrado lógico**: marca
/// `estado = ELIMINADO` (el registro sigue en la BD y los listados lo
/// excluyen), nunca ejecuta un `DELETE` de SQL. Para verlos, añade
/// `?estado=ELIMINADO` al listado; para restaurarlos, un `PUT` con otro estado.
const List<String> _endpoints = [
  'GET    /api/v1/health',
  'GET    /api/v1/network',
  'POST   /api/v1/network/hotspot        (ajustes.editar)',
  'POST   /api/v1/auth/login            (pública)',
  'POST   /api/v1/auth/logout',
  'GET    /api/v1/auth/me',
  'GET    /api/v1/products?limit=50&offset=0&estado=&q=',
  'GET    /api/v1/products/{id}',
  'POST   /api/v1/products',
  'POST   /api/v1/products/importar',
  'PUT    /api/v1/products/{id}',
  'DELETE /api/v1/products/{id}',
  'GET    /api/v1/categorias?limit=50&offset=0&estado=&q=',
  'GET    /api/v1/categorias/{id}',
  'POST   /api/v1/categorias',
  'PUT    /api/v1/categorias/{id}',
  'DELETE /api/v1/categorias/{id}',
  'GET    /api/v1/presentaciones?limit=50&offset=0&estado=&q=',
  'GET    /api/v1/presentaciones/{id}',
  'POST   /api/v1/presentaciones',
  'PUT    /api/v1/presentaciones/{id}',
  'DELETE /api/v1/presentaciones/{id}',
  'GET    /api/v1/colores?limit=50&offset=0&estado=&q=      (categorias.ver)',
  'GET    /api/v1/colores/{id}',
  'POST   /api/v1/colores                                   (categorias.crear)',
  'PUT    /api/v1/colores/{id}                              (categorias.editar)',
  'DELETE /api/v1/colores/{id}                           (categorias.eliminar)',
  'GET    /api/v1/unidades?limit=50&offset=0&estado=&q=',
  'GET    /api/v1/unidades/{id}',
  'POST   /api/v1/unidades',
  'PUT    /api/v1/unidades/{id}',
  'DELETE /api/v1/unidades/{id}',
  'GET    /api/v1/clientes?limit=50&offset=0&estado=&q=',
  'GET    /api/v1/clientes/{id}',
  'POST   /api/v1/clientes',
  'PUT    /api/v1/clientes/{id}',
  'DELETE /api/v1/clientes/{id}',
  'GET    /api/v1/proveedores?limit=50&offset=0&estado=&q=',
  'GET    /api/v1/proveedores/{id}',
  'POST   /api/v1/proveedores',
  'PUT    /api/v1/proveedores/{id}',
  'DELETE /api/v1/proveedores/{id}',
  'GET    /api/v1/empleados?limit=50&offset=0&estado=&q=',
  'GET    /api/v1/empleados/{id}',
  'POST   /api/v1/empleados',
  'PUT    /api/v1/empleados/{id}',
  'DELETE /api/v1/empleados/{id}',
  'GET    /api/v1/usuarios?limit=50&offset=0&estado=&q=',
  'GET    /api/v1/usuarios/{id}',
  'POST   /api/v1/usuarios',
  'PUT    /api/v1/usuarios/{id}',
  'DELETE /api/v1/usuarios/{id}',
  'GET    /api/v1/roles',
  'GET    /api/v1/roles/{id}',
  'POST   /api/v1/roles',
  'PUT    /api/v1/roles/{id}',
  'DELETE /api/v1/roles/{id}',
  'GET    /api/v1/auditoria?usuario=&desde=&hasta=&entidad=&accion=&q=',
  'DELETE /api/v1/auditoria/antes-de/{fecha}',
  'DELETE /api/v1/auditoria/todo',
  'GET    /api/v1/ordenes?limit=50&offset=0&estado=&q=',
  'GET    /api/v1/ordenes/{id}',
  'POST   /api/v1/ordenes',
  'PUT    /api/v1/ordenes/{id}/estado',
  'DELETE /api/v1/ordenes/{id}',
  'GET    /api/v1/ordenes/{id}/detalles',
  'POST   /api/v1/ordenes/{id}/detalles',
  'DELETE /api/v1/ordenes/{id}/detalles/{productoId}',
  'GET    /api/v1/facturas?limit=50&offset=0&estado=&q=',
  'GET    /api/v1/facturas/{id}',
  'POST   /api/v1/facturas',
  'PUT    /api/v1/facturas/{id}/estado',
  'DELETE /api/v1/facturas/{id}',
  'GET    /api/v1/cotizaciones?limit=50&offset=0&estado=&q=',
  'GET    /api/v1/cotizaciones/{id}',
  'POST   /api/v1/cotizaciones',
  'PUT    /api/v1/cotizaciones/{id}/estado',
  'DELETE /api/v1/cotizaciones/{id}',
  'GET    /api/v1/reportes/ventas?desde=&hasta=&agrupacion=  (reportes.ver)',
  'GET    /api/v1/reportes/ventas-productos?desde=&hasta=    (reportes.ver)',
  'GET    /api/v1/reportes/productos-vendidos?limite=6&orden=desc (reportes.ver)',
  'GET    /api/v1/ajustes',
  'PUT    /api/v1/ajustes               (permiso ajustes.editar)',
  'POST   /api/v1/respaldos               (permiso ajustes.editar)',
  'GET    /api/v1/respaldos               (permiso ajustes.ver)',
  'GET    /api/v1/respaldos/{nombre}/descarga',
  'POST   /api/v1/archivos/imagenes        (subida en base64)',
  'GET    /api/v1/archivos/imagenes/{nombre}',
  'GET    /api/v1/chat/estado',
  'POST   /api/v1/chat                     {mensajes:[{role,content}]}',
  'POST   /api/v1/chat/modelo/descargar',
  'GET    /api/v1/chat/modelo/descarga',
  'GET    /docs            (Swagger UI)',
  'GET    /openapi.json    (especificación OpenAPI)',
];
