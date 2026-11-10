/// Motor SQL activo en el proceso del backend.
///
/// El mismo código de repositorios/consultas debe funcionar contra
/// PostgreSQL (escritorio/web) y contra SQLite (APK embebida). Lo que no se
/// resuelve con la traducción automática del driver (funciones de fecha,
/// agregados con `FILTER`...) se ramifica consultando este marcador.
///
/// Se activa en el propio constructor de `SqliteDatabase`; los dobles en
/// memoria de los tests dejan el valor en `false` (PostgreSQL), que es el
/// dialecto para el que está escrito el SQL por defecto.
final class Dialecto {
  const Dialecto._();

  /// `true` si las consultas se ejecutarán contra SQLite.
  static bool sqlite = false;
}
