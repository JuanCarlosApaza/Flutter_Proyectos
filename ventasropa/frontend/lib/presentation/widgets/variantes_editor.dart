/// Editor de variantes de una prenda (talla + color): donde vive el **stock
/// real** de la tienda de ropa.
///
/// Se abre desde la fila de un producto (`ProductosPage.accionesExtras`) y
/// permite ver el stock de cada combinación, ajustarlo, añadir variantes y
/// ocultarlas (solo cuando su stock llega a 0).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/alertas.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/recurso_controller.dart';
import 'desplegable_buscable.dart';
import 'recurso_form.dart';
import 'variantes_alta.dart';

/// Abre el editor de variantes de [producto] en un bottom sheet.
///
/// Al cerrarlo recarga el listado de productos: cada variante mueve el stock
/// agregado de la prenda.
Future<void> mostrarEditorVariantes(
  BuildContext context,
  Recurso producto,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _EditorVariantes(producto: producto),
  );
  if (context.mounted) {
    await context.read<ProductosController>().recargar();
  }
}

class _EditorVariantes extends StatefulWidget {
  const _EditorVariantes({required this.producto});

  final Recurso producto;

  @override
  State<_EditorVariantes> createState() => _EditorVariantesState();
}

class _EditorVariantesState extends State<_EditorVariantes> {
  int get _productoId => widget.producto.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final variantes = context.read<VariantesController>();
      final tallas = context.read<TallasController>();
      final colores = context.read<ColoresController>();
      variantes.cargar(_productoId);
      if (!tallas.completoCargado) tallas.cargar();
      if (!colores.completoCargado) colores.cargar();
    });
  }

  Future<void> _operacion(Future<void> Function() operacion) async {
    try {
      await operacion();
    } on Failure catch (failure) {
      if (mounted) await alertaError(context, mensaje: failure.message);
    } catch (_) {
      if (mounted) await alertaError(context, mensaje: 'Operación no completada');
    }
  }

  @override
  Widget build(BuildContext context) {
    final variantes = context.watch<VariantesController>();
    final tallas = context.read<TallasController>();
    final colores = context.read<ColoresController>();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: ConstrainedBox(
        // En escritorio el sheet no debe ocupar todo el ancho.
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checkroom_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tallas y colores — ${widget.producto.texto('nombre')}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _agregar(tallas, colores),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Variante'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (!variantes.cargando &&
                variantes.errorMessage == null &&
                variantes.variantes.isNotEmpty)
              _resumen(variantes.variantes),
            const SizedBox(height: 12),
            if (variantes.cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (variantes.errorMessage != null)
              Text(
                variantes.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (variantes.variantes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('Esta prenda todavía no tiene variantes.'),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: variantes.variantes.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _filaVariante(variantes.variantes[index]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Resumen legible del detalle: cuántas variantes hay, su stock total y
  /// (si las hay) las ocultas, para no tener que sumarlas a ojo fila a fila.
  Widget _resumen(List<Recurso> lista) {
    final visibles = lista.where((v) => v.texto('estado') != 'ELIMINADO');
    final ocultas = lista.length - visibles.length;
    final stockTotal = visibles.fold<int>(
      0,
      (suma, v) => suma + (v.numero('stock') ?? 0).toInt(),
    );
    final stockOculto = lista
        .where((v) => v.texto('estado') == 'ELIMINADO')
        .fold<int>(0, (suma, v) => suma + (v.numero('stock') ?? 0).toInt());

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _pastilla(
          icono: Icons.style_outlined,
          texto: '${lista.length} ${lista.length == 1 ? 'variante' : 'variantes'}',
          fuerte: true,
        ),
        _pastilla(
          icono: Icons.inventory_2_outlined,
          texto: 'Stock total: $stockTotal',
          fuerte: true,
        ),
        if (ocultas > 0)
          _pastilla(
            icono: Icons.visibility_off_outlined,
            texto: '$ocultas oculta${ocultas == 1 ? '' : 's'} '
                '($stockOculto unid.)',
          ),
        _pastilla(
          icono: Icons.summarize_outlined,
          texto: 'La prenda suma sus variantes',
        ),
      ],
    );
  }

  /// Chip compacto del resumen del editor de variantes.
  Widget _pastilla({
    required IconData icono,
    required String texto,
    bool fuerte = false,
  }) {
    final color = fuerte ? AppColors.brandGreen : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12,
              fontWeight: fuerte ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaVariante(Recurso variante) {
    final stock = (variante.numero('stock') ?? 0).toInt();
    final oculta = variante.texto('estado') == 'ELIMINADO';
    final hex = variante.texto('codigoHex', vacio: '');

    return Opacity(
      opacity: oculta ? 0.5 : 1,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          radius: 10,
          backgroundColor: hex.isEmpty
              ? AppColors.trackGrey
              : Color(int.parse('FF${hex.substring(1)}', radix: 16)),
          child: hex.isEmpty
              ? const Icon(Icons.style_outlined, size: 14)
              : null,
        ),
        title: Text(
          '${variante.texto('talla', vacio: '—')} · '
          '${variante.texto('color', vacio: '—')}'
          '${oculta ? ' (oculta)' : ''}',
        ),
        subtitle: Text('Stock: $stock unidades'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Quitar 1',
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: oculta || stock <= 0
                  ? null
                  : () => _operacion(
                      () => context.read<VariantesController>().actualizar(
                        _productoId,
                        variante.id,
                        {'stock': stock - 1},
                      ),
                    ),
            ),
            Text('$stock'),
            IconButton(
              tooltip: 'Añadir 1',
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: oculta
                  ? null
                  : () => _operacion(
                      () => context.read<VariantesController>().actualizar(
                        _productoId,
                        variante.id,
                        {'stock': stock + 1},
                      ),
                    ),
            ),
            IconButton(
              tooltip: 'Eliminar variante',
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: Theme.of(context).colorScheme.error,
              ),
              onPressed: oculta
                  ? null
                  : () async {
                      final seguro = await confirmarAccion(
                        context,
                        titulo: 'Eliminar variante',
                        mensaje:
                            'Se ocultará '
                            '${variante.texto('talla')} / '
                            '${variante.texto('color')}. '
                            'Su stock debe ser 0.',
                      );
                      if (!seguro || !mounted) return;
                      await _operacion(
                        () => context.read<VariantesController>().eliminar(
                          _productoId,
                          variante.id,
                        ),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// Alta de variante: talla + color y stock inicial.
  ///
  /// Los catálogos pueden venir vacíos: el diálogo crea lo que haga falta
  /// con «Nueva talla» / «Nuevo color» (mismo patrón que el alta de
  /// producto), así que no se bloquea nada antes de abrirlo.
  Future<void> _agregar(
    TallasController tallas,
    ColoresController colores,
  ) async {
    final paquete = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _DialogoVariante(tallas: tallas, colores: colores),
    );
    if (paquete == null || !mounted) return;
    final partes = paquete.split('|');
    await _operacion(
      () => context.read<VariantesController>().crear(_productoId, {
        'tallaId': int.parse(partes[0]),
        'colorId': int.parse(partes[1]),
        'stock': int.parse(partes[2]),
      }),
    );
  }
}

/// Formulario de alta de variante; cierra devolviendo `tallaId|colorId|stock`.
class _DialogoVariante extends StatefulWidget {
  const _DialogoVariante({required this.tallas, required this.colores});

  final TallasController tallas;
  final ColoresController colores;

  @override
  State<_DialogoVariante> createState() => _DialogoVarianteState();
}

class _DialogoVarianteState extends State<_DialogoVariante> {
  int? _tallaId;
  int? _colorId;
  final _stock = TextEditingController(text: '1');

  @override
  void dispose() {
    _stock.dispose();
    super.dispose();
  }

  /// Alta en línea desde el diálogo: da de alta el nombre y devuelve su
  /// **id**, que es lo que viaja a la API en esta vía (el backend también
  /// acepta el nombre y lo resolvería él).
  Future<String?> _alta(RecursoController controller, String nombre) async {
    final creado = await altaEnCatalogo(controller, nombre);
    // El registro nuevo ya está en el catálogo: se repinta para que la
    // lista deje de enseñarlo como texto suelto y se pueda volver a elegir.
    if (mounted) setState(() {});
    return '${creado.id}';
  }

  @override
  Widget build(BuildContext context) {
    final tallas = widget.tallas.items
        .where((t) => t.texto('estado') != 'ELIMINADO')
        .toList();
    final colores = widget.colores.items
        .where((c) => c.texto('estado') != 'ELIMINADO')
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nueva variante',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Si la talla o el color que buscas no existen, créalos aquí '
              'mismo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            DesplegableBuscable(
              initialValue: _tallaId?.toString(),
              opciones: opcionesDe(tallas),
              decoracion: const InputDecoration(labelText: 'Talla *'),
              onChanged: (valor) =>
                  setState(() => _tallaId = int.tryParse(valor ?? '')),
              onCrear: (nombre) => _alta(widget.tallas, nombre),
              etiquetaCrear: 'Nueva talla',
            ),
            const SizedBox(height: 12),
            DesplegableBuscable(
              initialValue: _colorId?.toString(),
              opciones: opcionesDe(colores),
              decoracion: const InputDecoration(labelText: 'Color *'),
              onChanged: (valor) =>
                  setState(() => _colorId = int.tryParse(valor ?? '')),
              onCrear: (nombre) => _alta(widget.colores, nombre),
              etiquetaCrear: 'Nuevo color',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Stock inicial *',
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  final stock = int.tryParse(_stock.text.trim()) ?? -1;
                  if (_tallaId == null || _colorId == null || stock < 0) {
                    alertaError(
                      context,
                      mensaje: 'Elige talla, color y un stock válido.',
                    );
                    return;
                  }
                  Navigator.of(context).pop('$_tallaId|$_colorId|$stock');
                },
                child: const Text('Agregar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
