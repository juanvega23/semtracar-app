import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/invoice.dart';
import '../services/database_helper.dart';

const _navy = Color(0xFF12327F);
const _orange = Color(0xFFFA4B0C);

/// Hoja para solicitar delivery de VARIOS paquetes listos en un solo viaje.
/// El cliente elige con checkboxes cuáles llevar juntos (una sola tarifa).
/// Devuelve `true` por Navigator.pop si se solicitó algún delivery.
class MultiDeliveryRequestSheet extends StatefulWidget {
  /// Recibos pendientes (cada uno corresponde a un paquete listo).
  final List<Invoice> pendingInvoices;

  const MultiDeliveryRequestSheet({super.key, required this.pendingInvoices});

  @override
  State<MultiDeliveryRequestSheet> createState() =>
      _MultiDeliveryRequestSheetState();
}

class _MultiDeliveryRequestSheetState extends State<MultiDeliveryRequestSheet> {
  final _db = DatabaseHelper();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final Set<String> _selected = {}; // packageIds seleccionados
  bool _saving = false;
  bool _loadingContact = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Todos seleccionados por defecto.
    for (final inv in widget.pendingInvoices) {
      final pkgId = _packageId(inv);
      if (pkgId != null) _selected.add(pkgId);
    }
    _loadContact();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContact() async {
    try {
      final c = await _db.getCurrentUserContact();
      if (!mounted) return;
      setState(() {
        if (c['address'] != null) _addressCtrl.text = c['address']!;
        if (c['phone'] != null) _phoneCtrl.text = c['phone']!;
      });
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingContact = false);
    }
  }

  String? _packageId(Invoice inv) =>
      inv.items.isNotEmpty ? inv.items.first.packageId : null;

  String _packageLabel(Invoice inv) =>
      inv.items.isNotEmpty ? inv.items.first.description : 'Paquete';

  double get _packagesTotal => widget.pendingInvoices
      .where((inv) => _selected.contains(_packageId(inv)))
      .fold(0.0, (s, inv) => s + inv.subtotal);

  double get _total =>
      _selected.isEmpty ? 0 : _packagesTotal + DatabaseHelper.deliveryCost;

  Future<void> _confirm() async {
    if (_selected.isEmpty) {
      setState(() => _error = 'Selecciona al menos un paquete.');
      return;
    }
    final address = _addressCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (address.isEmpty) {
      setState(() => _error = 'Ingresa tu dirección de entrega.');
      return;
    }
    if (phone.length < 8) {
      setState(() => _error = 'El teléfono debe tener 8 dígitos.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _db.requestDeliveryMulti(
        packageIds: _selected.toList(),
        deliveryAddress: address,
        phone: phone,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
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
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Tienes ${widget.pendingInvoices.length} paquetes listos',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: _navy)),
            const SizedBox(height: 4),
            Text('Elige cuáles enviar juntos en un solo delivery.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 16),

            // Lista de paquetes con checkbox
            ...widget.pendingInvoices.map((inv) {
              final pkgId = _packageId(inv);
              final selected = pkgId != null && _selected.contains(pkgId);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: selected ? _orange : Colors.grey.shade300),
                  color: selected
                      ? _orange.withValues(alpha: 0.04)
                      : Colors.white,
                ),
                child: CheckboxListTile(
                  value: selected,
                  activeColor: _orange,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: pkgId == null
                      ? null
                      : (v) => setState(() {
                            if (v == true) {
                              _selected.add(pkgId);
                            } else {
                              _selected.remove(pkgId);
                            }
                          }),
                  title: Text(_packageLabel(inv),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _navy)),
                  subtitle: Text('\$${inv.subtotal.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ),
              );
            }),

            const SizedBox(height: 12),
            const Text('Dirección de entrega',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
            const SizedBox(height: 8),
            if (_loadingContact)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            TextField(
              controller: _addressCtrl,
              maxLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: _dec('Ej: Residencial Las Palmas, casa #15',
                  Icons.location_on_outlined),
            ),
            const SizedBox(height: 14),
            const Text('Teléfono de contacto',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: _dec('Ej: 88887777', Icons.phone_outlined)
                  .copyWith(counterText: ''),
            ),

            const SizedBox(height: 16),
            const Divider(),
            // Desglose
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Paquetes (${_selected.length})',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                Text('\$${_packagesTotal.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Delivery (una sola vez)',
                    style: TextStyle(fontSize: 13, color: _orange)),
                Text('\$${DatabaseHelper.deliveryCost.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13, color: _orange)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _navy,
                        fontSize: 15)),
                Text('\$${_total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: _navy)),
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
              child: ElevatedButton(
                onPressed: _saving ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        _selected.length > 1
                            ? 'Solicitar delivery de ${_selected.length} paquetes'
                            : 'Solicitar delivery',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: Text('Ahora no',
                    style: TextStyle(color: Colors.grey[600])),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
