class Package {
  final String? id;
  final String trackingCode;
  final int shippingMethodId;
  final int packageTypeId;
  final String userId;
  final DateTime createdAt;
  final double weight;
  final double price;
  final bool isPaid;
  final String? shippingMethodName;
  final String? packageTypeName;
  final List<Map<String, dynamic>>? statusHistory;
  
  // Getter para compatibilidad con código que usa statusTimeline
  List<Map<String, dynamic>> get statusTimeline => statusHistory ?? [];

  Package({
    this.id,
    required this.trackingCode,
    required this.shippingMethodId,
    required this.packageTypeId,
    required this.userId,
    required this.weight,
    required this.price,
    this.isPaid = false,
    this.shippingMethodName,
    this.packageTypeName,
    this.statusHistory,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? DateTime.now()).toUtc();  // Convertir a UTC al crear

  factory Package.fromMap(Map<String, dynamic> map) {
    return Package(
      id: map['id'],
      trackingCode: map['tracking_code'],
      shippingMethodId: map['shipping_method_id'],
      packageTypeId: map['package_type_id'],
      userId: map['user_id'],
      weight: map['weight']?.toDouble() ?? 0.0,
      price: map['price']?.toDouble() ?? 0.0,
      isPaid: map['is_paid'] ?? false,
      shippingMethodName: map['shipping_methods']?['name'],
      packageTypeName: map['package_types']?['name'],
      statusHistory: _parseStatusHistory(map['status_history']),
      createdAt: DateTime.parse(map['created_at']).toUtc(),  // Convertir a UTC
    );
  }

  static List<Map<String, dynamic>>? _parseStatusHistory(dynamic history) {
    if (history == null) return null;
    
    if (history is List) {
      final parsed = history.map((item) {
        return {
          'status': item['status_types']?['name'] ?? 'Desconocido',
          'date': DateTime.parse(item['created_at']).toUtc().toIso8601String(),
          'location': item['notes'],
        };
      }).toList();

      parsed.sort((a, b) =>
          DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));

      return parsed;
    }

    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'tracking_code': trackingCode,
      'shipping_method_id': shippingMethodId,
      'package_type_id': packageTypeId,
      'user_id': userId,
      'weight': weight,
      'price': price,
      'is_paid': isPaid,
      'created_at': createdAt.toIso8601String(),
    };
  }

}