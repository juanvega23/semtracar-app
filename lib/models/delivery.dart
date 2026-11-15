class Delivery {
  final String id;
  final String invoiceId;
  final String packageId;
  final String clientId;
  final String? delivererId;
  final String status;
  final String deliveryAddress;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? onTheWayAt;
  final DateTime? deliveredAt;
  final String? clientName;
  final String? clientPhone;
  final String? packageTracking;
  final int packageCount;
  final String? delivererName;
  final double? delivererLat;
  final double? delivererLng;
  final DateTime? locationUpdatedAt;
  final String? proofUrl; // foto de evidencia de entrega

  Delivery({
    required this.id,
    required this.invoiceId,
    required this.packageId,
    required this.clientId,
    this.delivererId,
    required this.status,
    required this.deliveryAddress,
    required this.createdAt,
    this.acceptedAt,
    this.onTheWayAt,
    this.deliveredAt,
    this.clientName,
    this.clientPhone,
    this.packageTracking,
    this.packageCount = 1,
    this.delivererName,
    this.delivererLat,
    this.delivererLng,
    this.locationUpdatedAt,
    this.proofUrl,
  });

  /// True si hay una ubicación del repartidor razonablemente reciente.
  bool get hasLiveLocation =>
      delivererLat != null &&
      delivererLng != null &&
      locationUpdatedAt != null;

  factory Delivery.fromMap(Map<String, dynamic> map) {
    final client = map['client'] as Map<String, dynamic>?;
    final deliverer = map['deliverer'] as Map<String, dynamic>?;
    // Preferir el nombre denormalizado en la fila (visible para el cliente sin
    // depender de RLS sobre users); si no, usar el join.
    String? delivererName = map['deliverer_name'] as String?;
    if ((delivererName == null || delivererName.trim().isEmpty) &&
        deliverer != null) {
      delivererName = '${deliverer['name']} ${deliverer['last_name']}';
    }
    // Igual para el cliente: preferir lo denormalizado (el repartidor no puede
    // leer la fila del cliente en users por RLS).
    String? clientName = map['client_name'] as String?;
    if ((clientName == null || clientName.trim().isEmpty) && client != null) {
      clientName = '${client['name']} ${client['last_name']}';
    }
    final String? clientPhone =
        (map['client_phone'] as String?) ?? client?['phone'];
    return Delivery(
      id: map['id'],
      invoiceId: map['invoice_id'],
      packageId: map['package_id'],
      clientId: map['client_id'],
      delivererId: map['deliverer_id'],
      status: map['status'] ?? 'disponible',
      deliveryAddress: map['delivery_address'] ?? '',
      createdAt: DateTime.parse(map['created_at']).toLocal(),
      acceptedAt: map['accepted_at'] != null
          ? DateTime.parse(map['accepted_at']).toLocal()
          : null,
      onTheWayAt: map['on_the_way_at'] != null
          ? DateTime.parse(map['on_the_way_at']).toLocal()
          : null,
      deliveredAt: map['delivered_at'] != null
          ? DateTime.parse(map['delivered_at']).toLocal()
          : null,
      clientName: (clientName != null && clientName.trim().isNotEmpty)
          ? clientName.trim()
          : null,
      clientPhone: (clientPhone != null && clientPhone.trim().isNotEmpty)
          ? clientPhone.trim()
          : null,
      packageTracking: map['package_tracking'] as String?,
      packageCount: (map['package_count'] as int?) ?? 1,
      delivererName:
          (delivererName != null && delivererName.trim().isNotEmpty)
              ? delivererName.trim()
              : null,
      delivererLat: (map['deliverer_lat'] as num?)?.toDouble(),
      delivererLng: (map['deliverer_lng'] as num?)?.toDouble(),
      locationUpdatedAt: map['location_updated_at'] != null
          ? DateTime.parse(map['location_updated_at']).toLocal()
          : null,
      proofUrl: map['proof_url'],
    );
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'disponible': return 'Disponible';
      case 'aceptado':   return 'Aceptado';
      case 'en_camino':  return 'En camino';
      case 'entregado':  return 'Entregado';
      case 'cancelado':  return 'Cancelado';
      default:           return status;
    }
  }
}
