import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/database_helper.dart';
import '../../models/package.dart';
import '../../models/invoice.dart';
import '../../models/delivery.dart';
import '../../models/user.dart' as app_models;

const _navy = Color(0xFF12327F);
const _orange = Color(0xFFFA4B0C);
const _green = Color(0xFF16A34A);
const _greenBg = Color(0xFFDCFCE7);
const _blueBg = Color(0xFFEFF6FF);
const _blue = Color(0xFF1D4ED8);

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  final DatabaseHelper _db = DatabaseHelper();
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Package> _packages = [];
  Map<String, Delivery> _deliveriesByPackageId = {};
  app_models.User? _currentUser;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final userMap =
          await _supabase.from('users').select().eq('id', userId).single();

      final allPackages = await _db.getCurrentUserPackages();
      final ready = allPackages.where((p) {
        final history = p.statusHistory ?? [];
        if (history.isEmpty) return false;
        return history.last['status'] == 'Listo para recoger';
      }).toList();

      final deliveries = await _db.getDeliveriesByClient(userId);
      final deliveryMap = <String, Delivery>{};
      for (final d in deliveries) {
        deliveryMap[d.packageId] = d;
      }

      if (!mounted) return;
      setState(() {
        _currentUser = app_models.User.fromMap(userMap);
        _packages = ready;
        _deliveriesByPackageId = deliveryMap;
      });
    } catch (e) {
      debugPrint('Error cargando historial: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showInvoice(Package package) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InvoiceSheet(db: _db, package: package),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: _orange)),
      );
    }

    if (_packages.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history_toggle_off,
                  size: 50, color: _navy.withValues(alpha: 0.3)),
              const SizedBox(height: 20),
              Text('No hay paquetes listos para recoger',
                  style: TextStyle(
                      fontSize: 16, color: _navy.withValues(alpha: 0.6))),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: _orange,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _packages.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final pkg = _packages[i];
            final delivery = _deliveriesByPackageId[pkg.id];
            return _PackageCard(
              package: pkg,
              user: _currentUser,
              delivery: delivery,
              onVerRecibo: () => _showInvoice(pkg),
            );
          },
        ),
      ),
    );
  }
}

// ─── Tarjeta de paquete ────────────────────────────────────────────────────────

class _PackageCard extends StatelessWidget {
  final Package package;
  final app_models.User? user;
  final Delivery? delivery;
  final VoidCallback onVerRecibo;

  const _PackageCard({
    required this.package,
    required this.user,
    required this.onVerRecibo,
    this.delivery,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.inventory_2_rounded,
                      color: _navy, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(package.trackingCode,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _navy)),
                      const SizedBox(height: 2),
                      Text(
                        package.packageTypeName ?? '',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                _PayBadge(isPaid: package.isPaid),
              ],
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 12),

            // ── Chips ────────────────────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(
                    icon: Icons.local_shipping_rounded,
                    label: package.shippingMethodName ?? ''),
                if (user != null)
                  _Chip(icon: Icons.inbox_rounded, label: user!.casillero),
                _Chip(
                  icon: Icons.calendar_today_outlined,
                  label: DateFormat('dd/MM/yyyy')
                      .format(package.createdAt.toLocal()),
                ),
              ],
            ),

            // ── Estado de delivery ────────────────────────────────────────────
            if (delivery != null) ...[
              const SizedBox(height: 12),
              _DeliveryStatusBadge(status: delivery!.status),
            ],

            const SizedBox(height: 14),

            // ── Precio + botones ──────────────────────────────────────────────
            Row(
              children: [
                Text(
                  '\$${package.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _navy),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: onVerRecibo,
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: const Text('Ver recibo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _navy,
                    side: const BorderSide(color: _navy),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Badge estado de delivery ──────────────────────────────────────────────────

class _DeliveryStatusBadge extends StatelessWidget {
  final String status;
  const _DeliveryStatusBadge({required this.status});

  String get _label {
    switch (status) {
      case 'disponible': return '🕐 Esperando repartidor';
      case 'aceptado':   return '✅ Repartidor asignado';
      case 'en_camino':  return '🛵 En camino a tu dirección';
      case 'entregado':  return '✅ Entregado';
      default:           return status;
    }
  }

  Color get _bg {
    switch (status) {
      case 'disponible': return const Color(0xFFFFF8EC);
      case 'aceptado':   return _blueBg;
      case 'en_camino':  return _blueBg;
      case 'entregado':  return _greenBg;
      default:           return Colors.grey.shade100;
    }
  }

  Color get _fg {
    switch (status) {
      case 'disponible': return const Color(0xFF854F0B);
      case 'aceptado':   return _blue;
      case 'en_camino':  return _blue;
      case 'entregado':  return _green;
      default:           return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: _bg, borderRadius: BorderRadius.circular(10)),
      child: Text(_label,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: _fg)),
    );
  }
}

// ─── Sheet del recibo ──────────────────────────────────────────────────────────

class _InvoiceSheet extends StatefulWidget {
  final DatabaseHelper db;
  final Package package;

  const _InvoiceSheet({required this.db, required this.package});

  @override
  State<_InvoiceSheet> createState() => _InvoiceSheetState();
}

class _InvoiceSheetState extends State<_InvoiceSheet> {
  Invoice? _invoice;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final inv = await widget.db.getInvoiceForPackage(widget.package.id!);
      setState(() => _invoice = inv);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: _loading
          ? const SizedBox(height: 160,
              child: Center(child: CircularProgressIndicator(color: _navy)))
          : _error != null
              ? SizedBox(height: 160,
                  child: Center(child: Text(_error!,
                      style: const TextStyle(color: Colors.red))))
              : _invoice == null
                  ? const SizedBox(height: 160,
                      child: Center(child: Text(
                        'Aún no se ha generado un recibo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF888888)),
                      )))
                  : _buildContent(_invoice!),
    );
  }

  Widget _buildContent(Invoice inv) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),

          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inv.displayNumber,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _navy)),
              const SizedBox(height: 4),
              Text(DateFormat('dd/MM/yyyy  HH:mm').format(inv.createdAt.toLocal()),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
              if (inv.issuedByName != null)
                Text('Emitido por: ${inv.issuedByName}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
            ])),
            _StatusBadge(status: inv.status),
          ]),

          // ── QR para retiro en local ─────────────────────────────────────
          if (inv.status != 'anulada') ...[
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: QrImageView(
                      data: 'ncx:${inv.id}',
                      version: QrVersions.auto,
                      size: 150,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    inv.balance > 0.009
                        ? 'Muestra este código al retirar o pagar en el local'
                        : 'Muestra este código al retirar tu paquete',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF888888)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),

          const Text('Detalle', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _navy)),
          const SizedBox(height: 10),
          ...inv.items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.inventory_2_outlined, size: 15, color: _orange),
              const SizedBox(width: 8),
              Expanded(child: Text(item.description, style: const TextStyle(fontSize: 13, color: Color(0xFF444444)))),
              const SizedBox(width: 8),
              Text('\$${item.amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
            ]),
          )),

          if (inv.hasDelivery) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 15, color: _orange),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Delivery${inv.deliveryAddress != null ? ' · ${inv.deliveryAddress}' : ''}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF444444)),
              )),
              const SizedBox(width: 8),
              Text('\$${inv.deliveryCost.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
            ]),
          ],

          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 10),

          _Row(label: 'Subtotal', value: '\$${inv.subtotal.toStringAsFixed(2)}'),
          if (inv.hasDelivery)
            _Row(label: 'Delivery', value: '\$${inv.deliveryCost.toStringAsFixed(2)}'),
          const SizedBox(height: 4),
          _Row(label: 'Total', value: '\$${inv.total.toStringAsFixed(2)}', bold: true, large: true),

          if (inv.payments.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 10),
            const Text('Pagos recibidos',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _navy)),
            const SizedBox(height: 8),
            ...inv.payments.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, size: 15, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(Payment.methodLabel(p.method), style: const TextStyle(fontSize: 13))),
                Text('\$${p.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.green)),
              ]),
            )),
            _Row(label: 'Pagado', value: '\$${inv.paidAmount.toStringAsFixed(2)}', valueColor: Colors.green),
          ],

          if (inv.balance > 0.009) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _orange.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Saldo pendiente',
                    style: TextStyle(fontWeight: FontWeight.w700, color: _orange, fontSize: 14)),
                Text('\$${inv.balance.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _orange)),
              ]),
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Helpers UI ────────────────────────────────────────────────────────────────

class _PayBadge extends StatelessWidget {
  final bool isPaid;
  const _PayBadge({required this.isPaid});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isPaid ? Colors.green.withValues(alpha: 0.1) : _orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isPaid ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 13, color: isPaid ? Colors.green : _orange),
        const SizedBox(width: 5),
        Text(isPaid ? 'Pagado' : 'Pendiente',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: isPaid ? Colors.green : _orange)),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.grey.shade600),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color get _bg {
    switch (status) {
      case 'pagada': return Colors.green.withValues(alpha: 0.1);
      case 'parcial': return Colors.orange.withValues(alpha: 0.1);
      case 'anulada': return Colors.red.withValues(alpha: 0.1);
      default: return _orange.withValues(alpha: 0.1);
    }
  }

  Color get _fg {
    switch (status) {
      case 'pagada': return Colors.green.shade700;
      case 'parcial': return Colors.orange.shade700;
      case 'anulada': return Colors.red.shade700;
      default: return _orange;
    }
  }

  String get _label {
    switch (status) {
      case 'pagada': return 'Pagado';
      case 'parcial': return 'Pago parcial';
      case 'anulada': return 'Anulado';
      default: return 'Pendiente';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(20)),
      child: Text(_label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _fg)),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool large;
  final Color? valueColor;

  const _Row({required this.label, required this.value,
      this.bold = false, this.large = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(
            fontSize: bold ? 14 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            color: bold ? _navy : const Color(0xFF666666))),
        Text(value, style: TextStyle(
            fontSize: large ? 18 : 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? _navy)),
      ]),
    );
  }
}
