import '../entities/persona.dart';

/// Contrato del repositorio de personas (clientes, proveedores, empleados).
///
/// El dominio define el *qué*; `data/` decide el *cómo* (SQL, caché...).
abstract interface class PersonaRepository {
  // --- Clientes -----------------------------------------------------------
  Future<List<Cliente>> findClientes({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de clientes del listado con los mismos filtros (COUNT real).
  Future<int> countClientes({String? estado, String? q});

  Future<Cliente?> findClienteById(int id);

  Future<Cliente> insertCliente(Cliente datos);

  /// Escribe únicamente los campos indicados en [campos] (nombres de
  /// campos de dominio); `null` en un campo enviado borra su valor.
  Future<Cliente> updateCliente(int id, Cliente datos, Set<String> campos);

  Future<bool> deleteCliente(int id);

  // --- Proveedores --------------------------------------------------------
  Future<List<Proveedor>> findProveedores({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de proveedores del listado con los mismos filtros (COUNT real).
  Future<int> countProveedores({String? estado, String? q});

  Future<Proveedor?> findProveedorById(int id);

  Future<Proveedor> insertProveedor(Proveedor datos);

  /// Escribe únicamente los campos indicados en [campos].
  Future<Proveedor> updateProveedor(
    int id,
    Proveedor datos,
    Set<String> campos,
  );

  Future<bool> deleteProveedor(int id);

  // --- Empleados ----------------------------------------------------------
  Future<List<Empleado>> findEmpleados({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de empleados del listado con los mismos filtros (COUNT real).
  Future<int> countEmpleados({String? estado, String? q});

  Future<Empleado?> findEmpleadoById(int id);

  Future<Empleado> insertEmpleado(Empleado datos);

  /// Escribe únicamente los campos indicados en [campos].
  Future<Empleado> updateEmpleado(int id, Empleado datos, Set<String> campos);

  Future<bool> deleteEmpleado(int id);
}
