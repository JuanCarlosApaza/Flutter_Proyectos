import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';

/// Formulario de activación de la suscripción: clave maestra + duración.
///
/// Es el **único** sitio que activa licencias; lo comparten la pantalla de
/// bloqueo (cuando venció) y la sección «Suscripción» de Ajustes (para
/// ampliar antes de que venza). La validación es del servidor: la clave
/// maestra nunca se guarda en el dispositivo.
class ActivacionSuscripcion extends StatefulWidget {
  const ActivacionSuscripcion({super.key, this.onActivado});

  /// Se invoca tras una activación aceptada por el servidor (para que la
  /// pantalla que lo contiene refresque el estado mostrado).
  final VoidCallback? onActivado;

  @override
  State<ActivacionSuscripcion> createState() => _ActivacionSuscripcionState();
}

class _ActivacionSuscripcionState extends State<ActivacionSuscripcion> {
  final _clave = TextEditingController();
  String _duracion = 'semana';
  bool _enviando = false;
  String? _errorLocal;

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  Future<void> _activar() async {
    final clave = _clave.text.trim();
    if (clave.isEmpty || _enviando) return;
    setState(() {
      _enviando = true;
      _errorLocal = null;
    });
    final auth = context.read<AuthController>();
    final ok = await auth.activarSuscripcion(
      clave: clave,
      duracion: _duracion,
    );
    if (!mounted) return;
    setState(() => _enviando = false);
    if (ok) {
      _clave.clear();
      widget.onActivado?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Suscripción activada.'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      setState(() => _errorLocal = auth.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _clave,
          obscureText: true,
          enabled: !_enviando,
          decoration: const InputDecoration(
            labelText: 'Clave de suscripción',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _activar(),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _duracion,
          // El desplegable reparte su ancho en vez de medirse por el ítem
          // más largo: con etiquetas largas (y la fuente ancha de los
          // tests) el contenido desbordaba su caja.
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Duración',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'minuto', child: Text('1 minuto')),
            DropdownMenuItem(value: 'semana', child: Text('1 semana')),
            DropdownMenuItem(value: 'mes', child: Text('1 mes')),
            DropdownMenuItem(value: 'siempre', child: Text('Para siempre')),
          ],
          onChanged: _enviando
              ? null
              : (valor) => setState(() => _duracion = valor ?? 'semana'),
        ),
        const SizedBox(height: 12),
        if (_errorLocal != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _errorLocal!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        FilledButton.icon(
          onPressed: _enviando ? null : _activar,
          icon: _enviando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_open),
          label: Text(_enviando ? 'Activando…' : 'Activar'),
        ),
      ],
    );
  }
}
