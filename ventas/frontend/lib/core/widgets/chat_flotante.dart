import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/controllers/chat_controller.dart';
import '../theme/app_colors.dart';

/// Burbuja de chat flotante presente en **todas** las pantallas.
///
/// Se monta en el `builder` de `MaterialApp`, es decir, por encima del
/// `Navigator`: así también asoma en el login y sobre cualquier hoja modal,
/// sin tener que tocar cada pantalla.
///
/// Ese emplazamiento tiene una consecuencia que manda el diseño: en ese punto
/// **no hay `Overlay` ni `Navigator` por encima** (los dos viven dentro del
/// `Navigator`, que es el `child` que se recibe). Por eso la burbuja trae su
/// propio `Overlay` —para que los `Tooltip` funcionen— y la conversación no
/// se abre con `showModalBottomSheet`, que necesita un `Navigator`, sino como
/// una capa más de este mismo `Stack`.
class ChatFlotante extends StatefulWidget {
  const ChatFlotante({
    super.key,
    required this.child,
    this.autenticado = true,
    this.visible = true,
  });

  final Widget child;

  /// ¿Hay usuario conectado? Lo decide quien la monta (`app.dart`, que sí
  /// puede mirar `AuthController`): sin sesión (login, splash, cierre) la
  /// burbuja no se pinta. El valor por defecto `true` conserva el
  /// comportamiento en widgets aislados (p. ej. tests).
  final bool autenticado;

  /// Ajuste «Burbuja del asistente» (`burbujaIA`): permite ocultarla
  /// porque en celular ocupa pantalla. También lo decide `app.dart`.
  final bool visible;

  @override
  State<ChatFlotante> createState() => _ChatFlotanteState();
}

class _ChatFlotanteState extends State<ChatFlotante> {
  /// ¿Está desplegada la hoja de conversación?
  bool _hojaAbierta = false;

  /// Sondeo del progreso de descarga (lo puede empezar Ajustes o esta hoja).
  Timer? _sondeo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _programarSondeo();
  }

  @override
  void dispose() {
    _sondeo?.cancel();
    super.dispose();
  }

  /// Mantiene vivo el sondeo mientras haya una descarga en marcha y la para
  /// en cuanto termina (o si este widget se destruye).
  void _programarSondeo() {
    _sondeo?.cancel();
    _sondeo = null;
    if (!mounted) return;
    if (!context.read<ChatController>().estado.descargando) return;

    _sondeo = Timer.periodic(const Duration(milliseconds: 700), (temporizador) {
      if (!mounted) {
        temporizador.cancel();
        return;
      }
      final chat = context.read<ChatController>();
      chat.sondearDescarga();
      if (!chat.estado.descargando) {
        temporizador.cancel();
        _sondeo = null;
        // Acaba de terminar: se relee el estado para ofrecer el chat.
        chat.refrescarModelo();
      }
    });
  }

  void _abrir() {
    _programarSondeo();
    setState(() => _hojaAbierta = true);
  }

  void _cerrar() {
    if (!_hojaAbierta) return;
    // Si se cierra con el teclado abierto, no se debe dejar tapando la
    // pantalla que queda debajo.
    FocusScope.of(context).unfocus();
    setState(() => _hojaAbierta = false);
  }

  @override
  Widget build(BuildContext context) {
    // Sin sesión (login, splash o cierre) o con la burbuja desactivada en
    // Ajustes, no se pinta: allí no hay usuario conectado que pregunte.
    if (!widget.autenticado || !widget.visible) {
      _hojaAbierta = false;
      _sondeo?.cancel();
      _sondeo = null;
      return widget.child;
    }

    // Rol sin el ajuste `iaRoles`: la burbuja no existe en esta cuenta
    // (lo decide el backend en `GET /chat/estado`; sin estado aún se pinta
    // y el 403 del envío cortaría igual).
    if (!context.watch<ChatController>().estado.permitido) {
      return widget.child;
    }

    final margen = MediaQuery.viewPaddingOf(context);
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    final pantalla = MediaQuery.sizeOf(context);

    // La hoja ocupa tres cuartos de pantalla, pero nunca por encima de la
    // barra de estado ni del teclado: en un móvil con teclado abierto, la
    // altura útil es bastante menos que el 72 %.
    var alto = pantalla.height * 0.72;
    alto = math.min(alto, pantalla.height - teclado - margen.top - 16);
    alto = math.max(alto, 240);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => Stack(
                  children: [
                    Positioned(
                      right: 18,
                      bottom: margen.bottom + 76,
                      child: Semantics(
                        button: true,
                        label: 'Asistente de la tienda',
                        child: FloatingActionButton(
                          onPressed: _abrir,
                          tooltip: 'Asistente',
                          backgroundColor: AppColors.brandGreen,
                          foregroundColor: Colors.white,
                          shape: const CircleBorder(),
                          child: const _IconoBurbuja(),
                        ),
                      ),
                    ),
                    // Capa que cierra al tocar fuera.
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !_hojaAbierta,
                        child: AnimatedOpacity(
                          opacity: _hojaAbierta ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: GestureDetector(
                            onTap: _cerrar,
                            behavior: HitTestBehavior.opaque,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: margen.bottom + teclado,
                      height: alto,
                      child: IgnorePointer(
                        ignoring: !_hojaAbierta,
                        child: AnimatedSlide(
                          offset: _hojaAbierta
                              ? Offset.zero
                              : const Offset(0, 1),
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          child: AnimatedOpacity(
                            opacity: _hojaAbierta ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: _HojaChat(onCerrar: _cerrar),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// El icono de la burbuja: rueda mientras el modelo redacta la respuesta.
class _IconoBurbuja extends StatelessWidget {
  const _IconoBurbuja();

  @override
  Widget build(BuildContext context) {
    final enviando = context.watch<ChatController>().enviando;
    if (!enviando) return const Icon(Icons.smart_toy_outlined);
    return const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
    );
  }
}

/// Hoja de conversación (no es una ruta: la monta [ChatFlotante]).
class _HojaChat extends StatefulWidget {
  const _HojaChat({required this.onCerrar});

  final VoidCallback onCerrar;

  @override
  State<_HojaChat> createState() => _HojaChatState();
}

class _HojaChatState extends State<_HojaChat> {
  final TextEditingController _controlador = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _controlador.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Baja al final si (y solo si) ya estaba al final: no se roba el scroll
  /// a quien está leyendo un mensaje largo.
  void _alPintar() {
    if (!mounted || !_scroll.hasClients) return;
    final alFinal =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40;
    if (!alFinal) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _enviar() async {
    final texto = _controlador.text;
    _controlador.clear();
    await context.read<ChatController>().enviar(texto);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    // Se recalcula en cada build: la respuesta llega y el chat notifica.
    WidgetsBinding.instance.addPostFrameCallback((_) => _alPintar());

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: AppColors.cardBorder),
      ),
      // La hoja no es una ruta, así que nadie pone el `Material` por ella:
      // sin este, el `TextField` y los `Chip` se negarían a construirse.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            _CabeceraHoja(onCerrar: widget.onCerrar),
            if (chat.error != null) _AvisoError(texto: chat.error!),
            Expanded(
              child: _Mensajes(chat: chat, scroll: _scroll),
            ),
            if (chat.enviando) const _Escribiendo(),
            _CajaEnvio(
              controlador: _controlador,
              habilitado: !chat.enviando,
              onEnviar: _enviar,
            ),
          ],
        ),
      ),
    );
  }
}

class _CabeceraHoja extends StatelessWidget {
  const _CabeceraHoja({required this.onCerrar});

  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final estado = chat.estado;

    final String pista;
    if (!estado.ollamaActivo) {
      pista = 'Ollama no responde · instálalo desde ollama.com';
    } else if (!estado.modeloListo) {
      pista = 'Falta el modelo · descárgalo en Ajustes';
    } else {
      pista = 'Modelo ${estado.modelo} en local';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 10),
      child: Row(
        children: [
          const Icon(
            Icons.smart_toy_outlined,
            size: 20,
            color: AppColors.brandGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Asistente de la tienda',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  pista,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (chat.mensajes.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar conversación',
              onPressed: chat.limpiar,
              icon: const Icon(
                Icons.delete_outline,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onCerrar,
            icon: const Icon(
              Icons.close,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoError extends StatelessWidget {
  const _AvisoError({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.negativeRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.negativeRed.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            size: 16,
            color: AppColors.negativeRed,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Descartar',
            onPressed: context.read<ChatController>().limpiarError,
            icon: const Icon(
              Icons.close,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Mensajes extends StatelessWidget {
  const _Mensajes({required this.chat, required this.scroll});

  final ChatController chat;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    if (chat.mensajes.isEmpty) return const _Bienvenida();
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: chat.mensajes.length,
      itemBuilder: (context, i) => _BurbujaDeMensaje(mensaje: chat.mensajes[i]),
    );
  }
}

/// Pantalla de bienvenida con las preguntas que el modelo sí sabe responder.
class _Bienvenida extends StatelessWidget {
  const _Bienvenida();

  static const List<String> _ejemplos = [
    '¿Cuánto vendí hoy?',
    '¿Qué vendimos más este mes?',
    '¿Qué productos están por vencer?',
    '¿Cuántos productos tengo en stock?',
  ];

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatController>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Pregúntame por el negocio. Respondo con los datos reales del '
          'sistema, sin salir de tu equipo.',
          style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        for (final ejemplo in _ejemplos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                label: Text(
                  ejemplo,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                backgroundColor: AppColors.pageBg,
                side: const BorderSide(color: AppColors.cardBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                onPressed: () => chat.enviar(ejemplo),
              ),
            ),
          ),
      ],
    );
  }
}

class _BurbujaDeMensaje extends StatelessWidget {
  const _BurbujaDeMensaje({required this.mensaje});

  final MensajeChat mensaje;

  @override
  Widget build(BuildContext context) {
    final propio = mensaje.esUsuario;
    return Align(
      alignment: propio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: propio ? AppColors.brandGreen : AppColors.pageBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(propio ? 14 : 4),
            bottomRight: Radius.circular(propio ? 4 : 14),
          ),
          border: propio ? null : Border.all(color: AppColors.cardBorder),
        ),
        child: Text(
          mensaje.texto,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: propio ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _Escribiendo extends StatelessWidget {
  const _Escribiendo();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.brandGreen,
            ),
          ),
          SizedBox(width: 8),
          Text(
            'Pensando la respuesta…',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CajaEnvio extends StatelessWidget {
  const _CajaEnvio({
    required this.controlador,
    required this.habilitado,
    required this.onEnviar,
  });

  final TextEditingController controlador;
  final bool habilitado;
  final Future<void> Function() onEnviar;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controlador,
                enabled: habilitado,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onEnviar(),
                decoration: InputDecoration(
                  hintText: 'Escribe tu pregunta…',
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  filled: true,
                  fillColor: AppColors.pageBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.brandGreen),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: FloatingActionButton(
                heroTag: 'chat-enviar',
                onPressed: habilitado ? onEnviar : null,
                backgroundColor: AppColors.brandGreen,
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                child: const Icon(Icons.send_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
