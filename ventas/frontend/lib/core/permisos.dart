/// Permisos de la app (`módulo.accion`): catálogo compartido por la UI.
///
/// Los módulos coinciden con los ítems de `navItems` en
/// `core/widgets/sidebar.dart` y con la semilla `009_roles_permisos` de la
/// BD: si se añade un módulo nuevo, hay que añadirlo aquí, en `navItems` y
/// en la migración.
library;

import 'widgets/sesion_scope.dart';

export 'widgets/sesion_scope.dart' show DatosSesion;

abstract final class Modulos {
  static const String dashboard = 'dashboard';
  static const String productos = 'productos';
  static const String catalogo = 'catalogo';
  static const String clientes = 'clientes';
  static const String ventas = 'ventas';
  static const String cotizaciones = 'cotizaciones';
  static const String categorias = 'categorias';
  static const String proveedores = 'proveedores';
  static const String empleados = 'empleados';
  static const String usuarios = 'usuarios';
  static const String auditoria = 'auditoria';
  static const String unidades = 'unidades';
  static const String ajustes = 'ajustes';

  /// Pantalla «Reportes»: informe de ventas por rango con gráficos y
  /// exportación (14º módulo; migración `019_permiso_reportes`).
  static const String reportes = 'reportes';

  /// Todos, en el mismo orden que [navItems] del sidebar (14 módulos).
  static const List<String> todos = [
    dashboard,
    productos,
    catalogo,
    clientes,
    ventas,
    cotizaciones,
    categorias,
    proveedores,
    empleados,
    usuarios,
    auditoria,
    unidades,
    ajustes,
    reportes,
  ];
}

/// Acciones sobre un módulo (el orden es el de las columnas de la matriz de
/// permisos en la pestaña «Roles»).
abstract final class Acciones {
  static const String ver = 'ver';
  static const String crear = 'crear';
  static const String editar = 'editar';
  static const String eliminar = 'eliminar';

  static const List<String> todas = [ver, crear, editar, eliminar];

  /// Etiqueta para la UI (`ver` → «Ver»).
  static String etiqueta(String accion) => switch (accion) {
    ver => 'Ver',
    crear => 'Crear',
    editar => 'Editar',
    eliminar => 'Eliminar',
    _ => accion,
  };
}

/// El conjunto completo de permisos (14 módulos × 4 acciones), igual que la
/// semilla de la BD. Lo usa el rol ADMIN y los tests.
List<String> get todosPermisos => [
  for (final modulo in Modulos.todos)
    for (final accion in Acciones.todas) '$modulo.$accion',
];

/// Atajo de la UI: `sesion.puede(Modulos.ventas, Acciones.crear)`.
extension PermisosSesion on DatosSesion {
  bool puede(String modulo, [String accion = Acciones.ver]) =>
      usuario.puede(modulo, accion);
}
