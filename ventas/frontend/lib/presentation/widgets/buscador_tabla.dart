import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/entities/recurso.dart';
import 'recurso_tabla.dart';

/// Equivalencias acento → letra para comparar búsquedas sin importar cómo
/// las escriba el usuario ("analgesicos" encuentra "Analgésicos").
const Map<String, String> _acentos = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// Pasa a minúsculas, recorta y quita acentos: es la forma en la que se
/// comparan las búsquedas contra los registros.
///
/// Un solo recorrido por carácter (el mapeo [_acentosPorCodigo] resuelve de
/// golpe): antes eran 22 `replaceAll` consecutivos sobre cada registro.
String normalizarTexto(String texto) {
  final base = texto.toLowerCase().trim();
  final salida = StringBuffer();
  for (final codigo in base.runes) {
    salida.writeCharCode(_acentosPorCodigo[codigo] ?? codigo);
  }
  return salida.toString();
}

/// Equivalencias de [_acentos] por código de punto de código.
final Map<int, int> _acentosPorCodigo = {
  for (final entrada in _acentos.entries)
    entrada.key.runes.first: entrada.value.runes.first,
};

/// Filtra [items] con el texto [busqueda] (sin normalizar) mirando el id,
/// los valores visibles en [columnas] y el resto de campos del registro.
///
/// Con [busqueda] vacía devuelve la lista completa. El resultado respeta el
/// orden original, así la paginación sigue siendo estable.
List<Recurso> filtrarPorBusqueda(
  List<Recurso> items,
  List<ColumnaTabla> columnas,
  String busqueda,
) {
  final consulta = normalizarTexto(busqueda);
  if (consulta.isEmpty) return items;
  return items
      .where((item) {
        final partes = <String>[
          item.id.toString(),
          for (final columna in columnas) columna.valor(item),
          for (final valor in item.datos.values)
            if (valor is String || valor is num) valor.toString(),
        ];
        return normalizarTexto(partes.join(' ')).contains(consulta);
      })
      .toList(growable: false);
}

/// Campo de búsqueda para filtrar una tabla en el cliente.
///
/// Va normalmente al principio de un `Wrap` junto a los chips de filtro y
/// avisa al padre con [onChanged] para que este filtre (ver
/// [filtrarPorBusqueda]) y reinicie la paginación.
class BuscadorTabla extends StatefulWidget {
  const BuscadorTabla({
    super.key,
    required this.onChanged,
    this.textoAyuda = 'Buscar…',
    this.anchuraMaxima = 320,
    this.controlador,
    this.autofocus = false,
    this.onBuscar,
  });

  /// Texto escrito por el usuario (sin normalizar).
  final ValueChanged<String> onChanged;

  /// Texto de ayuda cuando el campo está vacío.
  final String textoAyuda;

  /// Ancho máximo del campo; en pantallas estrechas se ajusta al `Wrap`.
  final double anchuraMaxima;

  /// Controlador externo del texto: permite limpiar la búsqueda desde los
  /// botones de la propia página (`clear()`). Si no se pasa, el widget crea
  /// y gestiona el suyo.
  final TextEditingController? controlador;

  /// El campo pide el foco al montarse (p. ej. el buscador de una hoja).
  final bool autofocus;

  /// Se dispara con `Intro`/`Buscar` del teclado: el selector de una hoja
  /// lo usa para elegir el primer resultado sin soltar el teclado.
  final ValueChanged<String>? onBuscar;

  @override
  State<BuscadorTabla> createState() => _BuscadorTablaState();
}

class _BuscadorTablaState extends State<BuscadorTabla> {
  late final TextEditingController _controlador =
      widget.controlador ?? TextEditingController();

  /// `false` cuando el controlador lo aporta la página (no se dispone).
  late final bool _gestionaControlador;

  @override
  void initState() {
    super.initState();
    _gestionaControlador = widget.controlador == null;
    _controlador.addListener(_alCambiarTexto);
  }

  @override
  void dispose() {
    _controlador.removeListener(_alCambiarTexto);
    if (_gestionaControlador) _controlador.dispose();
    super.dispose();
  }

  // Se redibuja solo para mostrar/ocultar el botón de limpiar.
  void _alCambiarTexto() {
    if (mounted) setState(() {});
  }

  void _limpiar() {
    _controlador.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final vacio = _controlador.text.isEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.anchuraMaxima),
      child: TextField(
        controller: _controlador,
        onChanged: widget.onChanged,
        onSubmitted: widget.onBuscar,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: widget.textoAyuda,
          hintStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 18,
            color: AppColors.textSecondary,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 0,
          ),
          suffixIcon: vacio
              ? null
              : IconButton(
                  tooltip: 'Limpiar búsqueda',
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: _limpiar,
                ),
          suffixIconConstraints: BoxConstraints(
            minWidth: vacio ? 0 : 38,
            minHeight: 0,
          ),
          isDense: true,
          filled: true,
          fillColor: AppColors.cardBg,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
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
      ),
    );
  }
}
