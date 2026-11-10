import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/validation/reglas.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/carrito_controller.dart';
import 'imagen_recurso.dart';

/// Tarjeta de producto del catálogo (estilo e-commerce): foto, etiqueta con
/// la **marca (solo si el producto tiene)** sobre el nombre, nombre,
/// categoría, precio, stock y el botón para agregarlo al carrito.
///
/// Cuando el producto ya está en el carrito el botón se sustituye por un
/// contador con `+` / `−` para ajustar la cantidad (entera o fraccionada,
/// según la unidad) sin salir del grid. La altura
/// es fija ([altura]) para que el `GridView` pinte filas parejas.
///
/// Rendimiento: la fila de acciones escucha el carrito con un `Selector`, de
/// modo que al agregar una unidad **solo** se redibuja esa fila de esa
/// tarjeta; la página y el resto de la vitrina no se enteran.
class ProductoTarjeta extends StatelessWidget {
  const ProductoTarjeta({
    super.key,
    required this.producto,
    required this.categoria,
    required this.marca,
    required this.onAgregar,
    required this.onRestar,
  });

  /// Altura fija de la tarjeta: se usa como `mainAxisExtent` del grid.
  /// Incluye el hueco de la etiqueta de marca (20 px) para que todas las
  /// tarjetas sigan midiendo lo mismo, con marca o sin ella.
  static const double altura = 320;

  /// Registro del producto (nombre, imagen, precioVenta, stock…).
  final Recurso producto;

  /// Nombre de su categoría ya resuelto (para no recorrer la lista en cada
  /// tarjeta).
  final String categoria;

  /// Nombre de su marca, ya resuelto. **Vacío = sin marca**: en ese caso la
  /// tarjeta no pinta nada (no todos los productos llevan marca).
  final String marca;

  final VoidCallback onAgregar;
  final VoidCallback onRestar;

  @override
  Widget build(BuildContext context) {
    final precio = producto.numero('precioVenta') ?? 0;
    final stock = producto.numero('stock') ?? 0;
    // El stock es fraccionado: `0.250 KG` ya se puede vender desde el
    // catálogo; solo lo que está a cero no tiene botón de agregar.
    final sinStock = stock <= 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _FotoProducto(imagen: producto.texto('imagen', vacio: '')),
          const SizedBox(height: 10),
          // Etiqueta con la marca, encima del nombre (solo si la tiene):
          // la tarjeta crece 20 px para que quepa sin desbordar.
          if (marca.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brandGreenDark.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.brandGreenDark.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  marca,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandGreenDark,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            producto.texto('nombre', vacio: 'Producto'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            categoria,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Bs ${precio.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Flexible + FittedBox: con la unidad el chip creció y a
              // 360 px desbordaba la fila; ahora se escala en vez de salirse.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _ChipStock(
                    stock: stock,
                    unidad: producto.texto('unidad', vacio: 'UN'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // La cantidad en el carrito es fraccionada (0.250 KG), así que el
          // selector sigue siendo un double. Suma las líneas de todos los
          // colores de este producto (badge «en el carrito»).
          Selector<CarritoController, double>(
            selector: (context, carrito) => carrito.totalDe(producto.id),
            builder: (context, enCarrito, _) =>
                _acciones(enCarrito: enCarrito, sinStock: sinStock),
          ),
        ],
      ),
    );
  }

  /// Botón "Agregar" o, si ya está en el carrito, el contador de cantidad.
  Widget _acciones({required double enCarrito, required bool sinStock}) {
    if (enCarrito <= 0) {
      return SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton.icon(
          onPressed: sinStock ? null : onAgregar,
          icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
          label: Text(sinStock ? 'Sin stock' : 'Agregar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandGreen,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.pageBg,
            disabledForegroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          _BotonContador(
            icono: Icons.remove_rounded,
            tooltip: 'Restar cantidad',
            onTap: onRestar,
          ),
          Expanded(
            child: Text(
              // `12.75 KG` o `3` en carrito: la unidad la pinta el panel.
              '${cantidadTexto(enCarrito)} en carrito',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          _BotonContador(
            icono: Icons.add_rounded,
            tooltip: 'Sumar cantidad',
            activo: true,
            onTap: onAgregar,
          ),
        ],
      ),
    );
  }
}

/// Chip de disponibilidad: stock en verde, "Agotado" en rojo.
class _ChipStock extends StatelessWidget {
  const _ChipStock({required this.stock, required this.unidad});

  final double stock;

  /// Unidad de venta del producto (`UN`, `KG`...), para que el chip diga
  /// «Stock 12.75 KG» y no un número suelto.
  final String unidad;

  @override
  Widget build(BuildContext context) {
    final conStock = stock > 0;
    final color = conStock ? AppColors.brandGreen : AppColors.negativeRed;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        conStock ? 'Stock ${cantidadTexto(stock)} $unidad' : 'Agotado',
        maxLines: 1,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Cuadrado 40×40 con radio 10 para sumar/restar unidades.
class _BotonContador extends StatelessWidget {
  const _BotonContador({
    required this.icono,
    required this.onTap,
    required this.tooltip,
    this.activo = false,
  });

  final IconData icono;
  final VoidCallback onTap;
  final String tooltip;
  final bool activo;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: activo ? AppColors.brandGreen : AppColors.pageBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Icon(
            icono,
            size: 18,
            color: activo ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Foto del producto a ancho completo; cualquier fallo de red cae en un
/// placeholder neutro (mismo criterio que [ImagenRecurso]).
class _FotoProducto extends StatelessWidget {
  const _FotoProducto({required this.imagen});

  static const double _alto = 118;

  /// Ruta del backend o URL externa (cadena vacía = sin imagen).
  final String imagen;

  @override
  Widget build(BuildContext context) {
    final url = ImagenRecurso.absoluta(imagen);
    final placeholder = Container(
      width: double.infinity,
      height: _alto,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: const Icon(
        Icons.image_outlined,
        size: 28,
        color: AppColors.textSecondary,
      ),
    );

    if (url == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: double.infinity,
        height: _alto,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          // Decodifica a la altura real de la tarjeta, no a la resolución
          // original del archivo (memoria y CPU al montar muchas tarjetas).
          cacheHeight: (_alto * MediaQuery.devicePixelRatioOf(context)).round(),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : placeholder,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      ),
    );
  }
}
