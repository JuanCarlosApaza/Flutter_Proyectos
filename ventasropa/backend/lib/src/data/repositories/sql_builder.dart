/// Constructor de sentencias SQL parametrizadas.
///
/// Capa `data/`: aquí solo se genera SQL con **marcadores posicionales**
/// (`$1`, `$2`...). Las claves de los mapas son nombres de columna del propio
/// código (nunca datos del usuario), de modo que la interpolación es segura.
library;

import '../../domain/rules/estados.dart';
import '../database/dialecto.dart';

/// Condición que descarta los registros **ocultos** por borrado lógico.
///
/// Se usa en los listados (vía [whereEstado]) y en las consultas de líneas de
/// una orden, donde ya hay un `WHERE` y hace falta un `AND`.
const String estadoVisible = "estado <> '$estadoEliminado'";

/// `UPDATE` que recalcula `productos.stock` como la **suma de sus variantes
/// visibles** y ajusta el estado (`AGOTADO` al llegar a 0, `DISPONIBLE` al
/// reponer), sin tocar un producto `DESCONTINUADO` u oculto.
///
/// Toma un único parámetro: el `producto_id`. Lo usan el repositorio de
/// productos (al editar una variante) y el de ventas (al cobrar/devolver),
/// para que el agregado siempre se recalcule igual y en la misma
/// transacción que el cambio de variante.
const String recalcularStockProducto =
    'UPDATE productos SET '
    'stock = COALESCE((SELECT SUM(stock) FROM producto_variantes '
    'WHERE producto_id = \$1 AND $estadoVisible), 0), '
    'estado = CASE '
    "WHEN estado IN ('DESCONTINUADO', 'ELIMINADO') THEN estado "
    'WHEN COALESCE((SELECT SUM(stock) FROM producto_variantes '
    "WHERE producto_id = \$1 AND $estadoVisible), 0) <= 0 "
    "THEN 'AGOTADO'::estado_producto "
    "ELSE 'DISPONIBLE'::estado_producto END, "
    'version = version + 1 '
    'WHERE producto_id = \$1';

/// Construye la cláusula `WHERE` de un listado filtrable por `estado`.
///
/// Reglas de **borrado lógico** (la API nunca borra filas):
///
/// * `estado == null` → solo registros **visibles**: se excluyen los ocultos
///   (`estado = 'ELIMINADO'`).
/// * `estado == 'ELIMINADO'` → solo los ocultos. La interfaz no lo expone,
///   pero la API lo permite para localizarlos/restaurarlos con un `PUT`.
/// * cualquier otro valor → ese estado exacto.
///
/// Cuando filtra por parámetro usa `$1`, por lo que el valor de `estado` debe
/// viajar como **primer** parámetro de la consulta. [tipo] es el enum de
/// PostgreSQL de la columna (`estado_general`, `estado_producto`...): usar el
/// enum equivocado hace que PostgreSQL falle con *operator does not exist*.
String whereEstado(String? estado, String tipo) =>
    estado == null ? ' WHERE $estadoVisible' : ' WHERE estado = \$1::$tipo';

/// Construye la cláusula `SET` de un `UPDATE` a partir de los campos a
/// modificar: `('direccion = $1, estado = $2::estado_general', [valor, estado])`.
///
/// * `cambios`: columna de BD -> valor (`null` escribe `NULL`).
/// * `casts`: columnas que necesitan conversión explícita (p. ej. los enums).
/// * `columnaFecha`: si no es `null`, se añade al final
///   `<columna> = CURRENT_TIMESTAMP` para que el `RETURNING` devuelva la
///   fecha ya actualizada (el trigger de la tabla escribe el mismo valor en
///   la BD). `Roles` no tiene esa columna y lo pasa como `null`.
///
/// Lanza [StateError] si no hay campos: nunca debe generarse un `SET` vacío.
({String set, List<Object?> params}) updateSet(
  Map<String, Object?> cambios, {
  Map<String, String> casts = const {},
  String? columnaFecha = 'fecha_actualizacion',
}) {
  if (cambios.isEmpty) {
    throw StateError('updateSet: la lista de campos está vacía.');
  }

  final params = <Object?>[];
  final parts = <String>[];

  cambios.forEach((columna, valor) {
    params.add(valor);
    final cast = casts[columna];
    parts.add('$columna = \$${params.length}${cast == null ? '' : '::$cast'}');
  });
  if (columnaFecha != null) parts.add('$columnaFecha = CURRENT_TIMESTAMP');

  return (set: parts.join(', '), params: params);
}

/// Patrón ILIKE sin comodines: escapa `\`, `%` y `_`.
String escaparPatron(String valor) => valor
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');

const String _acentoDesde =
    'áàäâéèëêíìïîóòöôúùüûñçÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑÇ';
const String _acentoHasta =
    'aaaaeeeeiiiioooouuuuncAAAAEEEEIIIIOOOOUUUUNC';

/// Condición `AND` de búsqueda libre (`?q=`) sobre todas las columnas de la
/// fila referenciada por [tabla] (el nombre de la tabla como fila: p. ej.
/// `to_jsonb(productos)`), insensible a mayúsculas y a acentos — espejo del
/// buscador del frontend. Devuelve SQL vacío si `q` no aporta nada.
///
/// [param] es el número de parámetro posicional que llevará el valor.
/// IMPORTANTE: se escapa el valor con [escaparPatron] para que `%`, `_` y
/// `\` del usuario no actúen como comodines.
///
/// En PostgreSQL la fila entera se voltea con `to_jsonb(fila)::text`; SQLite
/// no tiene esa función y concatena las columnas de [columnasBusqueda] (con
/// `ESCAPE '\'` para que el escape de [escaparPatron] signifique lo mismo
/// que en PostgreSQL).
({String sql, List<Object?> params}) andBusqueda(
  String tabla,
  String? q,
  int param,
) {
  final limpio = q?.trim() ?? '';
  if (limpio.isEmpty) return (sql: '', params: const []);

  if (Dialecto.sqlite) {
    final columnas = columnasBusqueda[tabla];
    if (columnas == null) {
      throw StateError(
        'andBusqueda: falta definir columnasBusqueda["$tabla"] para SQLite.',
      );
    }
    final fila = columnas
        .map((columna) => "ifnull(CAST($tabla.$columna AS TEXT), '')")
        .join(" || ' ' || ");
    return (
      sql: " AND translate($fila, '$_acentoDesde', '$_acentoHasta') "
          "LIKE '%' || translate(\$$param, '$_acentoDesde', "
          "'$_acentoHasta') || '%' ESCAPE '\\'",
      params: [escaparPatron(limpio)],
    );
  }

  return (
    sql: " AND translate(to_jsonb($tabla)::text, '$_acentoDesde', "
        "'$_acentoHasta') ILIKE '%' || translate(\$$param, '$_acentoDesde', "
        "'$_acentoHasta') || '%'",
    params: [escaparPatron(limpio)],
  );
}

/// Columnas que participan en la búsqueda libre por tabla (rama de SQLite;
/// `contrasena` queda fuera a propósito: no es texto buscable).
const Map<String, List<String>> columnasBusqueda = {
  'auditoria': [
    'id',
    'fecha',
    'usuario_id',
    'nombre_usuario',
    'rol',
    'accion',
    'exitoso',
    'codigo_error',
    'entidad',
    'entidad_id',
    'resumen',
    'detalles',
    'ip',
  ],
  'cotizaciones': [
    'cotizacion_id',
    'cliente_id',
    'nombre_cliente',
    'empleado_id',
    'fecha_cotizacion',
    'total',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
  'categorias': [
    'categoria_id',
    'nombre_categoria',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
  'marcas': [
    'marca_id',
    'nombre_marca',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
  'tallas': [
    'talla_id',
    'nombre',
    'orden',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
  'colores': [
    'color_id',
    'nombre',
    'codigo_hex',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
  'producto_variantes': [
    'variante_id',
    'producto_id',
    'talla_id',
    'color_id',
    'stock',
    'codigo',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
  'clientes': [
    'cliente_id',
    'nombre_cliente',
    'apellido',
    'direccion',
    'ciudad',
    'genero',
    'ci',
    'telefono',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
  'proveedores': [
    'proveedor_id',
    'nombre_proveedor',
    'direccion',
    'ciudad',
    'telefono',
    'email',
    'nit',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
  'empleados': [
    'empleado_id',
    'nombre_empleado',
    'apellido',
    'direccion',
    'ciudad',
    'edad',
    'telefono',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
  'productos': [
    'producto_id',
    'nombre_producto',
    'codigo',
    'imagen',
    'descripcion',
    'unidad',
    'precio_venta',
    'precio_compra',
    'precio_rebaja',
    'stock',
    'stock_minimo',
    'version',
    'categoria_id',
    'proveedor_id',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
  'ordenes_pedidos': [
    'orden_id',
    'fecha_orden',
    'cliente_id',
    'nombre_cliente',
    'empleado_id',
    'total',
    'rebaja',
    'factura',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
  'facturas': [
    'factura_numero',
    'fecha_factura',
    'empleado_id',
    'cliente_id',
    'orden_id',
    'subtotal',
    'rebaja',
    'iva',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
  'u': [
    'usuario_id',
    'empleado_id',
    'rol_id',
    'nombre_usuario',
    'estado',
    'fecha_creacion',
    'fecha_actualizacion',
  ],
};
