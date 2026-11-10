/// Punto de arranque del backend embebido.
///
/// Exporta la implementación de la plataforma: en web (donde `dart:io` no
/// existe) va el stub; en las plataformas con `dart:io` (Android, escritorio)
/// va el servidor real — que además solo arranca si el build define
/// `SERVIDOR_EMBEBIDO=1`.
library;

export 'servidor_embebido_io.dart' if (dart.library.html) 'servidor_embebido_web.dart';
