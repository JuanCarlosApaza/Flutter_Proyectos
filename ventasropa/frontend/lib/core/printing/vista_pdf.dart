import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../theme/app_colors.dart';
import 'compartir_pdf.dart';

/// Hoja con la vista previa de un PDF y las acciones del propio equipo:
/// **imprimir** con la impresora del sistema (o la del navegador en la web)
/// y **compartir** para guardar o enviar el archivo (Web Share API en web).
///
/// La comparten los recibos de Ventas y las cotizaciones: quien llama solo
/// aporta los bytes ya generados, el título de la hoja y el nombre de archivo.
Future<void> mostrarVistaPdf(
  BuildContext context, {
  required Future<Uint8List> bytes,
  required String titulo,
  required String archivo,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: PdfPreview(
              build: (_) => bytes,
              pdfFileName: archivo,
              // Documento a medida: sin selector de formato/orientación ni
              // conmutador de depuración, solo imprimir y compartir.
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              // La compartición del paquete solo descarga en web; se
              // sustituye por la hoja nativa (`compartir_pdf`).
              allowSharing: false,
              actions: [
                Tooltip(
                  message: 'Compartir',
                  child: IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: () async {
                      try {
                        await compartirPdf(await bytes, archivo);
                      } catch (_) {
                        // El navegador puede bloquear la hoja fuera de un
                        // gesto del usuario: no hay nada que avisar.
                      }
                    },
                  ),
                ),
              ],
              actionBarTheme: const PdfActionBarTheme(
                backgroundColor: AppColors.cardBg,
                iconColor: AppColors.brandGreen,
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
