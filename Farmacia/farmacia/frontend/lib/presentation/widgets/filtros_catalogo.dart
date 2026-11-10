import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/entities/recurso.dart';

/// Claves de la sección "Disponibilidad" (para poder compararlas en un
/// `Set<String>` sin depender del texto visible).
const String disponibilidadConStock = 'CON_STOCK';
const String disponibilidadAgotado = 'AGOTADO';

/// Panel de filtros del catálogo: secciones colapsables con casillas de
/// verificación (disponibilidad, precio y categorías).
///
/// Es un widget **sin estado**: el estado vive en la página, así el mismo
/// panel se puede pintar en el lateral de escritorio o dentro de la hoja
/// modal de móvil sin duplicar valores. Solo la apertura/cierre de cada
/// sección es local.
class FiltrosCatalogo extends StatelessWidget {
  const FiltrosCatalogo({
    super.key,
    required this.categorias,
    required this.categoriasSel,
    required this.onToggleCategoria,
    required this.disponibilidad,
    required this.onToggleDisponibilidad,
    required this.conStock,
    required this.agotados,
    required this.controladorMin,
    required this.controladorMax,
    required this.rango,
    required this.limites,
    required this.rangoInvalido,
    required this.onRango,
    required this.onPrecioMin,
    required this.onPrecioMax,
    required this.onLimpiar,
  });

  /// Todas las categorías del catálogo (índice completo).
  final List<Recurso> categorias;

  /// Ids de las categorías marcadas (vacío = sin filtro).
  final Set<int> categoriasSel;
  final ValueChanged<int> onToggleCategoria;

  /// Claves marcadas de [disponibilidad] (`CON_STOCK` / `AGOTADO`).
  final Set<String> disponibilidad;
  final ValueChanged<String> onToggleDisponibilidad;

  /// Productos con stock y agotados, para mostrar el conteo al lado.
  final int conStock;
  final int agotados;

  /// Texto escrito en los campos "Desde" / "Hasta" (lo posee la página).
  final TextEditingController controladorMin;
  final TextEditingController controladorMax;

  /// Selección actual y límites del catálogo para el `RangeSlider`.
  final RangeValues rango;
  final RangeValues limites;

  /// `true` cuando el mínimo tecleado supera al máximo.
  final bool rangoInvalido;

  final ValueChanged<RangeValues> onRango;

  /// Texto tecleado en cada campo (`null`/vacío = sin límite).
  final ValueChanged<String> onPrecioMin;
  final ValueChanged<String> onPrecioMax;

  /// Limpia todos los filtros (búsqueda no incluida).
  final VoidCallback onLimpiar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Filtros',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            TextButton(
              onPressed: onLimpiar,
              child: const Text(
                'Limpiar',
                style: TextStyle(fontSize: 12, color: AppColors.brandGreen),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _Seccion(
          titulo: 'Disponibilidad',
          child: Column(
            children: [
              _opcion(
                etiqueta: 'En existencia',
                conteo: conStock,
                seleccionado: disponibilidad.contains(disponibilidadConStock),
                onChanged: (_) =>
                    onToggleDisponibilidad(disponibilidadConStock),
              ),
              _opcion(
                etiqueta: 'Agotados',
                conteo: agotados,
                seleccionado: disponibilidad.contains(disponibilidadAgotado),
                onChanged: (_) => onToggleDisponibilidad(disponibilidadAgotado),
              ),
            ],
          ),
        ),
        const _Separador(),
        _Seccion(titulo: 'Precio', child: _precio()),
        const _Separador(),
        _Seccion(
          titulo: 'Categorías',
          child: categorias.isEmpty
              ? const Text(
                  'Sin categorías registradas',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                )
              : Column(
                  children: [
                    for (final categoria in categorias)
                      _opcion(
                        etiqueta: categoria.texto(
                          'nombre',
                          vacio: 'Sin nombre',
                        ),
                        seleccionado: categoriasSel.contains(categoria.id),
                        onChanged: (_) => onToggleCategoria(categoria.id),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Dos campos numéricos (mín/máx) + slider sincronizado con ellos.
  Widget _precio() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _CampoPrecio(
                controlador: controladorMin,
                ayuda: 'Desde',
                onChanged: onPrecioMin,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CampoPrecio(
                controlador: controladorMax,
                ayuda: 'Hasta',
                onChanged: onPrecioMax,
              ),
            ),
          ],
        ),
        RangeSlider(
          values: rango,
          min: limites.start,
          max: limites.end,
          activeColor: AppColors.brandGreen,
          inactiveColor: AppColors.trackGrey,
          onChanged: onRango,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Bs ${rango.start.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              'Bs ${rango.end.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        if (rangoInvalido)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'El mínimo supera al máximo',
              style: TextStyle(fontSize: 11, color: AppColors.negativeRed),
            ),
          ),
      ],
    );
  }

  /// Casilla + etiqueta + conteo opcional (mismo ancho que la sección).
  ///
  /// El `Material` propio evita la aserción de Flutter: la tarjeta blanca
  /// (DecoratedBox) quedaría entre el `ListTile` y el Material de la página.
  Widget _opcion({
    required String etiqueta,
    required bool seleccionado,
    required ValueChanged<bool> onChanged,
    int? conteo,
  }) {
    return Material(
      color: Colors.transparent,
      child: CheckboxListTile(
        value: seleccionado,
        onChanged: (valor) => onChanged(valor ?? false),
        activeColor: AppColors.brandGreen,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(
          conteo == null ? etiqueta : '$etiqueta ($conteo)',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// Campo numérico compacto "Desde" / "Hasta". Texto vacío = sin límite y
/// un valor incompleto (p. ej. `12.`) se ignora hasta ser parseable.
class _CampoPrecio extends StatelessWidget {
  const _CampoPrecio({
    required this.controlador,
    required this.ayuda,
    required this.onChanged,
  });

  final TextEditingController controlador;
  final String ayuda;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controlador,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}([.,]\d{0,2})?')),
      ],
      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: ayuda,
        hintStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        prefixText: 'Bs ',
        prefixStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        isDense: true,
        filled: true,
        fillColor: AppColors.pageBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brandGreen),
        ),
      ),
    );
  }
}

/// Título de sección plegable con chevron (patrón del panel de filtros).
class _Seccion extends StatefulWidget {
  const _Seccion({required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  State<_Seccion> createState() => _SeccionState();
}

class _SeccionState extends State<_Seccion> {
  bool _abierta = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _abierta = !_abierta),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.titulo,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  _abierta
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_abierta)
          Padding(padding: const EdgeInsets.only(top: 2), child: widget.child),
      ],
    );
  }
}

class _Separador extends StatelessWidget {
  const _Separador();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Divider(height: 1, color: AppColors.cardBorder),
    );
  }
}
