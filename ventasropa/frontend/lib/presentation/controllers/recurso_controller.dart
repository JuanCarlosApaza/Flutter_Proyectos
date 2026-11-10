import 'package:flutter/foundation.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/recurso.dart';
import '../../domain/usecases/crud.dart';
import 'load_state.dart';

/// Controlador CRUD genérico de un recurso de la API.
///
/// Expone dos visiones del listado:
///
/// * **lote completo** ([items], máx. 200): combos de formularios, dashboard,
///   catálogo, roles y ajustes — todo lo que necesito el conjunto en cliente;
/// * **vista paginada en servidor** ([paginaItems] + [total]): la que ven las
///   tablas, con `limit`/`offset`/`q` reales, así ninguna tabla se queda
///   truncada en 200 registros y el buscador encuentra lo que hay en la BD.
///
/// [recargar()] refresca las dos visiones que estén en uso. Las operaciones
/// de escritura (crear/actualizar/eliminar) también exponen los 4 estados de
/// la guía (`loading` / `error` / `vacío` / `datos`).
class RecursoController extends ChangeNotifier {
  RecursoController(this.crud, this.recurso);

  /// Casos de uso del CRUD (capa domain).
  final Crud crud;

  /// Nombre del recurso en la API, p. ej. `clientes`.
  final String recurso;

  LoadState state = LoadState.initial;

  /// Lote completo (máx. 200 registros) para combos/dashboard/catálogo.
  List<Recurso> items = const [];
  String? errorMessage;

  // --- Vista paginada en servidor (tablas) -----------------------------------

  /// Página actual devuelta por el servidor ([total] de filas real).
  List<Recurso> paginaItems = const [];

  /// Total de filas del listado con [filtroEstado], [busqueda] y
  /// [filtrosListado] aplicados (COUNT real del servidor).
  int total = 0;

  /// Índice de página (0-based) de la vista paginada.
  int pagina = 0;

  /// Filas por página pedidas al servidor (viene del ajuste «Filas por
  /// página» que decide la tabla).
  int tamano = 10;

  bool _paginaCargada = false;
  bool _paginaCargando = false;
  bool _completoCargado = false;

  /// ¿La vista paginada terminó de cargarse al menos una vez?
  bool get paginaCargada => _paginaCargada;

  /// Hay una petición de página en curso (independiente de [state], que
  /// comparten también los cargados completos).
  bool get paginaCargando => _paginaCargando;

  /// ¿Se ha usado la vista de lote completo?
  bool get completoCargado => _completoCargado;

  /// Filtro de estado de la vista paginada (`null` = chip "Todos").
  String? filtroEstado;

  /// Búsqueda libre server-side (`?q=`) de la vista paginada.
  String? busqueda;

  /// Parámetros de query extra del listado (`usuario`, `desde`, `hasta`…:
  /// los usa la auditoría). `recargar()` los conserva; `reiniciar()` limpia.
  Map<String, String>? filtrosListado;

  bool _activo = true;

  bool get cargando => state == LoadState.initial || state == LoadState.loading;

  bool get vacio => state == LoadState.loaded && items.isEmpty;

  /// Carga una página del servidor (offset real + COUNT con los filtros).
  ///
  /// Usa y conserva [filtroEstado], [busqueda] y [filtrosListado]; el
  /// resultado va a [paginaItems]/[total] sin tocar el lote [items].
  Future<void> cargarPagina({int? numero, int? porPagina}) async {
    if (numero != null) pagina = numero;
    if (porPagina != null) tamano = porPagina;
    _paginaCargada = true;
    // Recula página a página si el servidor devuelve una vacía (p. ej.
    // borraron el último registro de la última página).
    while (true) {
      _paginaCargando = true;
      state = LoadState.loading;
      errorMessage = null;
      _emit();
      final ListadoRecurso listado;
      try {
        listado = await crud.listar(
          recurso,
          limit: tamano,
          offset: pagina * tamano,
          estado: filtroEstado,
          q: busqueda,
          filtros: filtrosListado,
        );
      } on Failure catch (failure) {
        errorMessage = failure.message;
        state = LoadState.error;
        break;
      } catch (_) {
        errorMessage = 'Error inesperado al cargar los datos';
        state = LoadState.error;
        break;
      }
      paginaItems = listado.items;
      total = listado.total;
      if (paginaItems.isEmpty && pagina > 0) {
        pagina--;
        continue;
      }
      state = LoadState.loaded;
      break;
    }
    _paginaCargando = false;
    _emit();
  }

  /// Carga el lote completo en [items] (máx. 200 registros): combos,
  /// dashboard, catálogo y roles. No toca la vista paginada ni sus filtros.
  Future<void> cargar() async {
    _completoCargado = true;
    state = LoadState.loading;
    errorMessage = null;
    _emit();

    try {
      final listado = await crud.listar(recurso, filtros: filtrosListado);
      items = listado.items;
      state = LoadState.loaded;
    } on Failure catch (failure) {
      errorMessage = failure.message;
      state = LoadState.error;
    } catch (_) {
      errorMessage = 'Error inesperado al cargar los datos';
      state = LoadState.error;
    }
    _emit();
  }

  /// Recarga lo que esté en uso: la página de las tablas y/o el lote
  /// completo (combos, dashboard...), conservando filtros y búsqueda.
  ///
  /// Si todavía no se había cargado nada (p. ej. `respaldar()` sin haber
  /// listado antes), refresca el lote completo, como siempre.
  Future<void> recargar() async {
    if (!_paginaCargada && !_completoCargado) {
      await cargar();
      return;
    }
    if (_paginaCargada) await cargarPagina();
    if (_completoCargado) await cargar();
  }

  /// Vuelve al estado inicial: el próximo [cargar]/[cargarPagina] vuelve a
  /// pedir a la API.
  ///
  /// Se usa al cerrar sesión, para que si entra otra cuenta no se cuelen los
  /// datos (listados, ajustes) del usuario anterior.
  void reiniciar() {
    state = LoadState.initial;
    items = const [];
    paginaItems = const [];
    total = 0;
    pagina = 0;
    errorMessage = null;
    filtroEstado = null;
    busqueda = null;
    filtrosListado = null;
    _paginaCargada = false;
    _paginaCargando = false;
    _completoCargado = false;
    _emit();
  }

  /// POST y recarga. Lanza [Failure] si la API rechaza la operación.
  Future<Recurso> crear(Map<String, Object?> body) async {
    final creado = await crud.crear(recurso, body);
    await recargar();
    return creado;
  }

  /// PUT y recarga.
  ///
  /// Si el backend rechaza por guarda optimista
  /// (`409 producto_desactualizado`), se recarga la lista **antes** de
  /// relanzar el fallo: la alerta del servidor pide recargar y el listado
  /// ya queda con los datos frescos para el reintento.
  Future<Recurso> actualizar(int id, Map<String, Object?> body) async {
    try {
      final editado = await crud.editar('$recurso/$id', body);
      await recargar();
      return editado;
    } on ServerFailure catch (error) {
      if (error.code == 'producto_desactualizado') await recargar();
      rethrow;
    }
  }

  /// DELETE y recarga.
  Future<void> eliminar(int id) async {
    await crud.eliminar('$recurso/$id');
    await recargar();
  }

  void _emit() {
    if (_activo) notifyListeners();
  }

  @override
  void dispose() {
    _activo = false;
    super.dispose();
  }
}

// --- Controladores concretos (uno por recurso) -----------------------------

final class ProductosController extends RecursoController {
  ProductosController(Crud crud) : super(crud, 'productos');
}

final class ClientesController extends RecursoController {
  ClientesController(Crud crud) : super(crud, 'clientes');
}

final class ProveedoresController extends RecursoController {
  ProveedoresController(Crud crud) : super(crud, 'proveedores');
}

final class EmpleadosController extends RecursoController {
  EmpleadosController(Crud crud) : super(crud, 'empleados');
}

final class UsuariosController extends RecursoController {
  UsuariosController(Crud crud) : super(crud, 'usuarios');
}

/// Roles y permisos (RBAC) (`GET/POST/PUT/DELETE /roles`).
///
/// Alarga el CRUD genérico con los permisos (`modulo.accion`) de cada rol.
/// La API protege el rol ADMIN (`409 rol_protegido`): la UI lo muestra en
/// solo lectura con [esSoloLectura].
final class RolesController extends RecursoController {
  RolesController(Crud crud) : super(crud, 'roles');

  /// Permisos del rol con ese id (vacío si no está en el listado).
  List<String> permisosDe(int id) {
    for (final rol in items) {
      if (rol.id == id) return permisosDeRol(rol);
    }
    return const [];
  }

  /// El rol con ese id (`null` si no está cargado).
  Recurso? rolPorId(int id) {
    for (final rol in items) {
      if (rol.id == id) return rol;
    }
    return null;
  }

  /// El único rol que la API no deja modificar (acceso total siempre).
  bool esSoloLectura(Recurso rol) => rol.texto('nombre') == 'ADMIN';

  /// ¿Es un rol de la semilla (no se puede borrar)?
  bool esSistema(Recurso rol) => rol['esSistema'] == true;

  /// Reemplaza el conjunto completo de permisos del rol.
  Future<void> guardarPermisos(int id, Set<String> permisos) async {
    await crud.editar('roles/$id', {
      'permisos': [...permisos],
    });
    await recargar();
  }
}

/// Permisos (`modulo.accion`) de un rol del listado.
List<String> permisosDeRol(Recurso rol) {
  final crudo = rol.datos['permisos'];
  if (crudo is! List) return const [];
  return [for (final permiso in crudo) permiso.toString()];
}

final class CategoriasController extends RecursoController {
  CategoriasController(Crud crud) : super(crud, 'categorias');
}

/// Tallas de ropa (`GET/POST/PUT/DELETE /tallas`): catálogo compartido de
/// las prendas (S, M, XL, numéricas, «Única»...).
final class TallasController extends RecursoController {
  TallasController(Crud crud) : super(crud, 'tallas');
}

/// Colores de ropa (`GET/POST/PUT/DELETE /colores`).
final class ColoresController extends RecursoController {
  ColoresController(Crud crud) : super(crud, 'colores');
}

/// Marcas de ropa (`GET/POST/PUT/DELETE /marcas`): catálogo opcional de
/// productos (una prenda puede no tener marca).
final class MarcasController extends RecursoController {
  MarcasController(Crud crud) : super(crud, 'marcas');
}

/// Variantes (talla + color) de una prenda: el **stock real**.
///
/// A diferencia del resto de recursos, no tienen listado propio: cuelgan de
/// su producto (`GET/POST /productos/{id}/variantes`) y se editan/borran en
/// raíz (`PUT/DELETE /variantes/{id}`).
final class VariantesController extends ChangeNotifier {
  VariantesController(this.crud);

  final Crud crud;

  /// Variantes de la prenda cargada en [cargar].
  List<Recurso> variantes = const [];
  String? errorMessage;
  bool cargando = false;

  Future<void> cargar(int productoId) async {
    cargando = true;
    errorMessage = null;
    notifyListeners();
    try {
      final listado = await crud.listar('productos/$productoId/variantes');
      variantes = listado.items;
    } on Failure catch (failure) {
      errorMessage = failure.message;
    } catch (_) {
      errorMessage = 'Error inesperado al cargar las variantes';
    }
    cargando = false;
    notifyListeners();
  }

  /// Crea una variante y recarga las de esa prenda.
  Future<void> crear(int productoId, Map<String, Object?> body) async {
    await crud.crear('productos/$productoId/variantes', body);
    await cargar(productoId);
  }

  /// Actualiza stock/talla/color de la variante y recarga la prenda.
  Future<void> actualizar(
    int productoId,
    int varianteId,
    Map<String, Object?> body,
  ) async {
    await crud.editar('variantes/$varianteId', body);
    await cargar(productoId);
  }

  Future<void> eliminar(int productoId, int varianteId) async {
    await crud.eliminar('variantes/$varianteId');
    await cargar(productoId);
  }
}

/// Órdenes de venta: además del CRUD permite cambiar el estado
/// (`PUT /ordenes/{id}/estado`) aplicando la regla de stock del backend.
final class OrdenesController extends RecursoController {
  OrdenesController(Crud crud) : super(crud, 'ordenes');

  Future<void> cambiarEstado(int id, String estado) async {
    await crud.editar('ordenes/$id/estado', {'estado': estado});
    await recargar();
  }

  /// Líneas de una orden (`GET /ordenes/{id}` → cabecera + `detalles`).
  ///
  /// Se piden aquí y no en el listado: la tabla se queda con la cabecera y
  /// las líneas solo viajan al abrir la ficha de detalle, para no cargar los
  /// productos de todas las órdenes de golpe. La línea no tiene `id` propio
  /// (su clave natural es la variante), por eso el [Recurso] se construye a
  /// mano con `varianteId`.
  Future<List<Recurso>> detalles(int ordenId) async {
    final orden = await crud.obtener('ordenes/$ordenId');
    final lineas = orden['detalles'];
    if (lineas is! List) return const [];
    return [
      for (final linea in lineas)
        if (linea is Map)
          Recurso(
            id: (linea['varianteId'] as num?)?.toInt() ?? 0,
            datos: Map<String, Object?>.from(linea),
          ),
    ];
  }
}

/// Facturas: emisión (`POST /facturas`) y anulación por cambio de estado.
///
/// La factura no pide importes: copia subtotal, rebaja e IVA que la orden
/// ya cobró.
final class FacturasController extends RecursoController {
  FacturasController(Crud crud) : super(crud, 'facturas');

  Future<void> cambiarEstado(int id, String estado) async {
    await crud.editar('facturas/$id/estado', {'estado': estado});
    await recargar();
  }

  Future<void> emitir({
    required int ordenId,
    int? empleadoId,
    int? clienteId,
  }) async {
    final body = <String, Object?>{'ordenId': ordenId};
    if (empleadoId != null) body['empleadoId'] = empleadoId;
    if (clienteId != null) body['clienteId'] = clienteId;
    await crud.crear('facturas', body);
    await recargar();
  }
}

/// Cotizaciones: CRUD + cambio de estado
/// (`PUT /cotizaciones/{id}/estado`, `VIGENTE` → `ACEPTADA`/`RECHAZADA`).
final class CotizacionesController extends RecursoController {
  CotizacionesController(Crud crud) : super(crud, 'cotizaciones');

  Future<void> cambiarEstado(int id, String estado) async {
    await crud.editar('cotizaciones/$id/estado', {'estado': estado});
    await recargar();
  }

  /// Líneas de la cotización (`GET /cotizaciones/{id}` → cabecera +
  /// `detalles`), con el mismo patrón que [OrdenesController.detalles]: las
  /// líneas solo viajan al abrir la ficha, no en el listado; la clave de la
  /// línea es su variante (talla + color).
  Future<List<Recurso>> detalles(int cotizacionId) async {
    final cotizacion = await crud.obtener('cotizaciones/$cotizacionId');
    final lineas = cotizacion['detalles'];
    if (lineas is! List) return const [];
    return [
      for (final linea in lineas)
        if (linea is Map)
          Recurso(
            id: (linea['varianteId'] as num?)?.toInt() ?? 0,
            datos: Map<String, Object?>.from(linea),
          ),
    ];
  }
}

/// Ajustes globales del sistema (`GET`/`PUT /ajustes`).
///
/// Es la única fuente de la vista «Ajustes»: aquí se guardan los valores que
/// alguien elige para personalizar el comportamiento de la app (vendedor,
/// tipo de pago, cliente, orden del catálogo, página inicial, filas por
/// página y avisos del dashboard).
///
/// El resto de la app **no** consulta este controlador: lee `AjustesScope`,
/// que se alimenta de él en la raíz y devuelve los valores por defecto
/// mientras no haya nada guardado.
final class AjustesController extends RecursoController {
  AjustesController(Crud crud) : super(crud, 'ajustes');

  /// `clave` → `valor` de los ajustes guardados en la BD.
  Map<String, String> get valores => {
    for (final item in items)
      if (item.texto('clave', vacio: '').isNotEmpty)
        item.texto('clave'): item.texto('valor', vacio: ''),
  };

  /// Guarda un lote (`PUT /ajustes` con `{"valores": {...}}`) y recarga.
  ///
  /// La escritura la rechaza la API con `403` si la cuenta no es `ADMIN`.
  Future<void> guardar(Map<String, String> nuevos) async {
    await crud.editar(recurso, {'valores': nuevos});
    await recargar();
  }
}

/// Auditoría de cambios (`GET /auditoria` + purgas).
///
/// La búsqueda por usuario y rango de fechas es **del lado del servidor**:
/// [filtrosListado] viaja como query params del listado genérico.
final class AuditoriaController extends RecursoController {
  AuditoriaController(Crud crud) : super(crud, 'auditoria');

  /// Busca en la BD por usuario (parcial), rango de fechas (inclusive),
  /// entidad y acción (igualdad exacta) — todo server-side.
  ///
  /// Resetea a la página 0 y recarga la vista paginada de la tabla.
  Future<void> buscar({
    String? usuario,
    DateTime? desde,
    DateTime? hasta,
    String? entidad,
    String? accion,
  }) {
    filtrosListado = {
      if (usuario != null && usuario.trim().isNotEmpty)
        'usuario': usuario.trim(),
      if (desde != null) 'desde': fechaCorta(desde),
      if (hasta != null) 'hasta': fechaCorta(hasta),
      if (entidad != null && entidad.isNotEmpty) 'entidad': entidad,
      if (accion != null && accion.isNotEmpty) 'accion': accion,
    };
    if (filtrosListado!.isEmpty) filtrosListado = null;
    pagina = 0;
    return cargarPagina();
  }

  /// Quita los filtros y recarga la vista paginada sin ellos.
  Future<void> limpiarFiltros() {
    filtrosListado = null;
    pagina = 0;
    return cargarPagina();
  }

  /// Borra los eventos anteriores a [fecha] (día incluido).
  Future<void> limpiarAntesDe(DateTime fecha) async {
    await crud.eliminar('auditoria/antes-de/${fechaCorta(fecha)}');
    await recargar();
  }

  /// Vacía la tabla.
  Future<void> vaciar() async {
    await crud.eliminar('auditoria/todo');
    await recargar();
  }

  /// `yyyy-MM-dd` local (formato que espera la API).
  static String fechaCorta(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';
}
