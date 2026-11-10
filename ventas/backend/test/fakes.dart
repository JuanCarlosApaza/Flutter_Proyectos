import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/domain/entities/auditoria.dart';
import 'package:ventas_backend/src/domain/entities/marca.dart';
import 'package:ventas_backend/src/domain/entities/product.dart';
import 'package:ventas_backend/src/domain/entities/rol.dart';
import 'package:ventas_backend/src/domain/entities/unidad_medida.dart';
import 'package:ventas_backend/src/domain/entities/usuario.dart';
import 'package:ventas_backend/src/domain/entities/venta.dart';
import 'package:ventas_backend/src/domain/repositories/auditoria_repository.dart';
import 'package:ventas_backend/src/domain/repositories/marca_repository.dart';
import 'package:ventas_backend/src/domain/repositories/product_repository.dart';
import 'package:ventas_backend/src/domain/repositories/rol_repository.dart';
import 'package:ventas_backend/src/domain/repositories/unidad_medida_repository.dart';
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
  }) async =>
      _filtrados(estado: estado, q: q).skip(offset).take(limit).toList();

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
    if (hasta != null &&
        !e.fecha.isBefore(hasta.add(const Duration(days: 1)))) {
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
          : productos.map((p) => p.id).reduce((a, b) => a > b ? a : b) + 1;

  final List<Product> productos;
  int _siguienteId;

  Product? porId(int id) => productos.where((p) => p.id == id).firstOrNull;

  /// Los productos construidos en los tests sin `variantes:` representan
  /// filas leídas como si no se hubieran adjuntado: el dominio las debe ver
  /// como la variante «Único» (todo producto real de la 022 tiene al menos
  /// una variante viva). Las filas `ELIMINADO` se ocultan, igual que en el
  /// repositorio real.
  Product _cargado(Product producto) {
    if (producto.variantes.isEmpty) {
      return producto.conVariantes([
        VarianteProducto(
          varianteId: producto.id,
          nombreColor: 'Único',
          stock: producto.stock,
        ),
      ]);
    }
    return producto.conVariantes([
      for (final v in producto.variantes)
        if (v.estado != estadoEliminado) v,
    ]);
  }

  /// Cambia el stock de un producto (lo usa el fake de ventas para simular
  /// el descuento/reposición de `cambiarEstadoAtomico`).
  ///
  /// Si el producto tiene una única variante viva almacenada, esta se
  /// sincroniza con el nuevo stock (la suma sigue cuadrando); con varias
  /// variantes propias, usa `update(variantes:)` para moverlas.
  void ajustarStock(int id, double delta) {
    final index = productos.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final actual = productos[index];
    final stock = actual.stock + delta;
    final vivas = [
      for (final v in actual.variantes)
        if (v.estado != estadoEliminado) v,
    ];
    final variantes = vivas.length == 1
        ? [
          for (final v in actual.variantes)
              v.estado == estadoEliminado
                  ? v
                  : VarianteProducto(
                    varianteId: v.varianteId,
                    nombreColor: v.nombreColor,
                    colorId: v.colorId,
                    codigoHex: v.codigoHex,
                    stock: stock,
                    estado: v.estado,
                  ),
        ]
        : actual.variantes;
    productos[index] = Product(
      id: actual.id,
      nombre: actual.nombre,
      codigo: actual.codigo,
      imagen: actual.imagen,
      descripcion: actual.descripcion,
      unidad: actual.unidad,
      precioVenta: actual.precioVenta,
      precioCompra: actual.precioCompra,
      precioRebaja: actual.precioRebaja,
      fechaVencimiento: actual.fechaVencimiento,
      stock: stock,
      stockMinimo: actual.stockMinimo,
      categoriaId: actual.categoriaId,
      proveedorId: actual.proveedorId,
      presentacionId: actual.presentacionId,
      marcaId: actual.marcaId,
      garantiaMeses: actual.garantiaMeses,
      estado: actual.estado,
      version: actual.version + 1,
      variantes: variantes,
    );
  }

  /// Los mismos filtros que aplicaría la BD (estado exacto + `q` parcial
  /// sobre el nombre + filtro de marca) para que `findAll` y `count`
  /// coincidan.
  List<Product> _filtrados({String? estado, String? q, int? marcaId}) =>
      productos
          .where(
            (p) =>
                (estado == null || p.estado == estado) &&
                (marcaId == null || p.marcaId == marcaId) &&
                contiene(p.nombre, q),
          )
          .toList();

  @override
  Future<List<Product>> findAll({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
    int? marcaId,
  }) async =>
      _filtrados(estado: estado, q: q, marcaId: marcaId)
          .skip(offset)
          .take(limit)
          .map(_cargado)
          .toList();

  @override
  Future<int> count({String? estado, String? q, int? marcaId}) async =>
      _filtrados(estado: estado, q: q, marcaId: marcaId).length;

  @override
  Future<Product?> findById(int id) async {
    final producto = porId(id);
    return producto == null ? null : _cargado(producto);
  }

  /// Mismo criterio que la implementación SQL: el código si trae uno; si no,
  /// nombre + categoría + presentación. Solo filas vivas.
  @override
  Future<bool> existe({
    String? codigo,
    String? nombre,
    int? categoriaId,
    int? presentacionId,
  }) async {
    final limpio = (codigo ?? '').trim();
    if (limpio.isNotEmpty) {
      return productos.any(
        (p) => p.estado != 'ELIMINADO' && p.codigo == limpio,
      );
    }
    final texto = (nombre ?? '').trim().toLowerCase();
    if (texto.isEmpty) return false;
    return productos.any(
      (p) =>
          p.estado != 'ELIMINADO' &&
          p.nombre.trim().toLowerCase() == texto &&
          p.categoriaId == categoriaId &&
          p.presentacionId == presentacionId,
    );
  }

  @override
  Future<Product> insert(
    Product datos, {
    List<VarianteEntrada> variantes = const [],
  }) async {
    // Mismo criterio que la BD: con filas de colores el stock agregado es la
    // suma; sin filas, la variante «Único» lleva el stock del cuerpo.
    final stock = variantes.isEmpty
        ? datos.stock
        : variantes.fold(0.0, (suma, fila) => suma + fila.cantidad);
    final creada = Product(
      id: _siguienteId++,
      nombre: datos.nombre,
      codigo: datos.codigo,
      imagen: datos.imagen,
      descripcion: datos.descripcion,
      unidad: datos.unidad,
      precioVenta: datos.precioVenta,
      precioCompra: datos.precioCompra,
      precioRebaja: datos.precioRebaja,
      fechaVencimiento: datos.fechaVencimiento,
      stock: stock,
      stockMinimo: datos.stockMinimo,
      categoriaId: datos.categoriaId,
      proveedorId: datos.proveedorId,
      presentacionId: datos.presentacionId,
      marcaId: datos.marcaId,
      garantiaMeses: datos.garantiaMeses,
      estado: datos.estado,
      version: 1,
      variantes: [
        if (variantes.isEmpty)
          VarianteProducto(
            varianteId: _siguienteId * 1000,
            nombreColor: 'Único',
            stock: stock,
          )
        else
          for (var i = 0; i < variantes.length; i++)
            VarianteProducto(
              varianteId: _siguienteId * 1000 + i,
              colorId: variantes[i].colorId,
              nombreColor: variantes[i].color ?? 'Color ${variantes[i].colorId}',
              stock: variantes[i].cantidad,
            ),
      ],
    );
    productos.add(creada);
    return creada;
  }

  @override
  Future<Product> update(
    int id,
    Product datos,
    Set<String> campos, {
    int? versionEsperado,
    List<VarianteEntrada>? variantes,
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

    var stockFinal = campos.contains('stock') ? datos.stock : actual.stock;
    var variantesFinales = actual.variantes;
    final vivas = [
      for (final v in actual.variantes)
        if (v.estado != estadoEliminado) v,
    ];
    if (variantes != null) {
      if (variantes.isEmpty) {
        // Vuelve a vender como unidad simple (variante «Único»).
        variantesFinales = [
          VarianteProducto(
            varianteId: actual.id,
            nombreColor: 'Único',
            stock: stockFinal,
          ),
        ];
      } else {
        stockFinal = variantes.fold(0.0, (suma, f) => suma + f.cantidad);
        variantesFinales = [
          for (var i = 0; i < variantes.length; i++)
            VarianteProducto(
              varianteId: actual.id * 1000 + i,
              colorId: variantes[i].colorId,
              nombreColor:
                  variantes[i].color ?? 'Color ${variantes[i].colorId}',
              stock: variantes[i].cantidad,
            ),
        ];
      }
    } else if (campos.contains('stock')) {
      // Con varias variantes vivas el stock se edita por variante.
      if (vivas.length > 1) {
        throw BadRequestException(
          'El producto tiene ${vivas.length} variantes con stock propio: '
          'edita el stock enviando el campo "variantes".',
          code: 'stock_por_variante',
        );
      }
      if (vivas.length == 1) {
        variantesFinales = [
          for (final v in actual.variantes)
            v.estado == estadoEliminado
                ? v
                : VarianteProducto(
                  varianteId: v.varianteId,
                  nombreColor: v.nombreColor,
                  colorId: v.colorId,
                  codigoHex: v.codigoHex,
                  stock: stockFinal,
                  estado: v.estado,
                ),
        ];
      }
    }

    final actualizado = Product(
      id: id,
      nombre: campos.contains('nombre') ? datos.nombre : actual.nombre,
      codigo: campos.contains('codigo') ? datos.codigo : actual.codigo,
      imagen: campos.contains('imagen') ? datos.imagen : actual.imagen,
      descripcion: campos.contains('descripcion')
          ? datos.descripcion
          : actual.descripcion,
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
      fechaVencimiento: campos.contains('fechaVencimiento')
          ? datos.fechaVencimiento
          : actual.fechaVencimiento,
      stock: stockFinal,
      stockMinimo: campos.contains('stockMinimo')
          ? datos.stockMinimo
          : actual.stockMinimo,
      categoriaId: campos.contains('categoriaId')
          ? datos.categoriaId
          : actual.categoriaId,
      proveedorId: campos.contains('proveedorId')
          ? datos.proveedorId
          : actual.proveedorId,
      presentacionId: campos.contains('presentacionId')
          ? datos.presentacionId
          : actual.presentacionId,
      marcaId: campos.contains('marcaId') ? datos.marcaId : actual.marcaId,
      garantiaMeses: campos.contains('garantiaMeses')
          ? datos.garantiaMeses
          : actual.garantiaMeses,
      estado: campos.contains('estado') ? datos.estado : actual.estado,
      version: actual.version + 1,
      variantes: variantesFinales,
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
      descripcion: actual.descripcion,
      unidad: actual.unidad,
      precioVenta: actual.precioVenta,
      precioCompra: actual.precioCompra,
      precioRebaja: actual.precioRebaja,
      fechaVencimiento: actual.fechaVencimiento,
      stock: actual.stock,
      stockMinimo: actual.stockMinimo,
      categoriaId: actual.categoriaId,
      proveedorId: actual.proveedorId,
      presentacionId: actual.presentacionId,
      marcaId: actual.marcaId,
      garantiaMeses: actual.garantiaMeses,
      estado: estadoEliminado,
      version: actual.version + 1,
    );
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
        productos?.ajustarStock(linea.productoId, -linea.cantidad);
      }
    }
    if (reponerStock) {
      for (final linea in _detalles[ordenId] ?? const <DetalleOrden>[]) {
        productos?.ajustarStock(linea.productoId, linea.cantidad);
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
    return _ordenesFiltradas(
      estado: estado,
      q: q,
    ).skip(offset).take(limit).toList();
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
  Future<List<Pago>> findPagosByOrden(int ordenId) async => [
    ...?_pagos[ordenId],
  ];

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
    await _cambiarEstado(
      id,
      estadoEliminado,
      descontarStock: false,
      reponerStock: false,
    );
    return true;
  }

  @override
  Future<List<DetalleOrden>> findDetallesByOrden(int ordenId) async => [
    ...?_detalles[ordenId],
  ];

  @override
  Future<DetalleOrden?> findDetalle(
    int ordenId,
    int productoId, {
    int? varianteId,
  }) async => (_detalles[ordenId] ?? const <DetalleOrden>[])
      .where(
        (d) =>
            d.productoId == productoId &&
            (varianteId == null || d.varianteId == varianteId),
      )
      .firstOrNull;

  @override
  Future<DetalleOrden> upsertDetalle(DetalleOrden detalle) async {
    final lineas = _detalles.putIfAbsent(detalle.ordenId, () => []);
    // La clave real de la línea es (producto, variante): mismo producto en
    // dos colores son dos filas distintas.
    final index = lineas.indexWhere(
      (d) => d.productoId == detalle.productoId && d.varianteId == detalle.varianteId,
    );
    if (index < 0) {
      lineas.add(detalle);
    } else {
      lineas[index] = detalle;
    }
    return detalle;
  }

  @override
  Future<bool> deleteDetalle(
    int ordenId,
    int productoId, {
    int? varianteId,
  }) async {
    final lineas = _detalles[ordenId] ?? const <DetalleOrden>[];
    final borradas = [
      for (final d in lineas)
        if (d.productoId == productoId &&
            (varianteId == null || d.varianteId == varianteId))
          d,
    ];
    if (borradas.isEmpty) return false;
    lineas.removeWhere(
      (d) => d.productoId == productoId &&
          (varianteId == null || d.varianteId == varianteId),
    );
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
  }) async => _facturasFiltradas(
    estado: estado,
    q: q,
  ).skip(offset).take(limit).toList();

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

/// Unidad de medida de prueba.
UnidadMedida unidadDePrueba({
  int id = 1,
  String codigo = 'KG',
  String nombre = 'Kilogramo',
  String tipo = 'PESO',
  int decimales = 3,
  String estado = 'ACTIVO',
}) => UnidadMedida(
  id: id,
  codigo: codigo,
  nombre: nombre,
  tipo: tipo,
  decimales: decimales,
  estado: estado,
  fechaCreacion: DateTime.utc(2026, 1, 1),
  fechaActualizacion: DateTime.utc(2026, 1, 1),
);

/// Doble en memoria de [UnidadMedidaRepository]: las reglas de
/// `Unidades` y de `Productos.asegurarUnidadVigente` se prueban contra
/// aquí sin tocar SQL.
final class FakeUnidadMedidaRepository implements UnidadMedidaRepository {
  FakeUnidadMedidaRepository({List<UnidadMedida>? unidades})
    : unidades = [...?unidades];

  final List<UnidadMedida> unidades;

  /// Las 15 unidades que siembra la migración 017.
  factory FakeUnidadMedidaRepository.semilla() => FakeUnidadMedidaRepository(
    unidades: [
      for (final (i, codigo, nombre, tipo, decimales)
          in <(int, String, String, String, int)>[
            (1, 'KG', 'Kilogramo', 'PESO', 3),
            (2, 'GR', 'Gramo', 'PESO', 3),
            (3, 'UN', 'Unidad', 'UNIDAD', 0),
            (4, 'CAJA', 'Caja', 'UNIDAD', 0),
          ])
        unidadDePrueba(
          id: i,
          codigo: codigo,
          nombre: nombre,
          tipo: tipo,
          decimales: decimales,
        ),
    ],
  );

  UnidadMedida? porId(int id) => unidades.where((u) => u.id == id).firstOrNull;

  /// Los mismos filtros que aplica `whereEstado` en la BD: sin estado se
  /// excluyen los ocultos, con estado se busca ese exacto.
  List<UnidadMedida> _filtradas({String? estado, String? q}) => unidades
      .where(
        (u) =>
            (estado == null
                ? u.estado != estadoEliminado
                : u.estado == estado) &&
            (q == null ||
                contiene(u.codigo, q) ||
                contiene(u.nombre, q) ||
                contiene(u.tipo, q)),
      )
      .toList();

  @override
  Future<List<UnidadMedida>> findUnidades({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async =>
      _filtradas(estado: estado, q: q).skip(offset).take(limit).toList();

  @override
  Future<int> countUnidades({String? estado, String? q}) async =>
      _filtradas(estado: estado, q: q).length;

  @override
  Future<UnidadMedida?> findUnidadById(int id) async => porId(id);

  @override
  Future<UnidadMedida?> findUnidadActivaByCodigo(String codigo) async =>
      unidades
          .where((u) => u.codigo == codigo && u.estado == 'ACTIVO')
          .firstOrNull;

  @override
  Future<UnidadMedida> insertUnidad({
    required String codigo,
    required String nombre,
    required String tipo,
    required int decimales,
    required String estado,
  }) async {
    if (unidades.any((u) => u.codigo == codigo)) {
      throw ConflictException('Registro duplicado: $codigo');
    }
    final id = unidades.isEmpty
        ? 1
        : unidades.map((u) => u.id).reduce((a, b) => a > b ? a : b) + 1;
    final creada = UnidadMedida(
      id: id,
      codigo: codigo,
      nombre: nombre,
      tipo: tipo,
      decimales: decimales,
      estado: estado,
      fechaCreacion: DateTime.utc(2026, 1, 1),
      fechaActualizacion: DateTime.utc(2026, 1, 1),
    );
    unidades.add(creada);
    return creada;
  }

  @override
  Future<UnidadMedida> updateUnidad(
    int id, {
    required String codigo,
    required String nombre,
    required String tipo,
    required int decimales,
    required String estado,
  }) async {
    final index = unidades.indexWhere((u) => u.id == id);
    if (index < 0) {
      throw const NotFoundException('La unidad no existe.');
    }
    final actualizada = UnidadMedida(
      id: id,
      codigo: codigo,
      nombre: nombre,
      tipo: tipo,
      decimales: decimales,
      estado: estado,
      fechaCreacion: unidades[index].fechaCreacion,
      fechaActualizacion: DateTime.utc(2026, 2, 2),
    );
    unidades[index] = actualizada;
    return actualizada;
  }

  @override
  Future<bool> deleteUnidad(int id) async {
    final index = unidades.indexWhere((u) => u.id == id);
    if (index < 0) return false;
    if (unidades[index].estado == estadoEliminado) return false;
    unidades[index] = UnidadMedida(
      id: id,
      codigo: unidades[index].codigo,
      nombre: unidades[index].nombre,
      tipo: unidades[index].tipo,
      decimales: unidades[index].decimales,
      estado: estadoEliminado,
      fechaCreacion: unidades[index].fechaCreacion,
      fechaActualizacion: DateTime.utc(2026, 2, 2),
    );
    return true;
  }
}

/// Marca de prueba con las fechas ya rellenas.
Marca marcaDePrueba({
  int id = 1,
  String nombre = 'Samsung',
  String estado = 'ACTIVO',
}) => Marca(
  id: id,
  nombre: nombre,
  estado: estado,
  fechaCreacion: DateTime.utc(2026, 1, 1),
  fechaActualizacion: DateTime.utc(2026, 1, 1),
);

/// Doble en memoria de [MarcaRepository]: las reglas de `Marcas` y de
/// `Productos.asegurarMarcaVigente` se prueban aquí sin tocar SQL.
final class FakeMarcaRepository implements MarcaRepository {
  FakeMarcaRepository({List<Marca>? marcas}) : marcas = [...?marcas];

  final List<Marca> marcas;

  /// Catálogo con una marca viva (la que usan las pruebas de producto).
  factory FakeMarcaRepository.semilla() => FakeMarcaRepository(
    marcas: [marcaDePrueba(id: 1, nombre: 'Samsung')],
  );

  /// Los mismos filtros que aplica `whereEstado` en la BD: sin estado se
  /// excluyen los ocultos, con estado se busca ese exacto.
  List<Marca> _filtradas({String? estado, String? q}) => marcas
      .where(
        (m) =>
            (estado == null ? m.estado != estadoEliminado : m.estado == estado) &&
            (q == null || contiene(m.nombre, q)),
      )
      .toList();

  @override
  Future<List<Marca>> findMarcas({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async => _filtradas(estado: estado, q: q).skip(offset).take(limit).toList();

  @override
  Future<int> countMarcas({String? estado, String? q}) async =>
      _filtradas(estado: estado, q: q).length;

  @override
  Future<Marca?> findMarcaById(int id) async =>
      marcas.where((Marca m) => m.id == id).firstOrNull;

  @override
  Future<Marca?> findMarcaVivaByNombre(String nombre) async => marcas
      .where(
        (Marca m) =>
            m.estado != estadoEliminado &&
            m.nombre.toLowerCase() == nombre.trim().toLowerCase(),
      )
      .firstOrNull;

  @override
  Future<Marca> insertMarca({
    required String nombre,
    required String estado,
  }) async {
    final id = marcas.isEmpty
        ? 1
        : marcas.map((m) => m.id).reduce((a, b) => a > b ? a : b) + 1;
    final creada = marcaDePrueba(id: id, nombre: nombre, estado: estado);
    marcas.add(creada);
    return creada;
  }

  @override
  Future<Marca> updateMarca(
    int id, {
    required String nombre,
    required String estado,
  }) async {
    final index = marcas.indexWhere((m) => m.id == id);
    if (index < 0) {
      throw const NotFoundException('La marca no existe.');
    }
    final actualizada = Marca(
      id: id,
      nombre: nombre,
      estado: estado,
      fechaCreacion: marcas[index].fechaCreacion,
      fechaActualizacion: DateTime.utc(2026, 2, 2),
    );
    marcas[index] = actualizada;
    return actualizada;
  }

  @override
  Future<bool> deleteMarca(int id) async {
    final index = marcas.indexWhere((m) => m.id == id);
    if (index < 0) return false;
    if (marcas[index].estado == estadoEliminado) return false;
    marcas[index] = Marca(
      id: id,
      nombre: marcas[index].nombre,
      estado: estadoEliminado,
      fechaCreacion: marcas[index].fechaCreacion,
      fechaActualizacion: DateTime.utc(2026, 2, 2),
    );
    return true;
  }
}
