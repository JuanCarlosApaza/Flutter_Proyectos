/// Valores permitidos de los enums de negocio de PostgreSQL.
///
/// El dominio es quien conoce qué estados existen: si mañana se añade un
/// estado a la BD, se añade aquí (y en la migración correspondiente).
///
/// Cada conjunto corresponde a un `CREATE TYPE` de la migraciones
/// `001_esquema_farmacia` y `002_borrado_logico`.
library;

import '../../core/errors/app_exception.dart';

/// Estado que marca un registro **oculto** (borrado lógico).
///
/// En esta aplicación **jamás se borra una fila**: el `DELETE` de la API solo
/// escribe `estado = 'ELIMINADO'`, y los listados la excluyen por defecto. El
/// registro sigue existiendo en la BD (historial, foreign keys, auditoría).
///
/// Se puede recuperar con un `PUT` que escriba otro estado
/// (`?estado=ELIMINADO` en el listado sirve para localizarlo).
const String estadoEliminado = 'ELIMINADO';

/// `estado_general`: categorías, marcas, tallas, colores, clientes,
/// proveedores y usuarios.
const Set<String> estadosGenerales = {
  'ACTIVO',
  'INACTIVO',
  'BLOQUEADO',
  estadoEliminado,
};

/// `estado_empleado`: empleados.
const Set<String> estadosEmpleados = {
  'ACTIVO',
  'VACACIONES',
  'LICENCIA',
  'INACTIVO',
  estadoEliminado,
};

/// `estado_producto`: productos.
const Set<String> estadosProductos = {
  'DISPONIBLE',
  'AGOTADO',
  'DESCONTINUADO',
  estadoEliminado,
};

/// `estado_orden`: órdenes de pedido.
const Set<String> estadosOrdenes = {
  'PENDIENTE',
  'PAGADO',
  'CANCELADO',
  'DEVUELTO',
  estadoEliminado,
};

/// `estado_factura`: facturas.
const Set<String> estadosFacturas = {'EMITIDA', 'ANULADA', estadoEliminado};

/// `estado_cotizacion`: cotizaciones (no toca stock: el estado es solo
/// seguimiento comercial).
const Set<String> estadosCotizaciones = {
  'VIGENTE',
  'ACEPTADA',
  'RECHAZADA',
  estadoEliminado,
};

/// ¿Se pueden editar las **líneas** de una orden en este estado?
///
/// Única definición del predicado: la usa el dominio (`OrdenPedido.editable`)
/// y también la capa de datos al validar bajo el bloqueo de la fila, así que
/// ambos lados siempre coinciden.
bool esOrdenEditable(String estado) =>
    estado == 'PENDIENTE' || estado == 'DEVUELTO';

/// Valida que [valor] pertenezca a [permitidos]; si no, lanza `400`.
///
/// Devuelve el valor validado para poder encadenarlo.
String ensureEstado(String valor, Set<String> permitidos, String campo) {
  if (!permitidos.contains(valor)) {
    throw BadRequestException(
      'El campo "$campo" debe ser uno de: ${permitidos.join(', ')} '
      '(recibido: "$valor").',
      code: 'estado_invalido',
    );
  }
  return valor;
}
