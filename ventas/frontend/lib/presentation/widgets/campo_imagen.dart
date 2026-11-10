import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failure.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/comprimir_imagen.dart';
import '../../core/widgets/alertas.dart';
import 'imagen_recurso.dart';

/// Límite de subida; debe coincidir con `AlmacenamientoImagenes.maxBytes`
/// del backend (3 MB).
const int maxBytesImagen = 3 * 1024 * 1024;

/// Selector de imagen local: previsualización + botón "Subir imagen".
///
/// El fichero se lee en el cliente, **se reduce si supera los 3 MB**
/// (ver [comprimirImagen]), se envía en base64 a
/// `POST /api/v1/archivos/imagenes` y la API devuelve la **ruta** que queda
/// guardada en el recurso (`onSubido`). El binario nunca se persiste en la BD.
class SubidorImagen extends StatefulWidget {
  const SubidorImagen({
    super.key,
    required this.valor,
    required this.etiqueta,
    required this.onSubido,
    required this.onQuitar,
    this.auxiliar,
    this.tieneError = false,
    this.soloLectura = false,
    this.api,
  });

  /// Ruta actual (`/api/v1/archivos/imagenes/…` o vacío).
  final String valor;
  final String etiqueta;

  /// Texto de ayuda bajo el campo (o mensaje de validación).
  final String? auxiliar;

  /// `true` cuando la validación del formulario ha fallado (borde rojo).
  final bool tieneError;

  final ValueChanged<String> onSubido;
  final VoidCallback onQuitar;

  /// Vista de detalle: solo la previsualización, sin subir ni quitar.
  final bool soloLectura;

  /// Cliente HTTP inyectable (por defecto el real de [ApiClient]).
  final ApiClient? api;

  @override
  State<SubidorImagen> createState() => _SubidorImagenState();
}

class _SubidorImagenState extends State<SubidorImagen> {
  /// Cliente con el que se sube: el inyectado en los tests o el **compartido**
  /// de la app, que es el único que lleva el token de sesión. Crear uno nuevo
  /// aquí mandaba la subida sin `Authorization` y la API respondía 401
  /// «Se requiere iniciar sesión» aunque la sesión estuviera abierta.
  late final ApiClient _api = widget.api ?? context.read<ApiClient>();
  bool _subiendo = false;
  bool _comprimiendo = false;
  String? _error;

  Future<void> _subir() async {
    final fichero = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Imágenes',
          extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
        ),
      ],
    );
    if (fichero == null || !mounted) return;

    setState(() {
      _subiendo = true;
      _error = null;
    });

    try {
      var bytes = await fichero.readAsBytes();
      var nombre = fichero.name;
      final bytesOriginales = bytes.length;

      // Por encima del límite la imagen se reduce en el cliente en vez de
      // rechazarse (ver comprimirImagen).
      if (bytes.length > maxBytesImagen) {
        if (mounted) setState(() => _comprimiendo = true);
        final reducida = await comprimirImagen(
          bytes: bytes,
          nombre: nombre,
          maxBytes: maxBytesImagen,
        );
        if (reducida == null) {
          if (mounted) {
            setState(() {
              _error =
                  'La imagen pesa ${megas(bytesOriginales)} y no se pudo '
                  'reducir por debajo de 3 MB. Prueba con otra foto o en JPG.';
            });
          }
          return;
        }
        bytes = reducida.bytes;
        nombre = reducida.nombre;
      }

      final respuesta = await _api.post(
        '/api/v1/archivos/imagenes',
        body: {'nombre': nombre, 'datos': base64Encode(bytes)},
      );

      final ruta = respuesta is Map ? respuesta['ruta'] : null;
      if (ruta is! String || ruta.isEmpty) {
        setState(
          () => _error = 'El servidor no devolvió la ruta de la imagen.',
        );
        return;
      }
      widget.onSubido(ruta);

      // Avisa del ahorro solo cuando la imagen ha tenido que reducirse.
      if (bytes.length != bytesOriginales && mounted) {
        await alertaInfo(
          context,
          titulo: 'Imagen optimizada',
          mensaje:
              'Se redujo de ${megas(bytesOriginales)} a ${megas(bytes.length)} '
              'antes de subirla.',
        );
      }
    } on Failure catch (failure) {
      setState(() => _error = failure.message);
    } catch (_) {
      setState(
        () => _error = 'No se pudo subir la imagen. Inténtalo de nuevo.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _subiendo = false;
          _comprimiendo = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hayValor = widget.valor.trim().isNotEmpty;
    final nombreFichero = hayValor
        ? widget.valor.split('/').last
        : 'Sin imagen';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.tieneError
              ? AppColors.negativeRed
              : AppColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.etiqueta,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ImagenRecurso(
                ruta: hayValor ? widget.valor : null,
                tamano: 72,
                radio: 12,
                icono: Icons.image_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombreFichero,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (!widget.soloLectura)
                      Text(
                        widget.auxiliar ??
                            'PNG, JPG, GIF o WebP · máx. 3 MB '
                                '(se comprime si pesa más)',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (!widget.soloLectura) const SizedBox(height: 12),
          if (!widget.soloLectura)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _subiendo ? null : _subir,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.cardBorder),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _subiendo
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_outlined, size: 18),
                  label: Text(
                    _comprimiendo
                        ? 'Comprimiendo…'
                        : _subiendo
                        ? 'Subiendo…'
                        : (hayValor ? 'Cambiar imagen' : 'Subir imagen'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (hayValor)
                  OutlinedButton.icon(
                    onPressed: _subiendo ? null : widget.onQuitar,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.cardBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AppColors.negativeRed,
                    ),
                    label: const Text(
                      'Quitar',
                      style: TextStyle(
                        color: AppColors.negativeRed,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.negativeRed,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
