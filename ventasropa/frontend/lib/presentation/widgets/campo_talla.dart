import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Tallas de vestir: letras cortas (de la XXS a la XXXL).
const List<String> tallasRopa = [
  'XXS',
  'XS',
  'S',
  'M',
  'L',
  'XL',
  'XXL',
  'XXXL',
];

/// Tallas de calzado: números de la 34 a la 47 (fuera de este rango se
/// escribe el número a mano y la validación lo admite: `20`, `110`...).
const List<String> tallasCalzado = [
  '34',
  '35',
  '36',
  '37',
  '38',
  '39',
  '40',
  '41',
  '42',
  '43',
  '44',
  '45',
  '46',
  '47',
];

/// Prenda sin talla: gorros, cinturones, medias de una sola talla...
const String tallaUnica = 'Única';

/// Campo de talla con **presets por sistema**: elige `Ropa` (`S`, `M`,
/// `L`...), `Calzado` (`38`, `40`, `42`...) o `Ambas` y toca un tamaño para
/// rellenar el campo — o escríbelo si no está en la lista.
///
/// Es un envoltorio del campo de texto normal (que sigue poniendo su
/// etiqueta, su auxiliar y su validación, p. ej. `tallaValida`): los chips
/// son una ayuda para llegar antes y para que nadie meta frases como
/// «un par de medias» en el catálogo de tallas.
final class CampoTalla extends StatefulWidget {
  const CampoTalla({
    super.key,
    required this.campoTexto,
    required this.controlador,
  });

  /// El campo de texto ya construido por `RecursoForm`.
  final Widget campoTexto;

  /// Controlador del valor: los chips escriben en él y leen su texto para
  /// marcarse como seleccionados.
  final TextEditingController controlador;

  @override
  State<CampoTalla> createState() => _CampoTallaState();
}

final class _CampoTallaState extends State<CampoTalla> {
  /// Sistema visible: `ropa`, `calzado` o `ambos` (por defecto, los dos:
  /// quien da de alta escoge uno de los dos o los dos). Es solo una ayuda
  /// de pantalla, no un dato que se guarde en el catálogo.
  String _sistema = 'ambos';

  @override
  void initState() {
    super.initState();
    // Repinta los chips mientras se escribe: el resaltado sigue el texto.
    widget.controlador.addListener(_repintar);
  }

  @override
  void didUpdateWidget(covariant CampoTalla viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.controlador != widget.controlador) {
      viejo.controlador.removeListener(_repintar);
      widget.controlador.addListener(_repintar);
    }
  }

  @override
  void dispose() {
    widget.controlador.removeListener(_repintar);
    super.dispose();
  }

  void _repintar() {
    if (mounted) setState(() {});
  }

  /// Tocar un tamaño lo escribe en el campo; tocar el que ya está puesto lo
  /// quita (el chip funciona como un interruptor).
  void _tocar(String valor) {
    final actual = widget.controlador.text.trim().toUpperCase();
    widget.controlador.text = actual == valor.toUpperCase() ? '' : valor;
  }

  @override
  Widget build(BuildContext context) {
    final actual = widget.controlador.text.trim().toUpperCase();
    final valores = [
      if (_sistema != 'calzado') ...tallasRopa,
      if (_sistema != 'ropa') ...tallasCalzado,
      tallaUnica,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.campoTexto,
        const SizedBox(height: 10),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'ropa', label: Text('Ropa')),
            ButtonSegment(value: 'calzado', label: Text('Calzado')),
            ButtonSegment(value: 'ambas', label: Text('Ambas')),
          ],
          selected: {_sistema},
          onSelectionChanged: (e) => setState(() => _sistema = e.first),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final valor in valores)
              FilterChip(
                label: Text(valor),
                labelStyle: const TextStyle(fontSize: 12),
                visualDensity: VisualDensity.compact,
                selected: actual == valor.toUpperCase(),
                onSelected: (_) => _tocar(valor),
              ),
          ],
        ),
        if (widget.controlador.text.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Toca un tamaño o escríbelo',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
