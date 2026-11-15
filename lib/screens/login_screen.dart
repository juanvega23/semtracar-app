import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:testapp/services/database_helper.dart';
import 'package:testapp/services/notification_service.dart';

import 'admin_home_screen.dart';
import 'home_screen.dart';
import 'repartidor_home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? message;

  const LoginScreen({Key? key, this.message}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  int _failedAttempts = 0;
  bool _isBlocked = false;
  int _remainingSeconds = 0;
  bool _obscurePassword = true;
  Timer? _timer;

  final _formKey = GlobalKey<FormState>();
  final _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  @override
  void initState() {
    super.initState();

    if (widget.message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            backgroundColor: Colors.green,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.message!,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startTimer() {
    final blockLevel = _failedAttempts ~/ 3;
    final blockTime = 30 * blockLevel;

    setState(() {
      _isBlocked = true;
      _remainingSeconds = blockTime;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
        setState(() => _isBlocked = false);
      }
    });
  }

  void _showSecurityMessage(String message, bool isError) {
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.fixed,
        backgroundColor: isError ? Colors.orange : Colors.green,
        content: Row(
          children: [
            Icon(
              isError ? Icons.warning : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _forgotPassword() async {
    final TextEditingController resetEmailController = TextEditingController();
    final resetFormKey = GlobalKey<FormState>();
    bool isSending = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Column(
                children: [
                  Icon(Icons.lock_reset, color: Color(0xFFFA4B0C), size: 48),
                  SizedBox(height: 8),
                  Text(
                    'Recuperar contraseña',
                    style: TextStyle(
                      color: Color(0xFF12327F),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              content: Form(
                key: resetFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ingresa tu correo y te enviaremos un enlace para restablecer tu contraseña.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: resetEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(
                          Icons.alternate_email,
                          color: Color(0xFFFA4B0C),
                        ),
                        hintText: 'Correo electrónico',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          // <- agrega esto
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFFA4B0C),
                            width: 1.3,
                          ),
                        ),
                      ),

                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingrese su correo';
                        }
                        if (!_emailRegex.hasMatch(value)) {
                          return 'Correo inválido';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSending ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: isSending ? Colors.grey.shade300 : Colors.grey,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors:
                          isSending
                              ? [Colors.grey, Colors.grey.shade600]
                              : const [Color(0xFF12327F), Color(0xFFFA4B0C)],
                    ),
                  ),
                  child: TextButton(
                    onPressed:
                        isSending
                            ? null
                            : () async {
                              if (!resetFormKey.currentState!.validate())
                                return;

                              setDialogState(() => isSending = true);

                              try {
                                final email = resetEmailController.text.trim();

                                await Supabase.instance.client.auth
                                    .resetPasswordForEmail(
                                      email,
                                      redirectTo:
                                          'com.example.testapp://reset-callback/',
                                    );

                                Navigator.pop(context);

                                _showSecurityMessage(
                                  'Si el correo está registrado, recibirás un enlace en $email',
                                  false,
                                );
                              } catch (e) {
                                setDialogState(() => isSending = false);
                                Navigator.pop(context);

                                _showSecurityMessage(
                                  'Error al enviar el correo: ${e.toString()}',
                                  true,
                                );
                              }
                            },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child:
                        isSending
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : const Text(
                              'Enviar',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate() || _isBlocked) return;

    final nav = Navigator.of(context);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      final user = await _dbHelper.validateUser(email, password);

      if (user != null) {
        setState(() => _failedAttempts = 0);

        // Inicializa notificaciones y liga el token a esta cuenta SIN bloquear
        // el login: la navegación es inmediata y el token se guarda en segundo
        // plano (requestPermission + getToken pueden tardar varios segundos).
        unawaited(
          NotificationService.initialize().then(
            (_) => NotificationService.refreshTokenForCurrentUser(),
          ),
        );

        final roleLabel =
            user.role == 'admin'
                ? ' Administrador'
                : user.role == 'almacen'
                ? ' Encargado de almacén'
                : user.role == 'repartidor'
                ? ' Repartidor'
                : '';
        _showSecurityMessage('¡Bienvenido$roleLabel!', false);

        Widget destination;
        if (user.role == 'admin' || user.role == 'almacen') {
          destination = AdminHomeScreen();
        } else if (user.role == 'repartidor') {
          destination = const RepartidorHomeScreen();
        } else {
          destination = HomeScreen(userId: user.id);
        }

        nav.pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => destination,
            transitionsBuilder:
                (_, animation, __, child) =>
                    FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      } else {
        setState(() => _failedAttempts++);

        final remaining = 3 - (_failedAttempts % 3);

        if (_failedAttempts % 3 == 0) {
          final blockLevel = _failedAttempts ~/ 3;
          final blockTime = 30 * blockLevel;

          _showSecurityMessage(
            'Demasiados intentos. Espere $blockTime segundos.',
            true,
          );

          _startTimer();
        } else {
          _showSecurityMessage(
            'Credenciales incorrectas. Intentos restantes: $remaining',
            true,
          );
        }
      }
    } catch (e) {
      _showSecurityMessage('Error del sistema: ${e.toString()}', true);
    }
  }

  InputDecoration _inputDecoration({
    required IconData icon,
    required String hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: const Color(0xFFFA4B0C)),
      suffixIcon: suffixIcon,
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade600),
      filled: true,
      fillColor: Colors.white.withOpacity(0.84),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.80), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFA4B0C), width: 1.3),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.orange, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.orange, width: 1.3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Fondo
          Positioned.fill(
            child: Image.asset(
              'assets/images/login_background.png',
              fit: BoxFit.cover,
            ),
          ),

          // Capa suave para mejorar lectura
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.08)),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Logo suelto sobre el fondo, sin placa: el PNG tiene
                    // transparencia, asi que se apoya directo en el fondo.
                    Image.asset(
                      'assets/images/logo.png',
                      height: 66,
                      fit: BoxFit.contain,
                    ),

                    const SizedBox(height: 36),

                    // Card con sombra externa + borde glass
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.10),
                            blurRadius: 24,
                            spreadRadius: 0,
                            offset: const Offset(0, 9),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withOpacity(0.80),
                                  Colors.white.withOpacity(0.30),
                                  Colors.white.withOpacity(0.08),
                                  Colors.white.withOpacity(0.48),
                                ],
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22.5),
                                color: Colors.white.withOpacity(0.24),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.22),
                                  width: 0.8,
                                ),
                              ),
                              child: Column(
                                children: [
                                  // Email
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    style: const TextStyle(
                                      color: Colors.black87,
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Ingrese su email';
                                      }
                                      if (!_emailRegex.hasMatch(value)) {
                                        return 'Email inválido';
                                      }
                                      return null;
                                    },
                                    decoration: _inputDecoration(
                                      icon: Icons.alternate_email,
                                      hint: "Correo electrónico",
                                    ),
                                  ),

                                  const SizedBox(height: 20),

                                  // Contraseña
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    style: const TextStyle(
                                      color: Colors.black87,
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Ingrese su contraseña';
                                      }
                                      if (value.length < 8) {
                                        return 'Mínimo 8 caracteres';
                                      }
                                      return null;
                                    },
                                    decoration: _inputDecoration(
                                      icon: Icons.lock_outline,
                                      hint: "Contraseña",
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                          color: Colors.grey,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _forgotPassword,
                                      child: const Text(
                                        '¿Olvidaste tu contraseña?',
                                        style: TextStyle(
                                          color: Color(0xFFFA4B0C),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // Botón iniciar sesión
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient:
                                          _isBlocked
                                              ? LinearGradient(
                                                colors: [
                                                  Colors.grey,
                                                  Colors.grey.shade700,
                                                ],
                                              )
                                              : const LinearGradient(
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                                colors: [
                                                  Color(0xFF12327F),
                                                  Color(0xFF8E2A3D),
                                                  Color(0xFFFA4B0C),
                                                ],
                                              ),
                                      boxShadow:
                                          _isBlocked
                                              ? null
                                              : [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFFFA4B0C,
                                                  ).withOpacity(0.30),
                                                  blurRadius: 18,
                                                  offset: const Offset(0, 7),
                                                ),
                                              ],
                                    ),
                                    child: TextButton(
                                      onPressed: _isBlocked ? null : _login,
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        foregroundColor: Colors.white,
                                        disabledForegroundColor: Colors.white
                                            .withOpacity(0.9),
                                      ),
                                      child: Text(
                                        _isBlocked
                                            ? "BLOQUEADO ($_remainingSeconds)"
                                            : "INICIAR SESIÓN",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RegisterScreen(),
                          ),
                        );
                      },
                      child: RichText(
                        text: TextSpan(
                          text: "¿No tienes cuenta? ",
                          style: TextStyle(color: Colors.grey.shade700),
                          children: const [
                            TextSpan(
                              text: "Regístrate",
                              style: TextStyle(
                                color: Color(0xFFFA4B0C),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
