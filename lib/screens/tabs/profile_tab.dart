import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/database_helper.dart';
import '../../models/user.dart' as app_models;
import '../login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileTab extends StatefulWidget {
  @override
  _ProfileTabState createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late app_models.User _currentUser;
  int _packageCount = 0;
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Usuario no autenticado');

      final userMap =
          await _supabase.from('users').select().eq('id', userId).single();

      _currentUser = app_models.User.fromMap(userMap);
      final packages = await _dbHelper.getPackagesByUser(_currentUser.id);

      setState(() {
        _packageCount = packages.length;
        _nameController.text = _currentUser.name;
        _lastNameController.text = _currentUser.lastName;
        _emailController.text = _currentUser.email;
        _addressController.text = _currentUser.address ?? '';
        _phoneController.text = _currentUser.phone ?? '';
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
      }
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUpdating = true);

    try {
      final newName = _nameController.text.trim();
      final newLastName = _lastNameController.text.trim();
      final newEmail = _emailController.text.trim();

      if (newName != _currentUser.name ||
          newLastName != _currentUser.lastName) {
        final nameExists = await _dbHelper.checkNameLastNameExists(
          newName,
          newLastName,
        );
        if (nameExists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ya existe un usuario con ese nombre y apellido'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      if (newEmail != _currentUser.email) {
        final emailExists = await _dbHelper.checkEmailExists(newEmail);
        if (emailExists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El correo electrónico ya está en uso'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        await _supabase.auth.updateUser(UserAttributes(email: newEmail));
      }

      final newAddress = _addressController.text.trim();
      final newPhone = _phoneController.text.trim();
      await _supabase
          .from('users')
          .update({
            'name': newName,
            'last_name': newLastName,
            'email': newEmail,
            'address': newAddress.isEmpty ? null : newAddress,
            'phone': newPhone.isEmpty ? null : newPhone,
          })
          .eq('id', _currentUser.id);

      // Cambiar contraseña si se llenaron los campos
      if (_newPasswordController.text.isNotEmpty) {
        try {
          await _supabase.auth.signInWithPassword(
            email: _currentUser.email,
            password: _currentPasswordController.text,
          );

          await _supabase.auth.updateUser(
            UserAttributes(password: _newPasswordController.text),
          );

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contraseña actualizada con éxito'),
              backgroundColor: Colors.green,
            ),
          );
        } on AuthException catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e.message.contains('Invalid login')
                    ? 'La contraseña actual es incorrecta'
                    : 'Error al actualizar la contraseña: ${e.message}',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        _currentPasswordController.clear();
        _newPasswordController.clear();
      }

      setState(() {
        _currentUser = app_models.User(
          id: _currentUser.id,
          name: newName,
          lastName: newLastName,
          email: newEmail,
          casillero: _currentUser.casillero,
          isAdmin: _currentUser.isAdmin,
          address: newAddress.isEmpty ? null : newAddress,
          phone: newPhone.isEmpty ? null : newPhone,
        );
        _isEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil actualizado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  bool _isPasswordValid(String password) {
    final regex = RegExp(r'^(?=.*[A-Z])(?=.*[!@#\$&*~.,%^()\-_+=?]).{8,}$');
    return regex.hasMatch(password);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFA4B0C)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Info card ──────────────────────────────────────────────────
              Card(
                color: Colors.white,
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.confirmation_number,
                          color: Color(0xFFFA4B0C),
                        ),
                        title: const Text('Código de casillero'),
                        subtitle: Text(
                          _currentUser.casillero,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.inventory,
                          color: Color(0xFFFA4B0C),
                        ),
                        title: const Text('Paquetes asignados'),
                        subtitle: Text(
                          '$_packageCount',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Profile form card ──────────────────────────────────────────
              Card(
                color: Colors.white,
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Información personal',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFA4B0C),
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _nameController,
                        enabled: _isEditing,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor ingrese su nombre';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _lastNameController,
                        enabled: _isEditing,
                        decoration: const InputDecoration(
                          labelText: 'Apellido',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor ingrese su apellido';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _emailController,
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _addressController,
                        enabled: _isEditing,
                        maxLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Dirección de entrega',
                          hintText: 'Ej: Residencial Las Palmas, casa #15',
                          prefixIcon: Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder(),
                          helperText:
                              'Se usará para delivery de paquetes',
                          helperMaxLines: 1,
                        ),
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _phoneController,
                        enabled: _isEditing,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          hintText: 'Ej: 88887777',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                          counterText: '',
                          helperText: 'Para contactarte en el delivery',
                          helperMaxLines: 1,
                        ),
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              value.trim().length < 8) {
                            return 'El teléfono debe tener 8 dígitos';
                          }
                          return null;
                        },
                      ),

                      if (_isEditing) ...[
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _currentPasswordController,
                          obscureText: _obscureCurrentPassword,
                          decoration: InputDecoration(
                            labelText: 'Contraseña actual',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureCurrentPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey,
                              ),
                              onPressed:
                                  () => setState(
                                    () =>
                                        _obscureCurrentPassword =
                                            !_obscureCurrentPassword,
                                  ),
                            ),
                          ),
                          validator: (value) {
                            if (_newPasswordController.text.isNotEmpty &&
                                (value == null || value.isEmpty)) {
                              return 'Ingrese su contraseña actual';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: _obscureNewPassword,
                          decoration: InputDecoration(
                            labelText: 'Nueva contraseña (opcional)',
                            prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureNewPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey,
                              ),
                              onPressed:
                                  () => setState(
                                    () =>
                                        _obscureNewPassword =
                                            !_obscureNewPassword,
                                  ),
                            ),
                            helperText:
                                'Mín. 8 caracteres, 1 mayúscula y 1 carácter especial (!@#\$%...)',
                            helperMaxLines: 2,
                            helperStyle: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          validator: (value) {
                            if (value != null &&
                                value.isNotEmpty &&
                                !_isPasswordValid(value)) {
                              return 'Mín. 8 caracteres, 1 mayúscula\ny 1 carácter especial (!@#\$%...)';
                            }
                            return null;
                          },
                        ),
                      ],

                      const SizedBox(height: 20),

                      if (!_isEditing)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => setState(() => _isEditing = true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF12327F),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                            ),
                            child: const Text(
                              'EDITAR PERFIL',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                      if (_isEditing)
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed:
                                    _isUpdating
                                        ? null
                                        : () {
                                          _nameController.text =
                                              _currentUser.name;
                                          _lastNameController.text =
                                              _currentUser.lastName;
                                          _currentPasswordController.clear();
                                          _newPasswordController.clear();
                                          setState(() => _isEditing = false);
                                        },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                ),
                                child: const Text(
                                  'CANCELAR',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isUpdating ? null : _updateProfile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF12327F),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                ),
                                child:
                                    _isUpdating
                                        ? const CircularProgressIndicator(
                                          color: Colors.white,
                                        )
                                        : const Text(
                                          'GUARDAR',
                                          style: TextStyle(color: Colors.white),
                                        ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // ── Logout ─────────────────────────────────────────────────────
              ElevatedButton(
                onPressed: () async {
                  await _supabase.auth.signOut();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => LoginScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text(
                  'CERRAR SESIÓN',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
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
