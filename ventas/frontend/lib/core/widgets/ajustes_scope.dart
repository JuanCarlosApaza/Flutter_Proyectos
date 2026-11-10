import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Catálogo de los ajustes globales: sus claves y sus valores por defecto.
///
/// Es el único sitio donde se declara **qué** se puede personalizar: la misma
/// constante enlaza el desplegable de la vista «Ajustes», la fila que se
/// guarda en la tabla `Ajustes` y el punto del sistema donde se aplica.
///
/// La BD solo guarda lo que alguien cambia: si la fila no existe (primer
/// arranque, o se borró), manda el valor de [defectos], que es exactamente el
/// comportamiento anterior a existir los ajustes.
abstract final class Ajustes {
  /// Vendedor con el que arrancan las órdenes (`''` = la cuenta conectada).
  static const String vendedorPorDefecto = 'vendedorPorDefecto';

  /// Tipo de pago con el que arrancan carrito y «Nueva Orden».
  static const String tipoPagoPorDefecto = 'tipoPagoPorDefecto';

  /// Cliente con el que arrancan las órdenes (`''` = ocasional).
  static const String clientePorDefecto = 'clientePorDefecto';

  /// Orden inicial de la rejilla del catálogo.
  static const String ordenCatalogo = 'ordenCatalogo';

  /// Módulo que se abre al entrar (`''` = Dashboard).
  static const String paginaInicial = 'paginaInicial';

  /// Filas por página de las tablas (`PaginationMixin`).
  static const String porPagina = 'porPagina';

  /// Stock por debajo del cual el dashboard avisa que el producto está bajo.
  static const String stockMinimo = 'stockMinimo';

  /// Días de antelación con los que el dashboard avisa del vencimiento.
  static const String diasVencimiento = 'diasVencimiento';

  /// Minutos entre respaldos automáticos de la BD (`0` = solo manual).
  ///
  /// El backend lo lee para programar `pg_dump`: `1440` = cada día,
  /// `10080` = cada semana, `43200` = cada mes.
  static const String respaldoIntervalo = 'respaldoIntervalo';

  /// Roles que pueden usar el asistente IA, separados por comas
  /// (`ADMIN,CAJERO`); vacía = todos los roles.
  ///
  /// El backend lo aplica en `POST /api/v1/chat` (403 `ia_no_permitido`) y
  /// lo devuelve en `GET /chat/estado` como `permitido` para que la burbuja
  /// se oculte en los roles excluidos.
  static const String iaRoles = 'iaRoles';

  /// Nombre del negocio que aparece en la marca de la app y en los PDFs
  /// (recibos y hojas de cotización). Se cambia desde la pantalla Ajustes.
  static const String nombreTienda = 'nombreTienda';

  /// Contenido que codifica el QR mostrado al cobrar con QR (link o dato de
  /// la billetera). Vacío = no se muestra ningún QR.
  static const String qrPago = 'qrPago';

  /// ¿Se muestra la burbuja flotante del asistente? (`'1'` visible,
  /// `'0'` oculta — en celular ocupa bastante pantalla).
  static const String burbujaIA = 'burbujaIA';

  // --- Valor por defecto de los desplegables de los formularios -----------
  //
  // Convención `defecto.<entidad>.<campo>`: la clave se deriva de la entidad
  // del formulario y del `clave` del campo, así que [claveDefecto] y el backend
  // (que valida el patrón, no una lista cerrada) siempre coinciden.

  /// Clave de valor por defecto del campo [campo] del formulario de [entidad].
  static String claveDefecto(String entidad, String campo) =>
      'defecto.$entidad.$campo';

  /// Slug de una entidad para armar la clave (`'categoría'` → `'categoria'`).
  ///
  /// Las páginas usan nombres con tilde en `entidad:`; la clave no puede
  /// llevarla porque el patrón del backend solo admite `[a-z]`.
  static String slugEntidad(String entidad) => entidad
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .toLowerCase();

  /// Las claves de valor por defecto de desplegable, en orden de aparición.
  ///
  /// Se derivan de [defectos] en vez de vivir en una lista aparte: así no hay
  /// dos sitios que se puedan desincronizar.
  static List<String> get clavesDefecto => [
    for (final clave in defectos.keys)
      if (clave.startsWith('defecto.')) clave,
  ];

  /// Valor por defecto de cada ajuste.
  ///
  /// Las claves `defecto.<entidad>.<campo>` son el valor por defecto de cada
  /// desplegable al dar de alta: `''` = «— Sin valor por defecto —», así que el
  /// campo sale vacío y, si es obligatorio, la validación del formulario pide
  /// elegirlo. Las dos excepciones son las fichas de persona: su alta nacía
  /// siempre `ACTIVO` antes de existir este ajuste, y hay que conservarlo para
  /// que entrar en Ajustes y guardar sin tocar nada no cambie nada (la regla
  /// de la propia pantalla).
  static const Map<String, String> defectos = {
    vendedorPorDefecto: '',
    tipoPagoPorDefecto: 'EFECTIVO',
    clientePorDefecto: '',
    ordenCatalogo: 'destacados',
    paginaInicial: '',
    porPagina: '10',
    stockMinimo: '5',
    diasVencimiento: '90',
    respaldoIntervalo: '1440',
    iaRoles: '',
    nombreTienda: 'Mi Tienda',
    qrPago: '',
    burbujaIA: '1',
    // `defecto.<entidad>.<campo>`: el valor por defecto de cada desplegable.
    // Dart no admite `for` en un mapa const, así que se listan a mano.
    'defecto.producto.estado': '',
    'defecto.producto.categoriaId': '',
    'defecto.producto.presentacionId': '',
    'defecto.producto.proveedorId': '',
    'defecto.usuario.estado': '',
    'defecto.usuario.rolId': '',
    'defecto.usuario.empleadoId': '',
    'defecto.categoria.estado': '',
    'defecto.presentacion.estado': '',
    'defecto.proveedor.estado': '',
    'defecto.cliente.estado': 'ACTIVO',
    'defecto.cliente.genero': '',
    'defecto.empleado.estado': 'ACTIVO',
  };
}

/// Lectura de los ajustes: lo guardado en la BD o, si no, su valor por defecto.
///
/// Se crea en [AjustesScope.de], así que nunca es `null`: una pantalla sin
/// scope (aislada en un test) ve el sistema con su comportamiento de fábrica.
final class AjustesValores {
  const AjustesValores(this.guardados);

  /// `clave` → `valor` tal como están en la tabla `Ajustes`.
  final Map<String, String> guardados;

  /// Valor del ajuste [clave]: lo guardado o, en su defecto, el de fábrica.
  String valor(String clave) =>
      guardados[clave] ?? Ajustes.defectos[clave] ?? '';

  /// Igual que [valor] pero como número; si lo guardado no es entero, cae al
  /// valor de fábrica (un ajuste corrupto no puede dejar una tabla sin filas).
  int numero(String clave, {int defecto = 0}) {
    final propio = int.tryParse(guardados[clave] ?? '');
    if (propio != null) return propio;
    return int.tryParse(Ajustes.defectos[clave] ?? '') ?? defecto;
  }
}

/// Los ajustes cargados, accesibles desde cualquier `context`.
///
/// Va en la **raíz de la app, por encima de `MaterialApp`** (ver `app.dart`):
/// las hojas modales se montan en el `Navigator` y quedan fuera del
/// `SesionScope` (que envuelve a `MainScreen` dentro de `home:`), y el
/// carrito y «Nueva Orden» necesitan leerlos ahí dentro.
final class AjustesScope extends InheritedWidget {
  const AjustesScope({super.key, required this.valores, required super.child});

  /// `clave` → `valor` guardados en la BD (solo los que alguien cambió).
  final Map<String, String> valores;

  /// Ajustes visibles desde [context]; sin scope, los de fábrica.
  static AjustesValores de(BuildContext context) => AjustesValores(
    context.dependOnInheritedWidgetOfExactType<AjustesScope>()?.valores ??
        const {},
  );

  @override
  bool updateShouldNotify(AjustesScope anterior) =>
      !mapEquals(valores, anterior.valores);
}
