import 'package:flutter/material.dart';

import '../../core/errors/failure.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/recurso_controller.dart';

/// Diálogo para restablecer la contraseña de un usuario.
///
/// La API exige, junto a la contraseña nueva, la `claveAdmin` de la cuenta
/// que hace el cambio (la verifica el backend): sin ella no se escribe nada.
///
/// Devuelve `true` al guardarse (para que quien lo abre muestre su alerta
/// de éxito) y `null` si se cancela o falla (el error se pinta dentro).
Future<bool?> mostrarRestablecerContrasena(
  BuildContext context, {
  required UsuariosController usuarios,
  required Recurso usuario,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _DialogoRestablecer(usuarios: usuarios, usuario: usuario),
);

class _DialogoRestablecer extends StatefulWidget {
  const _DialogoRestablecer({required this.usuarios, required this.usuario});

  final UsuariosController usuarios;
  final Recurso usuario;

  @override
  State<_DialogoRestablecer> createState() => _DialogoRestablecerState();
}

class _DialogoRestablecerState extends State<_DialogoRestablecer> {
  final _formKey = GlobalKey<FormState>();
  final _nueva = TextEditingController();
  final _repetir = TextEditingController();
  final _claveAdmin = TextEditingController();
  String? _error;
  bool _enviando = false;

  @override
  void dispose() {
    _nueva.dispose();
    _repetir.dispose();
    _claveAdmin.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _enviando = true);
    try {
      await widget.usuarios.actualizar(widget.usuario.id, {
        'contrasena': _nueva.text.trim(),
        'claveAdmin': _claveAdmin.text,
      });
      if (mounted) Navigator.pop(context, true);
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _error = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      title: Text(
        'Restablecer contraseña',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cuenta: ${widget.usuario.texto('nombreUsuario')}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nueva,
                enabled: !_enviando,
                obscureText: true,
                maxLength: 72,
                decoration: const InputDecoration(
                  labelText: 'Nueva contraseña *',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                validator: (valor) {
                  final texto = (valor ?? '').trim();
                  if (texto.isEmpty) return 'Escribe la contraseña nueva';
                  if (texto.length < 8) return 'Mínimo 8 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _repetir,
                enabled: !_enviando,
                obscureText: true,
                maxLength: 72,
                decoration: const InputDecoration(
                  labelText: 'Repetir contraseña *',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                validator: (valor) {
                  if ((valor ?? '').trim() != _nueva.text.trim()) {
                    return 'Las contraseñas no coinciden';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _claveAdmin,
                enabled: !_enviando,
                obscureText: true,
                maxLength: 255,
                decoration: const InputDecoration(
                  labelText: 'Tu clave de administrador *',
                  helperText: 'Confirma tu identidad para autorizar el cambio',
                  border: OutlineInputBorder(),
                ),
                validator: (valor) {
                  if ((valor ?? '').isEmpty) return 'Confirma tu clave';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.negativeRed,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _enviando ? null : _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _enviando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Restablecer'),
        ),
      ],
    );
  }
}
