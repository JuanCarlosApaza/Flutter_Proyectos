import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/estado_chip.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../domain/entities/recurso.dart';
import 'imagen_recurso.dart';

/// Definición de una columna de tabla (y de su par `etiqueta: valor` en
/// mobile). La primera columna es la que se muestra como título de la
/// tarjeta en pantallas pequeñas.
final class ColumnaTabla {
  const ColumnaTabla({
    required this.clave,
    required this.etiqueta,
    this.flex = 2,
    this.formato,
    this.chip = false,
    this.miniatura = false,
  });

  /// Campo del JSON que representa.
  final String clave;

  /// Encabezado de columna / etiqueta de la tarjeta mobile.
  final String etiqueta;

  /// Peso de la columna (`Expanded(flex: n)`), nunca ancho fijo.
  final int flex;

  /// Formateo propio (p. ej. `Bs 3.20` o `categoriaId` → nombre).
  final String Function(Recurso)? formato;

  /// Si es `true` se pinta como [EstadoChip] en vez de texto plano.
  final bool chip;

  /// Muestra la miniatura del campo `imagen` del recurso a la izquierda del
  /// valor (solo tiene sentido en la primera columna).
  final bool miniatura;

  String valor(Recurso recurso) =>
      formato?.call(recurso) ?? recurso.texto(clave);
}

/// Tabla responsive: `>= 700` tabla completa, `< 700` tarjetas apiladas.
class RecursoTabla extends StatelessWidget {
  const RecursoTabla({
    super.key,
    required this.columnas,
    required this.items,
    this.onEditar,
    this.onEliminar,
    this.onVer,
    this.accionesExtras,
    this.anchoAcciones,
  });

  final List<ColumnaTabla> columnas;
  final List<Recurso> items;

  /// Abre la ficha editable del registro (botón ✏). Si es `null` (p. ej. la
  /// cuenta no tiene permiso `editar`) el botón no se muestra.
  final ValueChanged<Recurso>? onEditar;

  /// Borra el registro (botón 🗑). Si es `null` no se muestra.
  final ValueChanged<Recurso>? onEliminar;

  /// Abre la ficha de solo lectura del registro (botón 👁). Si es `null`
  /// el botón no se muestra.
  final ValueChanged<Recurso>? onVer;

  /// Botones adicionales a la derecha (p. ej. cambiar estado).
  final List<Widget> Function(Recurso)? accionesExtras;

  /// Ancho reservado a la columna de acciones. Si es `null` se calcula
  /// según los botones visibles (76 = 2 botones, 110 = 3 con el ojo).
  final double? anchoAcciones;

  /// Espacio ocupado por los botones de la fila.
  double get _anchoAcciones {
    if (anchoAcciones != null) return anchoAcciones!;
    final botones =
        (onVer == null ? 0 : 1) +
        (onEditar == null ? 0 : 1) +
        (onEliminar == null ? 0 : 1);
    if (botones == 0) return 0;
    // 34 px por icono + 8 px de holgura (76 para 2, 110 para 3).
    return 34.0 * botones + 8;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) return _tarjetasMovil();
        return _tablaEscritorio();
      },
    );
  }

  /// Botón de detalle (👁) o `null` si el módulo no lo pide.
  List<Widget>? _botonVer(Recurso item) {
    final ver = onVer;
    if (ver == null) return null;
    return [
      botonAccion(
        icono: Icons.visibility_outlined,
        color: AppColors.textSecondary,
        tooltip: 'Ver detalle',
        onTap: () => ver(item),
      ),
      const SizedBox(width: 4),
    ];
  }

  /// Botón de edición (✏) o `null` si el rol no tiene `editar`.
  List<Widget>? _botonEditar(Recurso item) {
    final editar = onEditar;
    if (editar == null) return null;
    return [
      botonAccion(
        icono: Icons.edit_outlined,
        color: AppColors.brandGreen,
        tooltip: 'Editar',
        onTap: () => editar(item),
      ),
      const SizedBox(width: 4),
    ];
  }

  /// Botón de borrado (🗑) o `null` si el rol no tiene `eliminar`.
  List<Widget>? _botonEliminar(Recurso item) {
    final eliminar = onEliminar;
    if (eliminar == null) return null;
    return [
      botonAccion(
        icono: Icons.delete_outline,
        color: AppColors.negativeRed,
        tooltip: 'Eliminar',
        onTap: () => eliminar(item),
      ),
    ];
  }

  // --- Versión desktop / tablet (>= 700) -----------------------------------

  Widget _tablaEscritorio() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
            ),
            child: Row(
              children: [
                for (final columna in columnas)
                  Expanded(
                    flex: columna.flex,
                    child: Text(
                      columna.etiqueta,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                SizedBox(width: _anchoAcciones),
              ],
            ),
          ),
          for (final item in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
              ),
              child: Row(
                children: [
                  for (final columna in columnas)
                    Expanded(flex: columna.flex, child: _celda(columna, item)),
                  SizedBox(
                    width: _anchoAcciones,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ...?accionesExtras?.call(item),
                        ...?_botonVer(item),
                        ...?_botonEditar(item),
                        ...?_botonEliminar(item),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _celda(ColumnaTabla columna, Recurso item) {
    if (columna.chip) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: EstadoChip(valor: columna.valor(item)),
        ),
      );
    }

    // Miniatura del recurso (campo `imagen`) + valor en la misma celda.
    if (columna.miniatura) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          children: [
            ImagenRecurso(
              ruta: item.texto('imagen', vacio: ''),
              tamano: 28,
              radio: 6,
            ),
            const SizedBox(width: 10),
            Expanded(child: _texto(columna, item)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _texto(columna, item),
    );
  }

  Widget _texto(ColumnaTabla columna, Recurso item) {
    return Text(
      columna.valor(item),
      style: TextStyle(
        color: columna == columnas.first
            ? AppColors.textPrimary
            : AppColors.textSecondary,
        fontSize: columna == columnas.first ? 14.0 : 13.0,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  // --- Versión mobile (< 700) ----------------------------------------------

  Widget _tarjetasMovil() {
    final principal = columnas.first;
    return Column(
      children: [
        for (final item in items)
          MobileCardContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (principal.miniatura) ...[
                            ImagenRecurso(
                              ruta: item.texto('imagen', vacio: ''),
                              tamano: 32,
                              radio: 8,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              principal.valor(item),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...?accionesExtras?.call(item),
                        ...?_botonVer(item),
                        ...?_botonEditar(item),
                        ...?_botonEliminar(item),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final columna in columnas.skip(1))
                  if (columna.chip)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Text(
                            '${columna.etiqueta}: ',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          EstadoChip(valor: columna.valor(item)),
                        ],
                      ),
                    )
                  else
                    _filaInfo(columna.etiqueta, columna.valor(item)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _filaInfo(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$etiqueta: ',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón de acción compacto de fila/tabla (36x36).
Widget botonAccion({
  required IconData icono,
  required Color color,
  required VoidCallback onTap,
  String? tooltip,
}) {
  Widget boton = IconButton(
    icon: Icon(icono, size: 18),
    color: color,
    style: IconButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(34, 34),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: onTap,
  );
  if (tooltip != null) boton = Tooltip(message: tooltip, child: boton);
  return boton;
}

/// Nombre legible de un recurso referenciado por id (`categoriaId`...).
String nombreDe(List<Recurso> items, Object? id, {String vacio = '—'}) {
  if (id == null) return vacio;
  for (final item in items) {
    if ('${item.id}' == '$id') return nombreCompletoDe(item);
  }
  return vacio;
}

/// Nombre visible de una persona: «Nombre Apellido».
///
/// Clientes y empleados llevan `apellido` aparte (migración
/// `011_apellido_personas`): si existe se añade al nombre y, si no —los
/// registros antiguos—, se queda el nombre tal cual. El resto de recursos
/// (productos, categorías…) no tienen ese campo y su etiqueta no cambia.
String nombreCompletoDe(Recurso item) {
  final nombre = item.texto('nombre');
  final apellido = item.texto('apellido', vacio: '');
  return apellido.isEmpty ? nombre : '$nombre $apellido';
}
