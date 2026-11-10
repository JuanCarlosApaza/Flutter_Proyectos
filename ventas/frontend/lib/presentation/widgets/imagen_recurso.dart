import 'package:flutter/material.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_colors.dart';

/// Imagen guardada en el backend.
///
/// El valor almacenado en la BD es una **ruta** (`/api/v1/archivos/imagenes/…`)
/// que se sirve desde el propio API; se acepta también una URL externa
/// heredada (`https://…`) por compatibilidad. Cualquier fallo de red se
/// sustituye por un placeholder neutro, nunca rompe el layout.
class ImagenRecurso extends StatelessWidget {
  const ImagenRecurso({
    super.key,
    required this.ruta,
    this.tamano = 36,
    this.radio = 8,
    this.icono = Icons.image_outlined,
  });

  /// Ruta relativa del backend o URL absoluta (`null`/vacío → placeholder).
  final String? ruta;

  final double tamano;
  final double radio;
  final IconData icono;

  /// URL absoluta que puede cargar el navegador/la app.
  static String? absoluta(String? ruta) {
    final valor = ruta?.trim() ?? '';
    if (valor.isEmpty) return null;
    if (valor.startsWith('http://') || valor.startsWith('https://')) {
      return valor;
    }
    return '${ApiConfig.baseUrl}$valor';
  }

  @override
  Widget build(BuildContext context) {
    final url = absoluta(ruta);
    final placeholder = ContenedorPlaceholder(
      tamano: tamano,
      radio: radio,
      icono: icono,
    );

    if (url == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: Image.network(
        url,
        width: tamano,
        height: tamano,
        fit: BoxFit.cover,
        // Decodifica a la medida que se va a pintar (no a la resolución
        // original): menos memoria en la caché de imágenes y sin tirones
        // al hacer scroll con muchas miniaturas.
        cacheWidth: (tamano * MediaQuery.devicePixelRatioOf(context)).round(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}

/// Cuadro neutro que ocupa el hueco de una imagen ausente o rota.
class ContenedorPlaceholder extends StatelessWidget {
  const ContenedorPlaceholder({
    super.key,
    required this.tamano,
    this.radio = 8,
    this.icono = Icons.image_outlined,
  });

  final double tamano;
  final double radio;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(radio),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Icon(icono, size: tamano * 0.5, color: AppColors.textSecondary),
    );
  }
}

/// Amplía la imagen de un producto en un diálogo (toca la miniatura para
/// verla grande). La red puede fallar: se muestra el mismo placeholder.
Future<void> mostrarImagenAmpliada(
  BuildContext context, {
  String? ruta,
  String titulo = 'Imagen del producto',
}) {
  final url = ImagenRecurso.absoluta(ruta);

  Widget imagen;
  if (url == null) {
    imagen = const ContenedorPlaceholder(tamano: 300, radio: 12);
  } else {
    imagen = Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const ContenedorPlaceholder(tamano: 300, radio: 12),
      errorBuilder: (context, error, stack) =>
          const ContenedorPlaceholder(tamano: 300, radio: 12),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        titulo,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      content: SizedBox(width: 300, height: 300, child: imagen),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text(
            'Cerrar',
            style: TextStyle(color: AppColors.brandGreen),
          ),
        ),
      ],
    ),
  );
}
