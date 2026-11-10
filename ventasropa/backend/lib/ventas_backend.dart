/// Punto de entrada público del backend.
///
/// Existe para que la app Flutter pueda embeberlo (build de APK con
/// `--dart-define=SERVIDOR_EMBEBIDO=1`) sin importar rutas `src/` de otro
/// paquete. El escritorio/web no lo usan: allí el backend corre aparte
/// contra PostgreSQL, como hasta ahora.
library;

export 'src/app.dart';
export 'src/core/config/app_config.dart';
