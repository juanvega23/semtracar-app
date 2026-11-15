import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:testapp/services/database_helper.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  bool _obscurePassword = true;

  static final RegExp _nameRegExp = RegExp(r'^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\- ]+$');

  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  static final RegExp _passwordRegExp = RegExp(
    r'^(?=.*[A-Z])(?=.*[!@#$%^&*(),.?\":{}|<>]).{8,}$',
  );

  @override
  void dispose() {
    _nameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFA4B0C)),
            ),
          ),
    );

    try {
      final authResponse = await _dbHelper.registerUser(
        name,
        lastName,
        email,
        password,
      );

      if (authResponse.user == null) {
        throw 'Error al registrar el usuario';
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      _showSuccessSnackBar('¡Registro exitoso! Verifica tu email');

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen()),
      );
    } catch (e) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        final errorMsg = e.toString();

        if (errorMsg.contains('email')) {
          _emailController.clear();
        } else if (errorMsg.contains('nombre') ||
            errorMsg.contains('apellido')) {
          _nameController.clear();
          _lastNameController.clear();
        } else if (errorMsg.contains('contraseña') ||
            errorMsg.contains('password')) {
          _passwordController.clear();
        }

        _showErrorSnackBar(errorMsg);
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: Colors.green,
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: Colors.red,
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required IconData icon,
    required String hint,
    Widget? suffixIcon,
    String? helperText,
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
      helperText: helperText,
      helperMaxLines: 2,
      helperStyle: TextStyle(fontSize: 11, color: Colors.grey.shade700),
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
                            child: Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  // Nombre
                                  TextFormField(
                                    controller: _nameController,
                                    style: const TextStyle(
                                      color: Colors.black87,
                                    ),
                                    decoration: _inputDecoration(
                                      icon: Icons.person_outline,
                                      hint: "Nombre",
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Ingrese su nombre';
                                      }
                                      if (!_nameRegExp.hasMatch(value)) {
                                        return 'Solo se permiten letras y espacios';
                                      }
                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 20),

                                  // Apellido
                                  TextFormField(
                                    controller: _lastNameController,
                                    style: const TextStyle(
                                      color: Colors.black87,
                                    ),
                                    decoration: _inputDecoration(
                                      icon: Icons.people_alt_outlined,
                                      hint: "Apellido",
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Ingrese su apellido';
                                      }
                                      if (!_nameRegExp.hasMatch(value)) {
                                        return 'Solo se permiten letras y espacios';
                                      }
                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 20),

                                  // Email
                                  TextFormField(
                                    controller: _emailController,
                                    style: const TextStyle(
                                      color: Colors.black87,
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: _inputDecoration(
                                      icon: Icons.alternate_email,
                                      hint: "Correo electrónico",
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Ingrese su correo electrónico';
                                      }
                                      if (!_emailRegExp.hasMatch(value)) {
                                        return 'Correo electrónico inválido';
                                      }
                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 20),

                                  // Contraseña
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    style: const TextStyle(
                                      color: Colors.black87,
                                    ),
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
                                      helperText:
                                          'Mín. 8 caracteres, 1 mayúscula y 1 carácter especial (!@#\$%...)',
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Ingrese su contraseña';
                                      }
                                      if (!_passwordRegExp.hasMatch(value)) {
                                        return 'Mín. 8 caracteres, 1 mayúscula\ny 1 carácter especial (!@#\$%...)';
                                      }
                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 24),

                                  // Botón registrarse
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient: const LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: [
                                          Color(0xFF12327F),
                                          Color(0xFF8E2A3D),
                                          Color(0xFFFA4B0C),
                                        ],
                                      ),
                                      boxShadow: [
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
                                      onPressed: _submitForm,
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
                                      ),
                                      child: const Text(
                                        "REGISTRARSE",
                                        style: TextStyle(
                                          color: Colors.white,
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
                  ),

                  const SizedBox(height: 20),

                  // Ir a login
                  TextButton(
                    onPressed:
                        () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => LoginScreen()),
                        ),
                    child: RichText(
                      text: TextSpan(
                        text: "¿Ya tienes cuenta? ",
                        style: TextStyle(color: Colors.grey.shade700),
                        children: const [
                          TextSpan(
                            text: "Inicia sesión",
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
        ],
      ),
    );
  }
}
