import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'admin_theme.dart';
import '../../services/database_helper.dart';
import '../../models/invoice.dart';
import 'package:testapp/models/user.dart' as app_models;

/// Escáner de QR para retiro en local: el cliente muestra el QR de su recibo,
/// el admin lo escanea y puede cobrar (si hay saldo) o confirmar la entrega.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _db = DatabaseHelper();
  final _controller = MobileScannerController();
  bool _handling = false; // evita procesar el mismo QR varias veces

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (raw == null || !raw.startsWith('ncx:')) return;
    _handling = true;
    await _controller.stop();

    final invoiceId = raw.substring(4);
    try {
      final invoice = await _db.getInvoiceById(invoiceId);
      final client = await _db.getUserById(invoice.userId);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PickupSheet(db: _db, invoice: invoice, client: client),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('QR no válido o recibo no encontrado: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }

    // Reanudar para el siguiente escaneo.
    if (mounted) {
      await _controller.start();
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: const Text('Escanear retiro',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Marco guía
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Pide al cliente que muestre el QR de su recibo',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hoja con el resultado del escaneo ───────────────────────────────────────

class _PickupSheet extends StatefulWidget {
  final DatabaseHelper db;
  final Invoice invoice;
  final app_models.User? client;

  const _PickupSheet(
      {required this.db, required this.invoice, this.client});

  @override
  State<_PickupSheet> createState() => _PickupSheetState();
}

class _PickupSheetState extends State<_PickupSheet> {
  late Invoice _invoice;
  bool _charging = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _invoice = widget.invoice;
  }

  bool get _paid => _invoice.balance <= 0.009;

  Future<void> _charge() async {
    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Cómo pagó el cliente?',
            style: TextStyle(
                color: navy, fontWeight: FontWeight.w700, fontSize: 16)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'efectivo'),
            child: const Row(children: [
              Icon(Icons.payments_outlined, color: navy),
              SizedBox(width: 10),
              Text('Efectivo'),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'transferencia'),
            child: const Row(children: [
              Icon(Icons.account_balance_outlined, color: navy),
              SizedBox(width: 10),
              Text('Transferencia'),
            ]),
          ),
        ],
      ),
    );
    if (method == null) return;

    setState(() {
      _charging = true;
      _error = null;
    });
    try {
      await widget.db.registerPayment(
        invoiceId: _invoice.id,
        amount: _invoice.balance,
        method: method,
      );
      final updated = await widget.db.getInvoiceById(_invoice.id);
      if (mounted) setState(() => _invoice = updated);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _charging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),

          // Estado del pago, grande y claro
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _paid ? readyBg : customsBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  _paid
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded,
                  color: _paid ? readyFg : customsFg,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _paid
                            ? 'PAGADO — Entregar paquete(s)'
                            : 'PENDIENTE — Saldo \$${_invoice.balance.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: _paid ? readyFg : customsFg),
                      ),
                      Text(_invoice.displayNumber,
                          style: TextStyle(
                              fontSize: 12,
                              color: _paid ? readyFg : customsFg)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Cliente
          if (client != null) ...[
            Row(
              children: [
                const Icon(Icons.person_rounded, size: 18, color: navy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${client.name} ${client.lastName}  ·  ${client.casillero}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: navy),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Paquetes del recibo
          ..._invoice.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 15, color: orange),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(item.description,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF444444)))),
                    Text('\$${item.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: navy)),
                  ],
                ),
              )),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: navy)),
              Text('\$${_invoice.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: navy)),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: _paid
                ? ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Listo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _charging ? null : _charge,
                    icon: _charging
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.payments_outlined),
                    label: Text(_charging
                        ? 'Registrando…'
                        : 'Cobrar \$${_invoice.balance.toStringAsFixed(2)}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
