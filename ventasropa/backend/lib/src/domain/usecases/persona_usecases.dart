import '../../core/errors/app_exception.dart';
import '../entities/persona.dart';
import '../repositories/persona_repository.dart';
import '../rules/estados.dart';
import '../rules/validaciones.dart';

/// Casos de uso de clientes.
final class Clientes {
  const Clientes({required this.repository});

  final PersonaRepository repository;

  Future<List<Cliente>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findClientes(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  /// Total de clientes con los mismos filtros que [listar] (COUNT real).
  Future<int> contar({String? estado, String? q}) => repository.countClientes(
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  Future<Cliente> obtener(int id) async {
    final cliente = await repository.findClienteById(id);
    if (cliente == null) {
      throw NotFoundException(
        'El cliente $id no existe.',
        code: 'cliente_no_encontrado',
      );
    }
    return cliente;
  }

  Future<Cliente> crear({
    required String nombre,
    required String apellido,
    String? direccion,
    String? ciudad,
    String? genero,
    String? ci,
    String? telefono,
    String estado = 'ACTIVO',
  }) => repository.insertCliente(
    Cliente(
      id: 0,
      nombre: ensureNombre(nombre),
      apellido: ensureApellido(apellido),
      direccion: direccion,
      ciudad: ciudad,
      genero: ensureGenero(genero),
      ci: ensureCi(ci),
      telefono: ensureTelefono(telefono),
      estado: ensureEstado(estado, estadosGenerales, 'estado'),
      fechaCreacion: DateTime.now(),
      fechaActualizacion: DateTime.now(),
    ),
  );

  /// Actualización parcial: solo se escriben los campos de [campos]; dentro
  /// de ellos, `null` borra el valor en la BD.
  Future<Cliente> actualizar(int id, Cliente datos, Set<String> campos) async {
    if (campos.isEmpty) {
      throw const BadRequestException(
        'Indica al menos un campo a actualizar.',
        code: 'fields_required',
      );
    }
    await obtener(id);
    return repository.updateCliente(
      id,
      Cliente(
        id: id,
        nombre: campos.contains('nombre')
            ? ensureNombre(datos.nombre)
            : datos.nombre,
        apellido: campos.contains('apellido')
            ? ensureApellido(datos.apellido)
            : datos.apellido,
        direccion: datos.direccion,
        ciudad: datos.ciudad,
        genero: campos.contains('genero')
            ? ensureGenero(datos.genero)
            : datos.genero,
        // Los campos no enviados llegan en `null` (el repositorio solo
        // escribe los de `campos`); el CI es obligatorio, así que solo se
        // exige cuando viaja en la petición (borrarlo tampoco está permitido).
        ci: campos.contains('ci') ? ensureCi(datos.ci) : datos.ci,
        telefono: ensureTelefono(datos.telefono),
        estado: campos.contains('estado')
            ? ensureEstado(datos.estado, estadosGenerales, 'estado')
            : datos.estado,
        fechaCreacion: datos.fechaCreacion,
        fechaActualizacion: datos.fechaActualizacion,
      ),
      campos,
    );
  }

  Future<void> eliminar(int id) async {
    await obtener(id);
    final removed = await repository.deleteCliente(id);
    if (!removed) {
      throw NotFoundException(
        'El cliente $id no existe.',
        code: 'cliente_no_encontrado',
      );
    }
  }
}

/// Casos de uso de proveedores.
final class Proveedores {
  const Proveedores({required this.repository});

  final PersonaRepository repository;

  Future<List<Proveedor>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findProveedores(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  /// Total de proveedores con los mismos filtros que [listar] (COUNT real).
  Future<int> contar({String? estado, String? q}) =>
      repository.countProveedores(
        estado: estado == null
            ? null
            : ensureEstado(estado, estadosGenerales, 'estado'),
        q: q,
      );

  Future<Proveedor> obtener(int id) async {
    final proveedor = await repository.findProveedorById(id);
    if (proveedor == null) {
      throw NotFoundException(
        'El proveedor $id no existe.',
        code: 'proveedor_no_encontrado',
      );
    }
    return proveedor;
  }

  Future<Proveedor> crear({
    required String nombre,
    String? direccion,
    String? ciudad,
    String? telefono,
    String? email,
    String? nit,
    String estado = 'ACTIVO',
  }) => repository.insertProveedor(
    Proveedor(
      id: 0,
      nombre: ensureNombre(nombre),
      direccion: direccion,
      ciudad: ciudad,
      telefono: ensureTelefono(telefono),
      email: ensureEmail(email),
      nit: ensureNit(nit),
      estado: ensureEstado(estado, estadosGenerales, 'estado'),
      fechaCreacion: DateTime.now(),
      fechaActualizacion: DateTime.now(),
    ),
  );

  /// Actualización parcial: solo se escriben los campos de [campos].
  Future<Proveedor> actualizar(
    int id,
    Proveedor datos,
    Set<String> campos,
  ) async {
    if (campos.isEmpty) {
      throw const BadRequestException(
        'Indica al menos un campo a actualizar.',
        code: 'fields_required',
      );
    }
    await obtener(id);
    return repository.updateProveedor(
      id,
      Proveedor(
        id: id,
        nombre: campos.contains('nombre')
            ? ensureNombre(datos.nombre)
            : datos.nombre,
        direccion: datos.direccion,
        ciudad: datos.ciudad,
        telefono: ensureTelefono(datos.telefono),
        email: ensureEmail(datos.email),
        nit: ensureNit(datos.nit),
        estado: campos.contains('estado')
            ? ensureEstado(datos.estado, estadosGenerales, 'estado')
            : datos.estado,
        fechaCreacion: datos.fechaCreacion,
        fechaActualizacion: datos.fechaActualizacion,
      ),
      campos,
    );
  }

  Future<void> eliminar(int id) async {
    await obtener(id);
    final removed = await repository.deleteProveedor(id);
    if (!removed) {
      throw NotFoundException(
        'El proveedor $id no existe.',
        code: 'proveedor_no_encontrado',
      );
    }
  }
}

/// Casos de uso de empleados.
final class Empleados {
  const Empleados({required this.repository});

  final PersonaRepository repository;

  Future<List<Empleado>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findEmpleados(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosEmpleados, 'estado'),
    q: q,
  );

  /// Total de empleados con los mismos filtros que [listar] (COUNT real).
  Future<int> contar({String? estado, String? q}) => repository.countEmpleados(
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosEmpleados, 'estado'),
    q: q,
  );

  Future<Empleado> obtener(int id) async {
    final empleado = await repository.findEmpleadoById(id);
    if (empleado == null) {
      throw NotFoundException(
        'El empleado $id no existe.',
        code: 'empleado_no_encontrado',
      );
    }
    return empleado;
  }

  Future<Empleado> crear({
    required String nombre,
    required String apellido,
    String? direccion,
    String? ciudad,
    int? edad,
    String? telefono,
    String estado = 'ACTIVO',
  }) => repository.insertEmpleado(
    Empleado(
      id: 0,
      nombre: ensureNombre(nombre),
      apellido: ensureApellido(apellido),
      direccion: direccion,
      ciudad: ciudad,
      edad: ensureEdad(edad),
      telefono: ensureTelefono(telefono),
      estado: ensureEstado(estado, estadosEmpleados, 'estado'),
      fechaCreacion: DateTime.now(),
      fechaActualizacion: DateTime.now(),
    ),
  );

  /// Actualización parcial: solo se escriben los campos de [campos]; la edad
  /// se valida solo si se envía.
  Future<Empleado> actualizar(
    int id,
    Empleado datos,
    Set<String> campos,
  ) async {
    if (campos.isEmpty) {
      throw const BadRequestException(
        'Indica al menos un campo a actualizar.',
        code: 'fields_required',
      );
    }
    await obtener(id);
    return repository.updateEmpleado(
      id,
      Empleado(
        id: id,
        nombre: campos.contains('nombre')
            ? ensureNombre(datos.nombre)
            : datos.nombre,
        apellido: campos.contains('apellido')
            ? ensureApellido(datos.apellido)
            : datos.apellido,
        direccion: datos.direccion,
        ciudad: datos.ciudad,
        edad: campos.contains('edad') ? ensureEdad(datos.edad) : datos.edad,
        telefono: ensureTelefono(datos.telefono),
        estado: campos.contains('estado')
            ? ensureEstado(datos.estado, estadosEmpleados, 'estado')
            : datos.estado,
        fechaCreacion: datos.fechaCreacion,
        fechaActualizacion: datos.fechaActualizacion,
      ),
      campos,
    );
  }

  Future<void> eliminar(int id) async {
    await obtener(id);
    final removed = await repository.deleteEmpleado(id);
    if (!removed) {
      throw NotFoundException(
        'El empleado $id no existe.',
        code: 'empleado_no_encontrado',
      );
    }
  }
}
