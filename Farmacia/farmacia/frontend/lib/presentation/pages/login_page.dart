import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/ajustes_scope.dart';
import '../controllers/auth_controller.dart';

/// Pantalla de inicio de sesión.
///
/// Es la primera que ve el usuario (el árbol la muestra cuando no hay
/// sesión). El check **"Recordar mi usuario y contraseña"** viene marcado
/// por defecto: al entrar, el token, el usuario y la contraseña se guardan
/// en el equipo (localStorage en el navegador, archivo de preferencias en
/// el exe), así la próxima vez el formulario ya viene relleno y no hay que
/// escribir nada hasta que el usuario pulse "Cerrar sesión".
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usuario;
  late final TextEditingController _contrasena;
  // Viene marcado: el login guarda usuario y contraseña por defecto para
  // que la próxima vez el formulario aparezca relleno.
  bool _recordar = true;
  bool _verContrasena = false;

  @override
  void initState() {
    super.initState();
    // Autocompletado de la sesión anterior y check "Recordarme" activo.
    final auth = context.read<AuthController>();
    _usuario = TextEditingController(text: auth.usuarioGuardado);
    _contrasena = TextEditingController(text: auth.contrasenaGuardada);
    _recordar = true;
  }

  @override
  void dispose() {
    _usuario.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    await context.read<AuthController>().iniciarSesion(
      usuario: _usuario.text,
      contrasena: _contrasena.text,
      recuerdame: _recordar,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Escucha los cambios: spinner del botón y mensaje de error del login.
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          final conMarca = ancho >= 900;

          final formulario = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _TarjetaLogin(
                  auth: auth,
                  formKey: _formKey,
                  usuario: _usuario,
                  contrasena: _contrasena,
                  recordar: _recordar,
                  verContrasena: _verContrasena,
                  // Sin panel lateral solo se pinta la tarjeta: ahí se ve la
                  // marca. Con panel, la marca ya ocupa la mitad izquierda.
                  mostrarMarca: !conMarca,
                  onRecordar: (valor) => setState(() => _recordar = valor),
                  onVerContrasena: () =>
                      setState(() => _verContrasena = !_verContrasena),
                  onEnviar: _enviar,
                ),
              ),
            ),
          );

          if (!conMarca) return formulario;

          return Row(
            children: [
              const Expanded(child: _PanelMarca()),
              Expanded(child: formulario),
            ],
          );
        },
      ),
    );
  }
}

/// Panel izquierdo (pantallas anchas): marca de la farmacia.
class _PanelMarca extends StatelessWidget {
  const _PanelMarca();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      color: AppColors.sidebarBg,
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.brandGreen,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.local_pharmacy_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            AjustesScope.de(context).valor(Ajustes.nombreFarmacia),
            style: const TextStyle(
              color: AppColors.textOnDark,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Inventario, ventas y facturación de la farmacia.\n'
            'Inicia sesión para acceder al panel.',
            style: TextStyle(
              color: AppColors.textOnDarkMuted,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta con el formulario de acceso.
class _TarjetaLogin extends StatelessWidget {
  const _TarjetaLogin({
    required this.auth,
    required this.formKey,
    required this.usuario,
    required this.contrasena,
    required this.recordar,
    required this.verContrasena,
    required this.onRecordar,
    required this.onVerContrasena,
    required this.onEnviar,
    required this.mostrarMarca,
  });

  final AuthController auth;
  final GlobalKey<FormState> formKey;
  final TextEditingController usuario;
  final TextEditingController contrasena;
  final bool recordar;
  final bool verContrasena;
  final ValueChanged<bool> onRecordar;
  final VoidCallback onVerContrasena;
  final VoidCallback onEnviar;

  /// `true` cuando la tarjeta se pinta sola (pantalla estrecha) y debe
  /// llevar su propia marca; `false` si ya está junto al panel de marca.
  final bool mostrarMarca;

  @override
  Widget build(BuildContext context) {
    final ocupado = auth.ocupado;
    final error = auth.error;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        // Transparente: da al `ListTile` (el check "Recordarme") el `Material`
        // que exige para pintar su ripple; el fondo lo pone el contenedor.
        color: Colors.transparent,
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Solo se ve la marca en pantallas estrechas (sin panel lateral):
              // la decide el `LayoutBuilder` y llega como [mostrarMarca].
              if (mostrarMarca) ...[
                Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.brandGreen,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.local_pharmacy_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              const Center(
                child: Text(
                  'Iniciar sesión',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Accede con tu usuario de la farmacia',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: usuario,
                enabled: !ocupado,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (valor) {
                  final texto = valor?.trim() ?? '';
                  if (texto.isEmpty) return 'Escribe tu usuario';
                  if (texto.length < 4) return 'Mínimo 4 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: contrasena,
                enabled: !ocupado,
                obscureText: !verContrasena,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => onEnviar(),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: verContrasena
                        ? 'Ocultar contraseña'
                        : 'Mostrar contraseña',
                    onPressed: ocupado ? null : onVerContrasena,
                    icon: Icon(
                      verContrasena
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (valor) => (valor == null || valor.isEmpty)
                    ? 'Escribe tu contraseña'
                    : null,
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                value: recordar,
                onChanged: ocupado
                    ? null
                    : (valor) => onRecordar(valor ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Recordar mi usuario y contraseña',
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
                subtitle: const Text(
                  'Entra sin volver a escribirlos hasta que cierres sesión.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.negativeRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 18,
                        color: AppColors.negativeRed,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.negativeRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: ocupado ? null : onEnviar,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.brandGreen.withValues(
                      alpha: 0.6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: ocupado
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Entrar',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
