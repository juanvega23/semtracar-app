class InvoiceItem {
  final String? id;
  final String packageId;
  final String description;
  final double amount;

  InvoiceItem({
    this.id,
    required this.packageId,
    required this.description,
    required this.amount,
  });

  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceItem(
      id: map['id'],
      packageId: map['package_id'],
      description: map['description'],
      amount: (map['amount'] as num).toDouble(),
    );
  }
}

class Payment {
  final String? id;
  final String invoiceId;
  final double amount;
  final String method;
  final String? reference;
  final String? bankName;
  final DateTime paidAt;

  Payment({
    this.id,
    required this.invoiceId,
    required this.amount,
    required this.method,
    this.reference,
    this.bankName,
    DateTime? paidAt,
  }) : paidAt = paidAt ?? DateTime.now();

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'],
      invoiceId: map['invoice_id'],
      amount: (map['amount'] as num).toDouble(),
      method: map['method'],
      reference: map['reference'],
      bankName: map['bank_name'],
      paidAt: DateTime.parse(map['paid_at']).toLocal(),
    );
  }

  static String methodLabel(String method) {
    switch (method) {
      case 'efectivo':
        return 'Efectivo';
      case 'transferencia':
        return 'Transferencia';
      case 'tarjeta_datafono':
        return 'Tarjeta (datáfono)';
      case 'tarjeta_online':
        return 'Tarjeta (en línea)';
      case 'contra_entrega':
        return 'Contra entrega';
      default:
        return method;
    }
  }
}

class Invoice {
  final String id;
  final String documentType;
  final int invoiceNumber;
  final String userId;
  final double subtotal;
  final double taxAmount;
  final double total;
  final String status;
  final DateTime createdAt;
  final List<InvoiceItem> items;
  final List<Payment> payments;
  final bool hasDelivery;
  final String? deliveryAddress;
  final double deliveryCost;
  final String? issuedByName;
  final String deliveryChoice; // pendiente | solicitado | rechazado

  Invoice({
    required this.id,
    required this.documentType,
    required this.invoiceNumber,
    required this.userId,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.status,
    required this.createdAt,
    this.items = const [],
    this.payments = const [],
    this.hasDelivery = false,
    this.deliveryAddress,
    this.deliveryCost = 0,
    this.issuedByName,
    this.deliveryChoice = 'pendiente',
  });

  double get paidAmount => payments.fold(0.0, (sum, p) => sum + p.amount);
  double get balance => total - paidAmount;

  String get displayNumber =>
      'REC-${invoiceNumber.toString().padLeft(5, '0')}';

  factory Invoice.fromMap(Map<String, dynamic> map) {
    final itemsRaw = map['invoice_items'] as List? ?? [];
    final paymentsRaw = map['payments'] as List? ?? [];
    final issuer = map['issuer'] as Map<String, dynamic>?;
    return Invoice(
      id: map['id'],
      documentType: map['document_type'] ?? 'recibo',
      invoiceNumber: map['invoice_number'] ?? 0,
      userId: map['user_id'],
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
      status: map['status'] ?? 'pendiente',
      createdAt: DateTime.parse(map['created_at']).toLocal(),
      items: itemsRaw.map((m) => InvoiceItem.fromMap(m)).toList(),
      payments: paymentsRaw.map((m) => Payment.fromMap(m)).toList(),
      hasDelivery: map['has_delivery'] ?? false,
      deliveryAddress: map['delivery_address'],
      deliveryCost: (map['delivery_cost'] as num?)?.toDouble() ?? 0,
      issuedByName: issuer != null
          ? '${issuer['name']} ${issuer['last_name']}'
          : null,
      deliveryChoice: map['delivery_choice'] ?? 'pendiente',
    );
  }
}
