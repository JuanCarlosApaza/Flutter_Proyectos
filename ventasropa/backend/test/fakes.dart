import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/domain/entities/auditoria.dart';
import 'package:ventas_backend/src/domain/entities/product.dart';
import 'package:ventas_backend/src/domain/entities/variante.dart';
import 'package:ventas_backend/src/domain/entities/rol.dart';
import 'package:ventas_backend/src/domain/entities/usuario.dart';
import 'package:ventas_backend/src/domain/entities/venta.dart';
import 'package:ventas_backend/src/domain/repositories/auditoria_repository.dart';
import 'package:ventas_backend/src/domain/repositories/product_repository.dart';
import 'package:ventas_backend/src/domain/repositories/rol_repository.dart';
import 'package:ventas_backend/src/domain/repositories/usuario_repository.dart';
import 'package:ventas_backend/src/domain/repositories/venta_repository.dart';
import 'package:ventas_backend/src/domain/rules/estados.dart';

/// Producto de prueba (precio, stock y estado configurables).
Product productoDePrueba({
  int id = 1,
  String nombre = 'Paracetamol 500 mg',
  double precioVenta = 2.45,
  double? precioCompra = 1.20,
  double? precioRebaja,
  double stock = 10,
  String estado = 'DISPONIBLE',
  int version = 0,
}) => Product(
  id: id,
  nombre: nombre,
  precioVenta: precioVenta,
  precioCompra: precioCompra,
  precioRebaja: precioRebaja,
  stock: stock,
  estado: estado,
  version: version,
);

/// Pago de prueba con las fechas ya rellenas.
Pago pagoDePrueba({
  required double monto,
  String metodoPago = 'EFECTIVO',
  String? referencia,
}) => Pago(
  metodoPago: metodoPago,
  monto: monto,
  referencia: referencia,
  fechaCreacion: DateTime.now(),
  fechaActualizacion: DateTime.now(),
);

/// Usuario de prueba con permisos configurables.
Usuario usuarioDePrueba({
  int id = 1,
  int rolId = 1,
  String nivel = 'ADMIN',
  Set<String> permisos = const {},
  String estado = 'ACTIVO',
  String contrasena = 'secreto123',
  String nombreUsuario = 'usuario.test',
}) => Usuario(
  id: id,
  empleadoId: null,
  rolId: rolId,
  nivelUsuario: nivel,
  permisos: permisos,
  nombreUsuario: nombreUsuario,
  contrasena: contrasena,
  estado: estado,
  fechaCreacion: DateTime.now(),
  fechaActualizacion: DateTime.now(),
);

/// Rol de prueba.
Rol rolDePrueba({
  int id = 1,
  String nombre = 'ADMIN',
  bool esSistema = true,
  Set<String> permisos = const {},
  String estado = 'ACTIVO',
}) => Rol(
  id: id,
  nombre: nombre,
  descripcion: null,
  esSistema: esSistema,
  estado: estado,
  permisos: permisos,
  fechaCreacion: DateTime.now(),
  fechaActualizacion: DateTime.now(),
);

/// Doble en memoria de [RolRepository].
final class FakeRolRepository implements RolRepository {
  FakeRolRepository({List<Rol>? roles, Map<int, int>? usuariosActivos})
    : roles = [...?roles],
      usuariosActivos = {...?usuariosActivos};

  final List<Rol> roles;
  final Map<int, int> usuariosActivos;
  int _siguienteId = 100;

  @override
  Future<List<Rol>> findAll({
    int limit = 50,
    int offset = 0,
    String? estado,
  }) async => roles.skip(offset).take(limit).toList();

  @override
  Future<Rol?> findById(int id) async =>
      roles.where((r) => r.id == id).firstOrNull;

  @override
  Future<Set<String>> permisosDeRol(int rolId) async =>
      (await findById(rolId))?.permisos ?? <String>{};

  @override
  Future<Map<int, Set<String>>> permisosPorRol() async => {
    for (final rol in roles) rol.id: rol.permisos,
  };

  @override
  Future<Rol> insert(Rol datos, Set<String> permisos) async {
    final creado = rolDePrueba(
      id: _siguienteId++,
      nombre: datos.nombre,
      esSistema: datos.esSistema,
      permisos: permisos,
      estado: datos.estado,
    );
    roles.add(creado);
    return creado;
  }

  @override
  Future<Rol> update(
    int id,
    Rol datos,
    Set<String> campos, {
    Set<String>? permisos,
  }) async {
    final index = roles.indexWhere((r) => r.id == id);
    final actual = roles[index];
    final actualizado = Rol(
      id: id,
      nombre: campos.contains('nombre') ? datos.nombre : actual.nombre,
      descripcion: campos.contains('descripcion')
          ? datos.descripcion
          : actual.descripcion,
      esSistema: actual.esSistema,
      estado: campos.contains('estado') ? datos.estado : actual.estado,
      permisos: permisos ?? actual.permisos,
      fechaCreacion: actual.fechaCreacion,
      fechaActualizacion: DateTime.now(),
    );
    roles[index] = actualizado;
    return actualizado;
  }

  @override
  Future<bool> delete(int id) async {
    final index = roles.indexWhere((r) => r.id == id);
    if (index < 0) return false;
    roles.removeAt(index);
    return true;
  }

  @override
  Future<int> contarUsuariosActivos(int rolId) async =>
      usuariosActivos[rolId] ?? 0;
}

/// `true` si [texto] contiene [q] sin distinguir mayúsculas (o si `q`
/// viene vacío). Los fakes lo usan para emular la búsqueda `?q=`.
bool contiene(String? texto, String? q) {
  final limpio = q?.trim() ?? '';
  if (limpio.isEmpty) return true;
  return (texto ?? '').toLowerCase().contains(limpio.toLowerCase());
}

/// Doble en memoria de [UsuarioRepository].
final class FakeUsuarioRepository implements UsuarioRepository {
  FakeUsuarioRepository({List<Usuario>? usuarios})
    : usuarios = [...?usuarios],
      _siguienteId = usuarios == null || usuarios.isEmpty
          ? 1
          : usuarios.last.id + 1;

  final List<Usuario> usuarios;
  int _siguienteId;

  /// Los mismos filtros que aplicaría la BD (estado exacto + `q` parcial
  /// sobre el nombre de login) para que `findAll` y `count` coincidan.
  List<Usuario> _filtrados({String? estado, String? q}) => usuarios
      .where(
        (u) =>
            (estado == null || u.estado == estado) &&
            contiene(u.nombreUsuario, q),
      )
      .toList();

  @override
  Future<List<Usuario>> findAll({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async => _filtrados(estado: estado, q: q)
      .skip(offset)
      .take(limit)
      .toList();

  @override
  Future<int> count({String? estado, String? q}) async =>
      _filtrados(estado: estado, q: q).length;

  @override
  Future<Usuario?> findById(int id) async =>
      usuarios.where((u) => u.id == id).firstOrNull;

  @override
  Future<Usuario?> findByNombreUsuario(String nombreUsuario) async =>
      usuarios.where((u) => u.nombreUsuario == nombreUsuario).firstOrNull;

  @override
  Future<Usuario> insert(Usuario datos) async {
    final creado = Usuario(
      id: _siguienteId++,
      empleadoId: datos.empleadoId,
      rolId: datos.rolId,
      nivelUsuario: datos.nivelUsuario,
      nombreUsuario: datos.nombreUsuario,
      contrasena: datos.contrasena,
      estado: datos.estado,
      fechaCreacion: DateTime.now(),
      fechaActualizacion: DateTime.now(),
    );
    usuarios.add(creado);
    return creado;
  }

  @override
  Future<Usuario> update(int id, Usuario datos, Set<String> campos) async {
    final index = usuarios.indexWhere((u) => u.id == id);
    final actual = usuarios[index];
    final actualizado = Usuario(
      id: id,
      empleadoId: campos.contains('empleadoId')
          ? datos.empleadoId
          : actual.empleadoId,
      rolId: campos.contains('rolId') ? datos.rolId : actual.rolId,
      nivelUsuario: datos.nivelUsuario,
      nombreUsuario: campos.contains('nombreUsuario')
          ? datos.nombreUsuario
          : actual.nombreUsuario,
      contrasena: campos.contains('contrasena')
          ? datos.contrasena
          : actual.contrasena,
      estado: campos.contains('estado') ? datos.estado : actual.estado,
      fechaCreacion: actual.fechaCreacion,
      fechaActualizacion: DateTime.now(),
    );
    usuarios[index] = actualizado;
    return actualizado;
  }

  @override
  Future<bool> delete(int id) async {
    final index = usuarios.indexWhere((u) => u.id == id);
    if (index < 0) return false;
    usuarios.removeAt(index);
    return true;
  }
}

/// Doble en memoria de [AuditoriaRepository]; captura el último filtro de
/// [listar] y puede simular un fallo de BD en [registrar].
final class FakeAuditoriaRepository implements AuditoriaRepository {
  final List<AuditoriaEvento> eventos = [];

  /// Si es `true`, [registrar] lanza (para probar que no se propaga).
  bool fallarAlRegistrar = false;

  ({
    String? usuario,
    DateTime? desde,
    DateTime? hasta,
    String? entidad,
    String? accion,
    String? q,
  })?
  ultimoFiltro;

  @override
  Future<void> registrar(AuditoriaEvento evento) async {
    if (fallarAlRegistrar) throw StateError('la BD no responde');
    eventos.add(evento);
  }

  /// Aplica los **mismos filtros que la BD**: usuario por parcial sobre
  /// `nombreUsuario`, fechas (ambos días incluidos), entidad/acción por
  /// igualdad exacta y `q` como búsqueda libre sobre el texto del evento.
  /// [listar] y [count] comparten este método para que siempre coincidan.
  List<AuditoriaEvento> filtrados({
    String? usuario,
    DateTime? desde,
    DateTime? hasta,
    String? entidad,
    String? accion,
    String? q,
  }) => eventos.where((e) {
    if (usuario != null &&
        usuario.trim().isNotEmpty &&
        !contiene(e.nombreUsuario, usuario)) {
      return false;
    }
    if (desde != null && e.fecha.isBefore(desde)) return false;
    // `hasta` incluye el día completo (igual que el `WHERE` de la BD).
    if (hasta != null && !e.fecha.isBefore(hasta.add(const Duration(days: 1)))) {
      return false;
    }
    if (entidad != null && entidad.isNotEmpty && e.entidad != entidad) {
      return false;
    }
    if (accion != null && accion.isNotEmpty && e.accion != accion) {
      return false;
    }
    final texto = [
      e.nombreUsuario,
      e.rol,
      e.accion,
      e.entidad,
      e.resumen,
      e.ip,
    ].join(' ');
    return contiene(texto, q);
  }).toList();

  @override
  Future<List<AuditoriaEvento>> listar({
    int limit = 50,
    int offset = 0,
    String? usuario,
    DateTime? desde,
    DateTime? hasta,
    String? entidad,
    String? accion,
    String? q,
  }) async {
    ultimoFiltro = (
      usuario: usuario,
      desde: desde,
      hasta: hasta,
      entidad: entidad,
      accion: accion,
      q: q,
    );
    return filtrados(
      usuario: usuario,
      desde: desde,
      hasta: hasta,
      entidad: entidad,
      accion: accion,
      q: q,
    ).skip(offset).take(limit).toList();
  }

  @override
  Future<int> count({
    String? usuario,
    DateTime? desde,
    DateTime? hasta,
    String? entidad,
    String? accion,
    String? q,
  }) async => filtrados(
    usuario: usuario,
    desde: desde,
    hasta: hasta,
    entidad: entidad,
    accion: accion,
    q: q,
  ).length;

  @override
  Future<int> eliminarAntesDe(DateTime fecha) async {
    final borrados = eventos.where((e) => e.fecha.isBefore(fecha)).length;
    eventos.removeWhere((e) => e.fecha.isBefore(fecha));
    return borrados;
  }

  @override
  Future<int> eliminarTodo() async {
    final total = eventos.length;
    eventos.clear();
    return total;
  }
}

/// Doble en memoria de [ProductRepository].
final class FakeProductoRepository implements ProductRepository {
  FakeProductoRepository({List<Product>? productos})
    : productos = [...?productos],
      _siguienteId = productos == null || productos.isEmpty
          ? 1
          : productos.map((p) => p.id).reduce((a, b) => a > b ? a : b) + 1,
      _siguienteVarianteId = 1 {
    // Toda prenda sin variantes recibe la variante única (Única/Único) con
    // su stock, igual que el repositorio real al crear un producto.
    for (var i = 0; i < this.productos.length; i++) {
      final p = this.productos[i];
      if (p.variantes.isEmpty) {
        this.productos[i] = p.conVariantes([_varianteUnica(p.id, p.stock)]);
      }
    }
  }

  final List<Product> productos;
  int _siguienteId;
  int _siguienteVarianteId;

  ProductoVariante _varianteUnica(int productoId, double stock) =>
      ProductoVariante(
        id: _siguienteVarianteId++,
        productoId: productoId,
        tallaId: 1,
        colorId: 1,
        nombreTalla: 'Única',
        nombreColor: 'Único',
        stock: stock,
      );

  // --- Catálogos simulados de tallas/colores -------------------------------
  //
  // El repositorio real resuelve en la BD los nombres que vienen escritos a
  // mano en una variante (y los crea si no existían); aquí se hace lo mismo
  // con dos mapas nombre → id.

  final Map<String, int> _tallas = {};
  final Map<String, int> _colores = {};
  int _siguienteTalla = 1000;
  int _siguienteColor = 1000;

  /// Un lado de una variante: con id se usa tal cual (etiqueta `T{id}` /
  /// `C{id}`, como siempre) y sin id el nombre se da de alta en el catálogo
  /// simulado —sin distinguir mayúsculas, igual que la BD—.
  ({int id, String nombre}) _ladoDeCatalogo(
    int id,
    String? nombre, {
    required String prefijo,
    required Map<String, int> catalogo,
    required int Function() siguiente,
  }) {
    if (id > 0) return (id: id, nombre: '$prefijo$id');
    final texto = (nombre ?? '').trim();
    for (final entrada in catalogo.entries) {
      if (entrada.key.toLowerCase() == texto.toLowerCase()) {
        return (id: entrada.value, nombre: entrada.key);
      }
    }
    final nuevo = siguiente();
    catalogo[texto] = nuevo;
    return (id: nuevo, nombre: texto);
  }

  ({int tallaId, String talla, int colorId, String color}) _resolverLados(
    DatoVariante v,
  ) {
    final talla = _ladoDeCatalogo(
      v.tallaId,
      v.talla,
      prefijo: 'T',
      catalogo: _tallas,
      siguiente: () => _siguienteTalla++,
    );
    final color = _ladoDeCatalogo(
      v.colorId,
      v.color,
      prefijo: 'C',
      catalogo: _colores,
      siguiente: () => _siguienteColor++,
    );
    return (
      tallaId: talla.id,
      talla: talla.nombre,
      colorId: color.id,
      color: color.nombre,
    );
  }

  /// Variante construida desde un [DatoVariante] con los lados ya resueltos
  /// (id propio, o el que le dio de alta el catálogo simulado).
  ProductoVariante _varianteDe(int productoId, DatoVariante v) {
    final lados = _resolverLados(v);
    return ProductoVariante(
      id: _siguienteVarianteId++,
      productoId: productoId,
      tallaId: lados.tallaId,
      colorId: lados.colorId,
      nombreTalla: lados.talla,
      nombreColor: lados.color,
      stock: v.stock,
      codigo: v.codigo,
    );
  }

  /// Copia de [p] con los campos que cambian en cada operación.
  Product _copia(
    Product p, {
    double? stock,
    String? estado,
    List<ProductoVariante>? variantes,
    int? version,
  }) => Product(
    id: p.id,
    nombre: p.nombre,
    codigo: p.codigo,
    imagen: p.imagen,
    unidad: p.unidad,
    precioVenta: p.precioVenta,
    precioCompra: p.precioCompra,
    precioRebaja: p.precioRebaja,
    stock: stock ?? p.stock,
    stockMinimo: p.stockMinimo,
    categoriaId: p.categoriaId,
    proveedorId: p.proveedorId,
    estado: estado ?? p.estado,
    version: version ?? p.version + 1,
    variantes: variantes ?? p.variantes,
  );

  /// Suma las variantes visibles al producto y mueve el estado
  /// DISPONIBLE/AGOTADO como hace la BD (mismo criterio que
  /// `recalcularStockProducto`).
  Product _recalcular(Product p, {List<ProductoVariante>? variantes}) {
    final visibles = (variantes ?? p.variantes)
        .where((v) => v.estado != estadoEliminado)
        .toList();
    final agregado = visibles.fold<double>(0, (suma, v) => suma + v.stock);
    final estado = switch (p.estado) {
      'DESCONTINUADO' || estadoEliminado => p.estado,
      _ => agregado <= 0 ? 'AGOTADO' : 'DISPONIBLE',
    };
    return _copia(
      p,
      stock: agregado,
      estado: estado,
      variantes: variantes ?? p.variantes,
    );
  }

  Product? porId(int id) => productos.where((p) => p.id == id).firstOrNull;

  /// Cambia el stock de una variante y recalcula el agregado del producto
  /// (simula el descuento/reposición de `cambiarEstadoAtomico`).
  void ajustarVariante(int varianteId, double delta) {
    final index = productos.indexWhere(
      (p) => p.variantes.any((v) => v.id == varianteId),
    );
    if (index < 0) return;
    final actual = productos[index];
    final variantes = [
      for (final v in actual.variantes)
        v.id == varianteId ? v.copiaCon(stock: v.stock + delta) : v,
    ];
    productos[index] = _recalcular(actual, variantes: variantes);
  }

  /// Los mismos filtros que aplicaría la BD (estado exacto + `q` parcial
  /// sobre el nombre) para que `findAll` y `count` coincidan.
  List<Product> _filtrados({String? estado, String? q}) => productos
      .where(
        (p) =>
            (estado == null || p.estado == estado) && contiene(p.nombre, q),
      )
      .toList();

  @override
  Future<List<Product>> findAll({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async => _filtrados(estado: estado, q: q)
      .skip(offset)
      .take(limit)
      .toList();

  @override
  Future<int> count({String? estado, String? q}) async =>
      _filtrados(estado: estado, q: q).length;

  @override
  Future<Product?> findById(int id) async => porId(id);

  @override
  Future<Product> insert(
    Product datos, {
    List<DatoVariante> variantes = const [],
  }) async {
    final id = _siguienteId++;
    final creadas = variantes.isEmpty
        ? [_varianteUnica(id, datos.stock)]
        : [for (final v in variantes) _varianteDe(id, v)];
    final agregado = creadas.fold<double>(0, (suma, v) => suma + v.stock);
    final creado = Product(
      id: id,
      nombre: datos.nombre,
      codigo: datos.codigo,
      imagen: datos.imagen,
      unidad: datos.unidad,
      precioVenta: datos.precioVenta,
      precioCompra: datos.precioCompra,
      precioRebaja: datos.precioRebaja,
      stock: agregado,
      stockMinimo: datos.stockMinimo,
      categoriaId: datos.categoriaId,
      proveedorId: datos.proveedorId,
      estado: datos.estado,
      version: 1,
      variantes: creadas,
    );
    productos.add(creado);
    return creado;
  }

  @override
  Future<Product> update(
    int id,
    Product datos,
    Set<String> campos, {
    int? versionEsperado,
  }) async {
    final index = productos.indexWhere((p) => p.id == id);
    if (index < 0) throw NotFoundException('El producto $id no existe.');
    final actual = productos[index];
    if (versionEsperado != null && versionEsperado != actual.version) {
      throw ConflictException(
        'El producto fue editado por otra persona.',
        code: 'producto_desactualizado',
      );
    }
    final actualizado = Product(
      id: id,
      nombre: campos.contains('nombre') ? datos.nombre : actual.nombre,
      codigo: campos.contains('codigo') ? datos.codigo : actual.codigo,
      imagen: campos.contains('imagen') ? datos.imagen : actual.imagen,
      unidad: campos.contains('unidad') ? datos.unidad : actual.unidad,
      precioVenta: campos.contains('precioVenta')
          ? datos.precioVenta
          : actual.precioVenta,
      precioCompra: campos.contains('precioCompra')
          ? datos.precioCompra
          : actual.precioCompra,
      precioRebaja: campos.contains('precioRebaja')
          ? datos.precioRebaja
          : actual.precioRebaja,
      stock: actual.stock,
      stockMinimo: campos.contains('stockMinimo')
          ? datos.stockMinimo
          : actual.stockMinimo,
      categoriaId: campos.contains('categoriaId')
          ? datos.categoriaId
          : actual.categoriaId,
      proveedorId: campos.contains('proveedorId')
          ? datos.proveedorId
          : actual.proveedorId,
      estado: campos.contains('estado') ? datos.estado : actual.estado,
      version: actual.version + 1,
      variantes: actual.variantes,
    );
    productos[index] = actualizado;
    return actualizado;
  }

  @override
  Future<bool> delete(int id) async {
    final index = productos.indexWhere((p) => p.id == id);
    if (index < 0) return false;
    final actual = productos[index];
    productos[index] = Product(
      id: actual.id,
      nombre: actual.nombre,
      codigo: actual.codigo,
      imagen: actual.imagen,
      unidad: actual.unidad,
      precioVenta: actual.precioVenta,
      precioCompra: actual.precioCompra,
      precioRebaja: actual.precioRebaja,
      stock: actual.stock,
      stockMinimo: actual.stockMinimo,
      categoriaId: actual.categoriaId,
      proveedorId: actual.proveedorId,
      estado: estadoEliminado,
      version: actual.version + 1,
      variantes: actual.variantes,
    );
    return true;
  }

  // --- Variantes (talla + color: el stock real) -----------------------------

  @override
  Future<List<ProductoVariante>> findVariantes(int productoId) async =>
      porId(productoId)?.variantes ?? const [];

  @override
  Future<ProductoVariante?> findVarianteById(int id) async {
    for (final p in productos) {
      for (final v in p.variantes) {
        if (v.id == id) return v;
      }
    }
    return null;
  }

  @override
  Future<ProductoVariante> insertVariante(
    int productoId,
    DatoVariante datos,
  ) async {
    final index = productos.indexWhere((p) => p.id == productoId);
    if (index < 0) {
      throw const NotFoundException(
        'El producto no existe.',
        code: 'producto_no_encontrado',
      );
    }
    final actual = productos[index];
    // Los lados se resuelven antes de mirar duplicados: un nombre escrito a
    // mano acaba en su id de catálogo, igual que en la BD.
    final lados = _resolverLados(datos);
    if (actual.variantes.any(
      (v) => v.tallaId == lados.tallaId && v.colorId == lados.colorId,
    )) {
      throw const ConflictException(
        'Esa combinación de talla y color ya existe en el producto.',
        code: 'variante_duplicada',
      );
    }
    final nueva = _varianteDe(productoId, datos);
    productos[index] = _recalcular(
      actual,
      variantes: [...actual.variantes, nueva],
    );
    return nueva;
  }

  @override
  Future<ProductoVariante> updateVariante(
    int id,
    DatoVariante datos,
    Set<String> campos,
  ) async {
    final index = productos.indexWhere(
      (p) => p.variantes.any((v) => v.id == id),
    );
    if (index < 0) {
      throw const NotFoundException(
        'La variante no existe.',
        code: 'variante_no_encontrada',
      );
    }
    final actual = productos[index];
    final variantes = [
      for (final v in actual.variantes)
        if (v.id != id)
          v
        else
          ProductoVariante(
            id: v.id,
            productoId: v.productoId,
            tallaId: campos.contains('tallaId') ? datos.tallaId : v.tallaId,
            colorId: campos.contains('colorId') ? datos.colorId : v.colorId,
            nombreTalla: v.nombreTalla,
            nombreColor: v.nombreColor,
            codigoHex: v.codigoHex,
            stock: campos.contains('stock') ? datos.stock : v.stock,
            codigo: campos.contains('codigo') ? datos.codigo : v.codigo,
            estado: v.estado,
          ),
    ];
    productos[index] = _recalcular(actual, variantes: variantes);
    return variantes.firstWhere((v) => v.id == id);
  }

  @override
  Future<bool> deleteVariante(int id) async {
    final index = productos.indexWhere(
      (p) => p.variantes.any((v) => v.id == id),
    );
    if (index < 0) return false;
    final actual = productos[index];
    final actualVariante = actual.variantes.firstWhere((v) => v.id == id);
    if (actualVariante.stock > 0.0005) {
      throw const ConflictException(
        'La variante todavía tiene stock: pon su stock a 0 antes de '
        'eliminarla.',
        code: 'variante_con_stock',
      );
    }
    final variantes = [
      for (final v in actual.variantes)
        v.id == id ? v.copiaCon(estado: estadoEliminado) : v,
    ];
    productos[index] = _recalcular(actual, variantes: variantes);
    return true;
  }
}

/// Doble en memoria de [VentaRepository]: guarda órdenes, líneas, pagos y
/// facturas, y **simula el stock** al pasar por `cambiarEstadoAtomico`
/// (descontar al cobrar, reponer al cancelar), incluida la carrera
/// `estado_cambiado`.
final class FakeVentaRepository implements VentaRepository {
  FakeVentaRepository({this.productos});

  /// Referencia al catálogo para descontar/reponer stock (opcional).
  final FakeProductoRepository? productos;

  final List<OrdenPedido> ordenes = [];
  final List<Factura> facturas = [];
  final Map<int, List<DetalleOrden>> _detalles = {};
  final Map<int, List<Pago>> _pagos = {};
  int _siguienteOrden = 1;
  int _siguienteFactura = 1;

  /// Última llamada a [cambiarEstadoAtomico] (para asertar flags de stock).
  ({
    int ordenId,
    String estadoActualEsperado,
    String nuevoEstado,
    bool descontarStock,
    bool reponerStock,
  })?
  ultimoCambio;

  /// Últimos límites recibidos por [findOrdenes] (para asertar el clamp).
  ({int limit, int offset})? ultimoListado;

  OrdenPedido? ordenPorId(int id) =>
      ordenes.where((o) => o.id == id).firstOrNull;

  Future<OrdenPedido> _cambiarEstado(
    int ordenId,
    String nuevo, {
    required bool descontarStock,
    required bool reponerStock,
  }) async {
    final index = ordenes.indexWhere((o) => o.id == ordenId);
    final actual = ordenes[index];
    final reemplazada = OrdenPedido(
      id: actual.id,
      fechaOrden: actual.fechaOrden,
      clienteId: actual.clienteId,
      nombreCliente: actual.nombreCliente,
      empleadoId: actual.empleadoId,
      pagos: actual.pagos,
      total: actual.total,
      rebaja: actual.rebaja,
      factura: actual.factura,
      estado: nuevo,
      fechaCreacion: actual.fechaCreacion,
      fechaActualizacion: DateTime.now().toUtc(),
    );
    ordenes[index] = reemplazada;
    if (descontarStock) {
      for (final linea in _detalles[ordenId] ?? const <DetalleOrden>[]) {
        productos?.ajustarVariante(linea.varianteId, -linea.cantidad);
      }
    }
    if (reponerStock) {
      for (final linea in _detalles[ordenId] ?? const <DetalleOrden>[]) {
        productos?.ajustarVariante(linea.varianteId, linea.cantidad);
      }
    }
    return reemplazada;
  }

  @override
  Future<List<OrdenPedido>> findOrdenes({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    ultimoListado = (limit: limit, offset: offset);
    return _ordenesFiltradas(estado: estado, q: q)
        .skip(offset)
        .take(limit)
        .toList();
  }

  /// Los mismos filtros que aplicaría la BD: estado exacto (o visible si no
  /// se filtra) y `q` parcial sobre el nombre del cliente.
  List<OrdenPedido> _ordenesFiltradas({String? estado, String? q}) => ordenes
      .where(
        (o) =>
            (estado == null
                ? o.estado != estadoEliminado
                : o.estado == estado) &&
            contiene(o.nombreCliente, q),
      )
      .toList();

  @override
  Future<int> countOrdenes({String? estado, String? q}) async =>
      _ordenesFiltradas(estado: estado, q: q).length;

  @override
  Future<OrdenPedido?> findOrdenById(int id) async => ordenPorId(id);

  @override
  Future<OrdenPedido> insertOrden(
    OrdenPedido datos,
    List<DetalleOrden> detalles,
    List<Pago> pagos,
  ) async {
    final id = _siguienteOrden++;
    final creada = OrdenPedido(
      id: id,
      fechaOrden: datos.fechaOrden,
      clienteId: datos.clienteId,
      nombreCliente: datos.nombreCliente,
      empleadoId: datos.empleadoId,
      pagos: pagos,
      total: datos.total,
      rebaja: datos.rebaja,
      factura: datos.factura,
      estado: datos.estado,
      fechaCreacion: datos.fechaCreacion,
      fechaActualizacion: datos.fechaActualizacion,
    );
    ordenes.add(creada);
    _detalles[id] = [...detalles];
    _pagos[id] = [...pagos];
    return creada;
  }

  @override
  Future<List<Pago>> findPagosByOrden(int ordenId) async =>
      [...?_pagos[ordenId]];

  @override
  Future<OrdenPedido> cambiarEstadoAtomico(
    int ordenId, {
    required String estadoActualEsperado,
    required String nuevoEstado,
    required bool descontarStock,
    required bool reponerStock,
  }) async {
    final index = ordenes.indexWhere((o) => o.id == ordenId);
    if (index < 0) throw NotFoundException('La orden $ordenId no existe.');
    final actual = ordenes[index];
    ultimoCambio = (
      ordenId: ordenId,
      estadoActualEsperado: estadoActualEsperado,
      nuevoEstado: nuevoEstado,
      descontarStock: descontarStock,
      reponerStock: reponerStock,
    );
    // Idempotente: dos cobros simultáneos descuentan stock una sola vez.
    if (actual.estado == nuevoEstado) return actual;
    if (actual.estado != estadoActualEsperado) {
      throw const ConflictException(
        'El estado de la orden cambió mientras se procesaba.',
        code: 'estado_cambiado',
      );
    }
    return _cambiarEstado(
      ordenId,
      nuevoEstado,
      descontarStock: descontarStock,
      reponerStock: reponerStock,
    );
  }

  @override
  Future<bool> deleteOrden(int id) async {
    final index = ordenes.indexWhere((o) => o.id == id);
    if (index < 0) return false;
    if (ordenes[index].estado == estadoEliminado) return false;
    await _cambiarEstado(id, estadoEliminado, descontarStock: false, reponerStock: false);
    return true;
  }

  @override
  Future<List<DetalleOrden>> findDetallesByOrden(int ordenId) async =>
      [...?_detalles[ordenId]];

  @override
  Future<DetalleOrden?> findDetalle(int ordenId, int varianteId) async =>
      (_detalles[ordenId] ?? const <DetalleOrden>[])
          .where((d) => d.varianteId == varianteId)
          .firstOrNull;

  @override
  Future<DetalleOrden> upsertDetalle(DetalleOrden detalle) async {
    final lineas = _detalles.putIfAbsent(detalle.ordenId, () => []);
    final index = lineas.indexWhere((d) => d.varianteId == detalle.varianteId);
    if (index < 0) {
      lineas.add(detalle);
    } else {
      lineas[index] = detalle;
    }
    return detalle;
  }

  @override
  Future<bool> deleteDetalle(int ordenId, int varianteId) async {
    final lineas = _detalles[ordenId] ?? const <DetalleOrden>[];
    final index = lineas.indexWhere((d) => d.varianteId == varianteId);
    if (index < 0) return false;
    lineas.removeAt(index);
    return true;
  }

  /// Los mismos filtros que aplicaría la BD: estado exacto (o visible si no
  /// se filtra) y `q` parcial sobre el número de factura o su estado (la
  /// factura no tiene columnas de texto libre como las órdenes).
  List<Factura> _facturasFiltradas({String? estado, String? q}) => facturas
      .where(
        (f) =>
            (estado == null
                ? f.estado != estadoEliminado
                : f.estado == estado) &&
            (contiene(f.id.toString(), q) || contiene(f.estado, q)),
      )
      .toList();

  @override
  Future<List<Factura>> findFacturas({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async => _facturasFiltradas(estado: estado, q: q)
      .skip(offset)
      .take(limit)
      .toList();

  @override
  Future<int> countFacturas({String? estado, String? q}) async =>
      _facturasFiltradas(estado: estado, q: q).length;

  @override
  Future<Factura?> findFacturaById(int id) async =>
      facturas.where((f) => f.id == id).firstOrNull;

  @override
  Future<Factura?> findFacturaByOrden(
    int ordenId, {
    bool incluirOcultas = false,
  }) async => facturas
      .where(
        (f) =>
            f.ordenId == ordenId &&
            (incluirOcultas || f.estado != estadoEliminado),
      )
      .firstOrNull;

  @override
  Future<Factura> insertFactura(Factura datos) async {
    final creada = Factura(
      id: _siguienteFactura++,
      fechaFactura: datos.fechaFactura,
      empleadoId: datos.empleadoId,
      clienteId: datos.clienteId,
      ordenId: datos.ordenId,
      subtotal: datos.subtotal,
      rebaja: datos.rebaja,
      iva: datos.iva,
      estado: datos.estado,
      fechaCreacion: datos.fechaCreacion,
      fechaActualizacion: datos.fechaActualizacion,
    );
    facturas.add(creada);
    return creada;
  }

  @override
  Future<Factura> updateEstadoFactura(int id, String estado) async {
    final index = facturas.indexWhere((f) => f.id == id);
    final actual = facturas[index];
    final actualizada = Factura(
      id: actual.id,
      fechaFactura: actual.fechaFactura,
      empleadoId: actual.empleadoId,
      clienteId: actual.clienteId,
      ordenId: actual.ordenId,
      subtotal: actual.subtotal,
      rebaja: actual.rebaja,
      iva: actual.iva,
      estado: estado,
      fechaCreacion: actual.fechaCreacion,
      fechaActualizacion: DateTime.now().toUtc(),
    );
    facturas[index] = actualizada;
    return actualizada;
  }

  @override
  Future<bool> deleteFactura(int id) async {
    final index = facturas.indexWhere((f) => f.id == id);
    if (index < 0) return false;
    if (facturas[index].estado == estadoEliminado) return false;
    facturas[index] = await updateEstadoFactura(id, estadoEliminado);
    return true;
  }
}
