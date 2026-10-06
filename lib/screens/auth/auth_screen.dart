import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../services/session_scope.dart';
import '../../theme.dart';

/// Abre la pantalla de alta/entrada. Devuelve true si se consiguió entrar.
///
/// Vive aquí, junto a la pantalla que abre, y no en el shell: la piden tres
/// sitios distintos —el corazón de una tarjeta, la pestaña Saved y el botón de
/// desbloquear de la ficha—, y ponerla en el shell obligaba a que esas pantallas
/// importaran al shell que las contiene. El ciclo compila, pero se lee mal.
Future<bool> pedirEntrar(BuildContext context,
    {String? motivo, bool registro = false}) async {
  final entro = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => AuthScreen(motivo: motivo, empezarEnRegistro: registro),
    ),
  );
  return entro == true;
}

/// Crear cuenta y entrar, en una sola pantalla.
///
/// Una pantalla y no dos porque los dos formularios piden lo mismo —correo y
/// contraseña— y separarlos obliga a quien se equivoca de lado a navegar para
/// escribirlo otra vez. El conmutador de arriba cambia el modo sin perder lo
/// escrito.
///
/// Se abre como una ruta normal y se cierra con `Navigator.pop(true)` cuando se
/// consigue entrar, para que quien la abrió sepa que puede seguir con lo que
/// estaba haciendo.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.motivo, this.empezarEnRegistro = false});

  /// Por qué se está pidiendo la cuenta: "Sign in to save this place". Se
  /// enseña arriba. Sin esto, a quien pulsa un corazón le aparece un formulario
  /// sin explicación.
  final String? motivo;
  final bool empezarEnRegistro;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formulario = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  late bool _registro = widget.empezarEnRegistro;
  bool _enviando = false;
  bool _verPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formulario.currentState!.validate()) return;

    setState(() {
      _enviando = true;
      _error = null;
    });

    final sesion = SessionScope.sin(context);
    final email = _email.text.trim();

    try {
      if (_registro) {
        await sesion.registrar(email, _password.text);
      } else {
        await sesion.entrar(email, _password.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        // El 409 del registro tiene una salida obvia, así que se ofrece en vez
        // de dejar al usuario mirando "email already registered".
        _error = e.statusCode == 409
            ? 'That email already has an account. Try signing in instead.'
            : e.message;
        if (e.statusCode == 409) _registro = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        // Sin red, el mensaje de la excepción de socket es ilegible para
        // cualquiera que no programe. Se dice lo que pasa.
        _error = 'Could not reach the server. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_registro ? 'Create account' : 'Sign in')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Form(
            key: _formulario,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.motivo != null) ...[
                  Text(
                    widget.motivo!,
                    style: const TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: AztecTheme.tintaSuave),
                  ),
                  const SizedBox(height: 22),
                ],

                _Conmutador(
                  registro: _registro,
                  onCambio: _enviando
                      ? null
                      : (v) => setState(() {
                            _registro = v;
                            _error = null;
                          }),
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _email,
                  enabled: !_enviando,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  // Sin esto, iOS pone mayúscula a la primera letra del correo.
                  textCapitalization: TextCapitalization.none,
                  autofillHints: const [AutofillHints.email],
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Enter your email';
                    // A propósito flojo: quien valida el correo de verdad es el
                    // servidor, y una expresión regular estricta rechaza
                    // direcciones válidas raras.
                    if (!t.contains('@') || !t.contains('.')) {
                      return 'That does not look like an email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _password,
                  enabled: !_enviando,
                  obscureText: !_verPassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    helperText:
                        _registro ? 'At least 8 characters' : null,
                    suffixIcon: IconButton(
                      icon: Icon(_verPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _verPassword = !_verPassword),
                      tooltip: _verPassword ? 'Hide password' : 'Show password',
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _enviar(),
                  autofillHints: [
                    _registro
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  validator: (v) {
                    final t = v ?? '';
                    if (t.isEmpty) return 'Enter your password';
                    // 8 es el mínimo del servidor. Comprobarlo aquí ahorra un
                    // viaje y un 400; el que manda sigue siendo el servidor.
                    if (_registro && t.length < 8) {
                      return 'At least 8 characters';
                    }
                    return null;
                  },
                ),

                if (_error != null) ...[
                  const SizedBox(height: 18),
                  _Aviso(texto: _error!),
                ],

                const SizedBox(height: 26),
                FilledButton(
                  onPressed: _enviando ? null : _enviar,
                  style: FilledButton.styleFrom(
                    backgroundColor: AztecTheme.coral,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: _enviando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          _registro ? 'Create account' : 'Sign in',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                ),

                const SizedBox(height: 20),
                const Text(
                  'Your account keeps your saved places and your unlock across '
                  'devices.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AztecTheme.tintaSuave),
                ),

                // Google y Apple todavía no: los dos necesitan configuración en
                // sus consolas y el backend aún no tiene el endpoint. No se
                // pinta un botón que no funciona.
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Conmutador extends StatelessWidget {
  const _Conmutador({required this.registro, this.onCambio});

  final bool registro;
  final ValueChanged<bool>? onCambio;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AztecTheme.linea),
      ),
      child: Row(
        children: [
          _opcion(context, 'Sign in', !registro, () => onCambio?.call(false)),
          _opcion(context, 'Create account', registro, () => onCambio?.call(true)),
        ],
      ),
    );
  }

  Widget _opcion(
      BuildContext context, String texto, bool activa, VoidCallback alPulsar) {
    return Expanded(
      child: GestureDetector(
        onTap: onCambio == null ? null : alPulsar,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: activa ? AztecTheme.coral : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: activa ? Colors.white : AztecTheme.tintaSuave,
            ),
          ),
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AztecTheme.coral.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AztecTheme.coral.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 19, color: AztecTheme.coral),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.4, color: AztecTheme.tinta),
            ),
          ),
        ],
      ),
    );
  }
}
