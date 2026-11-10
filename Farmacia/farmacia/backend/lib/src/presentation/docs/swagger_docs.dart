import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_swagger_ui/shelf_swagger_ui.dart';

/// Documentación OpenAPI de la API.
///
/// Carga y valida `doc/openapi.json` al arrancar y lo **recarga solo** cuando
/// el archivo cambia en disco (comparando su fecha de modificación), de modo
/// que editar la especificación no obliga a reiniciar el servidor. Expone:
///  - [ui]: Swagger UI interactivo en `/docs`
///  - [spec]: la especificación cruda en `/openapi.json` (para Postman,
///    Insomnia, generadores de clientes...)
///
/// Si la especificación falta o es inválida, ambos son `null` y la API
/// sigue funcionando sin documentación. Un JSON inválido *después* de un
/// arranque correcto no rompe nada: se sirve la última versión buena.
final class SwaggerDocs {
  SwaggerDocs._(this._file, this._spec, this._modified);

  /// Archivo de la especificación (`null` si no se encontró).
  final File? _file;

  /// JSON normalizado de la especificación (`null` si no está disponible).
  String? _spec;

  /// Fecha de modificación de [_file] correspondiente a [_spec].
  DateTime? _modified;

  factory SwaggerDocs.load({required bool enabled}) {
    if (!enabled) return SwaggerDocs._(null, null, null);

    final file = _findSpecFile();
    if (file == null) {
      stderr.writeln(
        'Aviso: no se encontró doc/openapi.json; la documentación '
        '(/docs y /openapi.json) no estará disponible.',
      );
      return SwaggerDocs._(null, null, null);
    }

    try {
      // Se valida y normaliza para que el navegador reciba JSON correcto.
      final spec = _parse(file);
      return SwaggerDocs._(file, spec, file.statSync().modified);
    } on FormatException catch (error) {
      stderr.writeln(
        'Aviso: doc/openapi.json no es JSON válido (${error.message}); '
        'la documentación no estará disponible.',
      );
      return SwaggerDocs._(file, null, null);
    }
  }

  /// Handler de Swagger UI (`/docs`).
  ///
  /// Se construye en cada petición para que refleje la última versión del
  /// archivo; la página apenas se consulta, así el coste es despreciable.
  Handler? get ui {
    if (_spec == null) return null;
    return (Request request) => SwaggerUI(
      _actual() ?? '',
      specType: SpecType.json,
      title: 'Farmacia API',
      docExpansion: DocExpansion.list,
      deepLink: true,
    ).call(request);
  }

  /// Handler de la especificación OpenAPI (`/openapi.json`).
  Handler? get spec {
    if (_spec == null) return null;
    return (Request _) => Response.ok(
      _actual() ?? '',
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  bool get available => _spec != null;

  /// JSON servido en este momento: si `doc/openapi.json` cambió en disco,
  /// se vuelve a leer y validar; si el cambio es inválido o ilegible se
  /// conserva la última versión buena.
  String? _actual() {
    final file = _file;
    if (file == null || _spec == null) return _spec;

    final DateTime modified;
    try {
      modified = file.statSync().modified;
    } on FileSystemException {
      return _spec; // Transitorio (archivo borrado a medias): última buena.
    }
    if (modified == _modified) return _spec;

    try {
      _spec = _parse(file);
      _modified = modified;
    } on FormatException catch (error) {
      stderr.writeln(
        'Aviso: doc/openapi.json no es JSON válido (${error.message}); '
        'se mantiene la última versión válida.',
      );
    } on FileSystemException {
      // Transitorio: se mantiene la última versión válida.
    }
    return _spec;
  }

  static String _parse(File file) =>
      jsonEncode(jsonDecode(file.readAsStringSync()));

  /// Localiza `doc/openapi.json` sin depender del directorio de trabajo.
  static File? _findSpecFile() {
    const candidates = ['doc/openapi.json', 'backend/doc/openapi.json'];
    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) return file;
    }

    // Relativo a este script: <proyecto>/bin/server.dart -> <proyecto>/doc
    final script = File(Platform.script.toFilePath());
    final file = File(
      '${script.parent.parent.path}${Platform.pathSeparator}'
      'doc${Platform.pathSeparator}openapi.json',
    );
    return file.existsSync() ? file : null;
  }
}
