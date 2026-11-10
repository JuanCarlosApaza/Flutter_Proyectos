import '../../core/errors/app_exception.dart';
import '../../domain/entities/persona.dart';
import '../../domain/repositories/persona_repository.dart';
import '../database/database.dart';
import '../database/dialecto.dart';
import '../models/persona_model.dart';
import '../models/row_utils.dart';
import 'borrado_logico.dart';
import 'sql_builder.dart';

/// Implementación SQL del contrato [PersonaRepository].
///
/// Los valores viajan siempre como parámetros posicionales (`$1`, `$2`...);
/// solo se interpolan constantes de código (nombres de tabla/columna).
final class PersonaRepositoryImpl implements PersonaRepository {
  PersonaRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _clienteColumns =
      'cliente_id, nombre_cliente, apellido, direccion, ciudad, genero, ci, '
      'telefono, estado::text AS estado, fecha_creacion, '
      'fecha_actualizacion';

  static const String _proveedorColumns =
      'proveedor_id, nombre_proveedor, direccion, ciudad, telefono, '
      'estado::text AS estado, fecha_creacion, fecha_actualizacion';

  static const String _empleadoColumns =
      'empleado_id, nombre_empleado, apellido, direccion, ciudad, edad, '
      'telefono, estado::text AS estado, fecha_creacion, '
      'fecha_actualizacion';

  /// Los mismos campos más `rol` y `permisos` de la cuenta vinculada
  /// (`usuarios.empleado_id` → `roles`). Van en subconsulta para poder
  /// filtrar por `estado` de una sola tabla; los `RETURNING` de
  /// INSERT/UPDATE usan [_empleadoColumns] y no los traen.
  ///
  /// El agregado de permisos es `string_agg` en PostgreSQL y
  /// `group_concat` (misma firma) en SQLite.
  static String get _empleadoSelect {
    final agregado = Dialecto.sqlite ? 'group_concat' : 'string_agg';
    return '$_empleadoColumns, '
        "(SELECT r.nombre FROM usuarios u JOIN roles r ON r.rol_id = u.rol_id "
        "WHERE u.empleado_id = empleados.empleado_id "
        "AND u.estado = 'ACTIVO') AS rol, "
        "COALESCE((SELECT $agregado(p.modulo || '.' || p.accion, ',') "
        'FROM usuarios u JOIN rol_permisos rp ON rp.rol_id = u.rol_id '
        'JOIN permisos p ON p.permiso_id = rp.permiso_id '
        "WHERE u.empleado_id = empleados.empleado_id "
        "AND u.estado = 'ACTIVO'), '') AS permisos";
  }

  // --- Clientes -----------------------------------------------------------

  @override
  Future<List<Cliente>> findClientes({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('clientes', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_clienteColumns FROM clientes$where${busqueda.sql} '
      'ORDER BY nombre_cliente LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(PersonaModel.cliente).toList();
  }

  @override
  Future<int> countClientes({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('clientes', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM clientes$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<Cliente?> findClienteById(int id) async {
    final rows = await _db.query(
      'SELECT $_clienteColumns FROM clientes WHERE cliente_id = \$1',
      [id],
    );
    return rows.isEmpty ? null : PersonaModel.cliente(rows.first);
  }

  @override
  Future<Cliente> insertCliente(Cliente datos) async {
    final rows = await _db.query(
      'INSERT INTO clientes (nombre_cliente, apellido, direccion, ciudad, '
      'genero, ci, telefono, estado) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8::estado_general) '
      'RETURNING $_clienteColumns',
      [
        datos.nombre,
        datos.apellido,
        datos.direccion,
        datos.ciudad,
        datos.genero,
        datos.ci,
        datos.telefono,
        datos.estado,
      ],
    );
    return PersonaModel.cliente(rows.first);
  }

  @override
  Future<Cliente> updateCliente(
    int id,
    Cliente datos,
    Set<String> campos,
  ) async {
    final cambios = <String, Object?>{
      if (campos.contains('nombre')) 'nombre_cliente': datos.nombre,
      if (campos.contains('apellido')) 'apellido': datos.apellido,
      if (campos.contains('direccion')) 'direccion': datos.direccion,
      if (campos.contains('ciudad')) 'ciudad': datos.ciudad,
      if (campos.contains('genero')) 'genero': datos.genero,
      if (campos.contains('ci')) 'ci': datos.ci,
      if (campos.contains('telefono')) 'telefono': datos.telefono,
      if (campos.contains('estado')) 'estado': datos.estado,
    };
    return _update(
      tabla: 'clientes',
      pk: 'cliente_id',
      columnas: _clienteColumns,
      cambios: cambios,
      id: id,
      noEncontrado: () => const NotFoundException(
        'El cliente no existe.',
        code: 'cliente_no_encontrado',
      ),
      model: PersonaModel.cliente,
    );
  }

  @override
  Future<bool> deleteCliente(int id) => ocultarRegistro(
    _db,
    tabla: 'clientes',
    pk: 'cliente_id',
    enumTipo: 'estado_general',
    id: id,
  );

  // --- Proveedores --------------------------------------------------------

  @override
  Future<List<Proveedor>> findProveedores({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('proveedores', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_proveedorColumns FROM proveedores$where${busqueda.sql} '
      'ORDER BY nombre_proveedor LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(PersonaModel.proveedor).toList();
  }

  @override
  Future<int> countProveedores({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('proveedores', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM proveedores$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<Proveedor?> findProveedorById(int id) async {
    final rows = await _db.query(
      'SELECT $_proveedorColumns FROM proveedores WHERE proveedor_id = \$1',
      [id],
    );
    return rows.isEmpty ? null : PersonaModel.proveedor(rows.first);
  }

  @override
  Future<Proveedor> insertProveedor(Proveedor datos) async {
    final rows = await _db.query(
      'INSERT INTO proveedores (nombre_proveedor, direccion, ciudad, '
      'telefono, estado) '
      'VALUES (\$1, \$2, \$3, \$4, \$5::estado_general) '
      'RETURNING $_proveedorColumns',
      [
        datos.nombre,
        datos.direccion,
        datos.ciudad,
        datos.telefono,
        datos.estado,
      ],
    );
    return PersonaModel.proveedor(rows.first);
  }

  @override
  Future<Proveedor> updateProveedor(
    int id,
    Proveedor datos,
    Set<String> campos,
  ) async {
    final cambios = <String, Object?>{
      if (campos.contains('nombre')) 'nombre_proveedor': datos.nombre,
      if (campos.contains('direccion')) 'direccion': datos.direccion,
      if (campos.contains('ciudad')) 'ciudad': datos.ciudad,
      if (campos.contains('telefono')) 'telefono': datos.telefono,
      if (campos.contains('estado')) 'estado': datos.estado,
    };
    return _update(
      tabla: 'proveedores',
      pk: 'proveedor_id',
      columnas: _proveedorColumns,
      cambios: cambios,
      id: id,
      noEncontrado: () => const NotFoundException(
        'El proveedor no existe.',
        code: 'proveedor_no_encontrado',
      ),
      model: PersonaModel.proveedor,
    );
  }

  @override
  Future<bool> deleteProveedor(int id) => ocultarRegistro(
    _db,
    tabla: 'proveedores',
    pk: 'proveedor_id',
    enumTipo: 'estado_general',
    id: id,
  );

  // --- Empleados ----------------------------------------------------------

  @override
  Future<List<Empleado>> findEmpleados({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    // La columna es `estado_empleado`: filtrar con `estado_general` hacía
    // fallar PostgreSQL con *operator does not exist*.
    final where = whereEstado(estado, 'estado_empleado');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('empleados', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_empleadoSelect FROM empleados$where${busqueda.sql} '
      'ORDER BY nombre_empleado LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(PersonaModel.empleado).toList();
  }

  @override
  Future<int> countEmpleados({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_empleado');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('empleados', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM empleados$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<Empleado?> findEmpleadoById(int id) async {
    final rows = await _db.query(
      'SELECT $_empleadoSelect FROM empleados WHERE empleado_id = \$1',
      [id],
    );
    return rows.isEmpty ? null : PersonaModel.empleado(rows.first);
  }

  @override
  Future<Empleado> insertEmpleado(Empleado datos) async {
    final rows = await _db.query(
      'INSERT INTO empleados (nombre_empleado, apellido, direccion, ciudad, '
      'edad, telefono, estado) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7::estado_empleado) '
      'RETURNING $_empleadoColumns',
      [
        datos.nombre,
        datos.apellido,
        datos.direccion,
        datos.ciudad,
        datos.edad,
        datos.telefono,
        datos.estado,
      ],
    );
    return PersonaModel.empleado(rows.first);
  }

  @override
  Future<Empleado> updateEmpleado(
    int id,
    Empleado datos,
    Set<String> campos,
  ) async {
    final cambios = <String, Object?>{
      if (campos.contains('nombre')) 'nombre_empleado': datos.nombre,
      if (campos.contains('apellido')) 'apellido': datos.apellido,
      if (campos.contains('direccion')) 'direccion': datos.direccion,
      if (campos.contains('ciudad')) 'ciudad': datos.ciudad,
      if (campos.contains('edad')) 'edad': datos.edad,
      if (campos.contains('telefono')) 'telefono': datos.telefono,
      if (campos.contains('estado')) 'estado': datos.estado,
    };
    return _update(
      tabla: 'empleados',
      pk: 'empleado_id',
      columnas: _empleadoColumns,
      cambios: cambios,
      id: id,
      noEncontrado: () => const NotFoundException(
        'El empleado no existe.',
        code: 'empleado_no_encontrado',
      ),
      model: PersonaModel.empleado,
      enumTipo: 'estado_empleado',
    );
  }

  @override
  Future<bool> deleteEmpleado(int id) => ocultarRegistro(
    _db,
    tabla: 'empleados',
    pk: 'empleado_id',
    enumTipo: 'estado_empleado',
    id: id,
  );

  // --- Auxiliares ---------------------------------------------------------

  /// `UPDATE <tabla> SET ... WHERE <pk> = $n RETURNING <columnas>`.
  ///
  /// [cambios] usa nombres de columna de BD (constantes del código). El campo
  /// `estado` necesita la conversión explícita al enum correspondiente
  /// ([enumTipo]), porque PostgreSQL no infiere el tipo desde un parámetro.
  Future<T> _update<T>({
    required String tabla,
    required String pk,
    required String columnas,
    required Map<String, Object?> cambios,
    required int id,
    required AppException Function() noEncontrado,
    required T Function(Map<String, Object?>) model,
    String enumTipo = 'estado_general',
  }) async {
    final upd = updateSet(cambios, casts: {'estado': enumTipo});
    final rows = await _db.query(
      'UPDATE $tabla SET ${upd.set} WHERE $pk = \$${upd.params.length + 1} '
      'RETURNING $columnas',
      [...upd.params, id],
    );
    if (rows.isEmpty) throw noEncontrado();
    return model(rows.first);
  }
}
