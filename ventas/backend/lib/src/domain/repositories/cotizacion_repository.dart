import '../entities/cotizacion.dart';

/// Contrato del repositorio de cotizaciones.
///
/// El dominio define el *qué*; `data/` decide el *cómo* (SQL, transacciones).
abstract interface class CotizacionRepository {
  /// Listado de cabeceras (sin líneas), más reciente primero.
  Future<List<Cotizacion>> findCotizaciones({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de cotizaciones del listado con los mismos filtros (COUNT real).
  Future<int> countCotizaciones({String? estado, String? q});

  /// Cabecera con sus líneas (`detalles`); `null` si no existe.
  Future<Cotizacion?> findCotizacionById(int id);

  /// Inserta la cabecera y sus líneas en **una transacción** y devuelve la
  /// cotización persistida con las líneas ya puestas.
  Future<Cotizacion> insertCotizacion(
    Cotizacion datos,
    List<DetalleCotizacion> detalles,
  );

  /// Cambia el estado (`VIGENTE` <-> `ACEPTADA` <-> `RECHAZADA`).
  Future<Cotizacion> updateEstadoCotizacion(int id, String estado);

  /// Borrado lógico: `true` si se ocultó ahora (el registro sigue en la BD).
  Future<bool> deleteCotizacion(int id);
}
