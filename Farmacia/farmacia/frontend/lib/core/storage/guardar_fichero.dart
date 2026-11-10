/// Guarda un fichero en el equipo de quien lo pide.
///
/// * Móvil → hoja nativa de compartir (el celular no tiene «Guardar como»).
/// * Escritorio → diálogo «Guardar como» del sistema.
/// * Web → descarga del navegador (variante propia).
///
/// Devuelve `true` si se guardó/compartió y `false` si se canceló el
/// diálogo o la hoja.
library;

export 'guardar_fichero_stub.dart'
    if (dart.library.js_interop) 'guardar_fichero_web.dart';
