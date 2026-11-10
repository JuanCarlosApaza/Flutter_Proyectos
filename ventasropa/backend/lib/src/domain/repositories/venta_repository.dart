import '../entities/venta.dart';

/// Contrato del repositorio de ventas (órdenes, detalles y facturas).
///
/// El dominio define el *qué*; `data/` decide el *cómo*. Las operaciones que
/// deben ser atómicas (crear una orden con sus líneas, descontar stock) se
/// exponen como una sola llamada para que se ejecuten en transacción.
abstract interface class VentaRepository {
  // --- Órdenes ------------------------------------------------------------
  Future<List<OrdenPedido>> findOrdenes({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de órdenes del listado con los mismos filtros (COUNT real).
  Future<int> countOrdenes({String? estado, String? q});

  Future<OrdenPedido?> findOrdenById(int id);

  /// Inserta la cabecera, sus líneas y sus pagos en una **transacción** y
  /// devuelve la orden persistida (con su `id`).
  Future<OrdenPedido> insertOrden(
    OrdenPedido datos,
    List<DetalleOrden> detalles,
    List<Pago> pagos,
  );

  /// Líneas de pago de la orden (el desglose efectivo + QR etc.).
  Future<List<Pago>> findPagosByOrden(int ordenId);

  /// Cambia el estado de la orden en **una sola transacción**, con la fila
  /// bloqueada (`SELECT ... FOR UPDATE`) para serializar los cobros,
  /// cancelaciones y ediciones concurrentes de la misma orden.
  ///
  /// Reglas aplicadas bajo el bloqueo:
  ///
  /// * si el estado actual ya es [nuevoEstado] no hace nada (idempotente:
  ///   dos peticiones `PAGADO` simultáneas descuentan stock **una** vez);
  /// * si el estado actual no es [estadoActualEsperado] (otro usuario lo
  ///   cambió entre la lectura y el bloqueo) lanza `409 estado_cambiado`;
  /// * [descontarStock] aplica el cobro y [reponerStock] revierte, ambos en
  ///   la misma transacción que el `UPDATE` de estado.
  Future<OrdenPedido> cambiarEstadoAtomico(
    int ordenId, {
    required String estadoActualEsperado,
    required String nuevoEstado,
    required bool descontarStock,
    required bool reponerStock,
  });

  /// Borrado lógico: `true` si se ocultó ahora (el registro sigue en la BD).
  ///
  /// Las líneas de la orden **no** se borran: siguen en su tabla y la orden
  /// oculta simplemente deja de mostrarse con ellas.
  Future<bool> deleteOrden(int id);

  // --- Detalles ------------------------------------------------------------
  Future<List<DetalleOrden>> findDetallesByOrden(int ordenId);

  Future<DetalleOrden?> findDetalle(int ordenId, int varianteId);

  /// Inserta o reemplaza la línea (PK compuesta variante+orden) y
  /// recalcula el total.
  ///
  /// Si la línea ya existía **oculta**, se revive (la clave primaria sigue
  /// ocupada: no se crea una fila nueva). Se ejecuta con la fila de la orden
  /// bloqueada y validando que siga editable, para que no se cruce con un
  /// cobro concurrente.
  Future<DetalleOrden> upsertDetalle(DetalleOrden detalle);

  /// Borrado lógico de la línea: se oculta y se recalcula el total.
  ///
  /// Igual que [upsertDetalle]: con la orden bloqueada y editable bajo el
  /// bloqueo.
  Future<bool> deleteDetalle(int ordenId, int varianteId);

  // --- Facturas ------------------------------------------------------------
  Future<List<Factura>> findFacturas({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de facturas del listado con los mismos filtros (COUNT real).
  Future<int> countFacturas({String? estado, String? q});

  Future<Factura?> findFacturaById(int id);

  /// Factura de la orden.
  ///
  /// Por defecto solo considera las **visibles** (una factura oculta ya no
  /// impide ocultar la orden). Pasa `incluirOcultas: true` para comprobar la
  /// unicidad real antes de emitir: la columna `orden_id` es `UNIQUE` y la
  /// fila oculta sigue ocupándola.
  Future<Factura?> findFacturaByOrden(
    int ordenId, {
    bool incluirOcultas = false,
  });

  Future<Factura> insertFactura(Factura datos);

  Future<Factura> updateEstadoFactura(int id, String estado);

  /// Borrado lógico: `true` si se ocultó ahora (el registro sigue en la BD).
  Future<bool> deleteFactura(int id);
}
