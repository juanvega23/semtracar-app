class User {
  final String id;
  final String name;
  final String lastName;
  final String email;
  final String casillero;
  final bool isAdmin;
  final String? address;
  final String? phone;
  final String role; // 'admin' | 'cliente' | 'repartidor'
  final bool isAvailable;

  User({
    required this.id,
    required this.name,
    required this.lastName,
    required this.email,
    required this.casillero,
    required this.isAdmin,
    this.address,
    this.phone,
    this.role = 'cliente',
    this.isAvailable = false,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      name: map['name'],
      lastName: map['last_name'],
      email: map['email'],
      casillero: map['casillero'] ?? '',
      isAdmin: map['is_admin'] ?? false,
      address: map['address'],
      phone: map['phone'],
      role: map['role'] ?? (map['is_admin'] == true ? 'admin' : 'cliente'),
      isAvailable: map['is_available'] ?? false,
    );
  }
}