import 'dart:io';

/// Servidor estático para el build de release del frontend.
///
/// Uso (desde `frontend/`):
/// ```sh
/// dart run tool/serve_web.dart                 # 0.0.0.0:8081 sirve build/web
/// dart run tool/serve_web.dart --port 9000 --host 127.0.0.1 --dir build/web
/// ```
///
/// Por qué existe (y no se usa un servidor genérico):
///
/// * Escucha en `0.0.0.0` por defecto → el celular en la misma red Wi-Fi
///   puede abrir la app (un servidor en `127.0.0.1` no sirve).
/// * Sirve el **MIME correcto** para `wasm` (`application/wasm`), `js` y
///   `json`: con el MIME equivocado CanvasKit no carga y la página queda en
///   blanco.
/// * `cache-control: no-cache` en HTML/JS/JSON para que tras un
///   `flutter build web --release` se vean los cambios sin depender de la
///   caché del navegador (el service worker de Flutter se encarga del resto).
/// * **Compresión gzip** en texto/wasm si el cliente la pide: `main.dart.js`
///   baja de 3,3 MB a 1 MB y `canvaskit.wasm` de 5,3 MB a 2 MB (la primera
///   carga en el celular pasa de ~8,7 MB a ~3 MB). Solo se comprime una vez
///   por fichero (resultado cacheado en memoria).
/// * **`ETag`** para que esas recargas con `no-cache` no bajen el fichero
///   entero: el navegador revalida y el servidor responde `304` sin cuerpo.
/// * `Vary: Accept-Encoding`, para que nadie cachee la versión comprimida
///   como si fuera la normal.
Future<void> main(List<String> args) async {
  var host = '0.0.0.0';
  var port = 8081;
  var directorio = 'build/web';

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    final valor = i + 1 < args.length ? args[i + 1] : '';
    switch (arg) {
      case '--host':
        host = valor;
        i++;
      case '--port':
        port = int.tryParse(valor) ?? port;
        i++;
      case '--dir':
        directorio = valor;
        i++;
      case '--help' || '-h':
        stdout.writeln(
          'Uso: dart run tool/serve_web.dart '
          '[--host 0.0.0.0] [--port 8081] [--dir build/web]',
        );
        return;
      default:
        stderr.writeln('Argumento desconocido: $arg (usa --help)');
        exitCode = 64;
        return;
    }
  }

  final raiz = Directory(directorio);
  if (!raiz.existsSync()) {
    stderr.writeln(
      'No existe "$directorio". Compila antes con: flutter build web --release',
    );
    exitCode = 78;
    return;
  }
  final raizAbsoluta = raiz.absolute.path.replaceAll('\\', '/');

  final server = await HttpServer.bind(host, port);
  stdout.writeln('Front sirviendo en http://$host:$port');
  stdout.writeln('  Directorio: ${raiz.absolute.path}');
  stdout.writeln('  URL PC:     http://localhost:$port');
  stdout.writeln('  Ctrl+C para detener\n');

  await for (final request in server) {
    try {
      await _responder(request, raizAbsoluta);
    } on Object catch (error) {
      stderr.writeln('Error sirviendo ${request.uri.path}: $error');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } on Object {
        // La conexión ya se cerró; nada que hacer.
      }
    }
  }
}

Future<void> _responder(HttpRequest request, String raizAbsoluta) async {
  if (request.method != 'GET' && request.method != 'HEAD') {
    request.response.statusCode = HttpStatus.methodNotAllowed;
    await request.response.close();
    return;
  }

  // `/` -> index.html; cualquier directorio con barra final también.
  var ruta = Uri.decodeComponent(request.uri.path);
  if (ruta.endsWith('/')) ruta = '${ruta}index.html';

  // Bloquea traversal fuera del directorio raíz (`../`, rutas absolutas).
  final limpio = ruta.replaceAll('\\', '/');
  if (limpio.contains('..') || limpio.contains(':')) {
    request.response.statusCode = HttpStatus.forbidden;
    await request.response.close();
    return;
  }

  final fichero = File('$raizAbsoluta${limpio.startsWith('/') ? limpio : '/$limpio'}');
  final existe = await fichero.exists();
  final esIndice = !existe && limpio.endsWith('index.html');
  if (!existe && !esIndice) {
    request.response.statusCode = HttpStatus.notFound;
    request.response.headers.contentType = ContentType.text;
    request.response.write('404: ${request.uri.path}');
    await request.response.close();
    return;
  }
  if (!existe) {
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
    return;
  }

  final extension = fichero.path.split('.').last.toLowerCase();
  final tipo = _mime[extension] ?? 'application';
  final subtipo = _subtipo[extension] ?? 'octet-stream';
  final respuesta = request.response;
  respuesta.headers.contentType = ContentType(
    tipo,
    subtipo,
    charset: _charset[extension],
  );
  // Sin caché en código: un rebuild debe verse al instante en PC y celular.
  respuesta.headers.set(
    'cache-control',
    _sinCacha.contains(extension) ? 'no-cache' : 'public, max-age=300',
  );

  final tamano = await fichero.length();
  final mtime = (await fichero.lastModified()).millisecondsSinceEpoch;

  // gzip solo si el cliente lo admite y el formato compensa (los binarios ya
  // comprimidos —png, woff2— no se tocan).
  final comprimir = _comprimibles.contains(extension) && _aceptaGzip(request);

  // ETag único por fichero **y** por codificación: así `If-None-Match`
  // devuelve 304 y el navegador no vuelve a bajar 3,3 MB en cada recarga.
  final etag =
      '"${tamano.toRadixString(16)}-${mtime.toRadixString(16)}'
      '${comprimir ? '-gz' : ''}"';
  respuesta.headers.set(HttpHeaders.etagHeader, etag);
  respuesta.headers.set('vary', 'accept-encoding');

  final ifNoneMatch = request.headers.value(HttpHeaders.ifNoneMatchHeader);
  if (ifNoneMatch != null && _coincideEtag(ifNoneMatch, etag)) {
    respuesta.statusCode = HttpStatus.notModified;
    await respuesta.close();
    return;
  }

  final Stream<List<int>> cuerpo;
  if (comprimir) {
    final comprimido = await _gzipDe(fichero, '$tamano-$mtime-${fichero.path}');
    respuesta.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
    respuesta.contentLength = comprimido.length;
    cuerpo = Stream<List<int>>.value(comprimido);
  } else {
    respuesta.contentLength = tamano;
    cuerpo = fichero.openRead();
  }

  if (request.method == 'HEAD') {
    await respuesta.close();
    return;
  }
  await respuesta.addStream(cuerpo);
  await respuesta.close();
}

/// gzip de [fichero], cacheado por fichero+mtime: comprimir `main.dart.js`
/// cuesta ~80 ms y `canvaskit.wasm` ~120 ms, y solo interesa hacerlo una vez.
final Map<String, List<int>> _gzipCache = {};

Future<List<int>> _gzipDe(File fichero, String clave) async {
  final cacheado = _gzipCache[clave];
  if (cacheado != null) return cacheado;
  if (_gzipCache.length > 64) _gzipCache.clear();
  final trozos = await gzip.encoder.bind(fichero.openRead()).toList();
  final completo = <int>[
    for (final trozo in trozos) ...trozo,
  ];
  _gzipCache[clave] = completo;
  return completo;
}

/// ¿El cliente acepta gzip?
bool _aceptaGzip(HttpRequest request) {
  final cabecera = request.headers.value(HttpHeaders.acceptEncodingHeader);
  if (cabecera == null) return false;
  // Se ignora `identity;q=1, gzip;q=0` (caso raro pero barato de cubrir).
  if (RegExp(r'gzip\s*;\s*q=0(\.0+)?\b').hasMatch(cabecera)) return false;
  return cabecera.contains('gzip');
}

/// `If-None-Match` coincide: admite `*`, listas, comillas y prefijo débil
/// `W/`. Se comparan las etiquetas ya normalizadas para no depender de cómo
/// las reenvíe cada cliente.
bool _coincideEtag(String cabecera, String etag) {
  if (cabecera.trim() == '*') return true;
  final propio = _normalizaEtag(etag);
  for (final candidata in cabecera.split(',')) {
    if (_normalizaEtag(candidata) == propio) return true;
  }
  return false;
}

String _normalizaEtag(String valor) {
  var s = valor.trim();
  if (s.startsWith('W/')) s = s.substring(2);
  if (s.length > 1 && s.startsWith('"') && s.endsWith('"')) {
    s = s.substring(1, s.length - 1);
  }
  return s;
}

/// Extensiones que merece la pena comprimir (texto o wasm; los formatos ya
/// comprimidos —png, jpg, woff2— solo costarían CPU).
const Set<String> _comprimibles = {
  'html',
  'js',
  'mjs',
  'css',
  'json',
  'map',
  'txt',
  'svg',
  'wasm',
  'webmanifest',
  'symbols',
  'notices',
};

/// MIME por extensión. Los tres críticos: `wasm`, `js` y `json`.
const Map<String, String> _mime = {
  'html': 'text',
  'js': 'text',
  'mjs': 'text',
  'css': 'text',
  'txt': 'text',
  'json': 'application',
  'map': 'application',
  'wasm': 'application',
  'webmanifest': 'application',
  'png': 'image',
  'jpg': 'image',
  'jpeg': 'image',
  'gif': 'image',
  'webp': 'image',
  'svg': 'image',
  'ico': 'image',
  'woff': 'font',
  'woff2': 'font',
  'ttf': 'font',
  'otf': 'font',
};

/// Subtipo y charset por extensión (los ausentes usan `octet-stream`).
const Map<String, String> _subtipo = {
  'html': 'html',
  'js': 'javascript',
  'mjs': 'javascript',
  'css': 'css',
  'txt': 'plain',
  'json': 'json',
  'map': 'json',
  'wasm': 'wasm',
  'webmanifest': 'manifest+json',
  'png': 'png',
  'jpg': 'jpeg',
  'jpeg': 'jpeg',
  'gif': 'gif',
  'webp': 'webp',
  'svg': 'svg+xml',
  'ico': 'x-icon',
  'woff': 'woff',
  'woff2': 'woff2',
  'ttf': 'ttf',
  'otf': 'otf',
};

const Map<String, String> _charset = {
  'html': 'utf-8',
  'js': 'utf-8',
  'mjs': 'utf-8',
  'css': 'utf-8',
  'txt': 'utf-8',
  'json': 'utf-8',
  'map': 'utf-8',
};

/// Extensiones que deben revalidarse siempre (código que cambia en rebuilds).
const Set<String> _sinCacha = {'html', 'js', 'mjs', 'json', 'map', 'txt'};
