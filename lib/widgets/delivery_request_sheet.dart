import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/database_helper.dart';

const _navy = Color(0xFF12327F);
const _orange = Color(0xFFFA4B0C);

/// Hoja para confirmar la dirección y solicitar delivery de un paquete.
/// Devuelve `true` por Navigator.pop si el delivery se solicitó con éxito.
class DeliveryRequestSheet extends StatefulWidget {
  final String invoiceId;
  final String packageId;
  final String? userAddress;

  const DeliveryRequestSheet({
    super.key,
    required this.invoiceId,
    required this.packageId,
    this.userAddress,
  });

  @override
  State<DeliveryRequestSheet> createState() => _DeliveryRequestSheetState();
}

class _DeliveryRequestSheetState extends State<DeliveryRequestSheet> {
  final _db = DatabaseHelper();
  late final TextEditingController _addressCtrl;
  final _phoneCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  String? _savedAddress; // dirección guardada en el perfil
  bool _loadingAddress = true;

  @override
  void initState() {
    super.initState();
    _addressCtrl = TextEditingController(text: widget.userAddress ?? '');
    _loadSavedContact();
  }

  Future<void> _loadSavedContact() async {
    try {
      final contact = await _db.getCurrentUserContact();
      if (!mounted) return;
      setState(() {
        _savedAddress = contact['address'];
        // Precargar dirección guardada si no venía una.
        if (_addressCtrl.text.trim().isEmpty && _savedAddress != null) {
          _addressCtrl.text = _savedAddress!;
        }
        // Precargar teléfono guardado.
        if (_phoneCtrl.text.trim().isEmpty && contact['phone'] != null) {
          _phoneCtrl.text = contact['phone']!;
        }
      });
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final address = _addressCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (address.isEmpty) {
      setState(() => _error = 'Ingresa tu dirección de entrega.');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _error = 'Ingresa tu número de teléfono.');
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
      await _db.requestDelivery(
        invoiceId: widget.invoiceId,
        packageId: widget.packageId,
        deliveryAddress: address,
        phone: phone,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
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
            const Text('Solicitar delivery',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: _navy)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.delivery_dining_rounded,
                    size: 18, color: _orange),
                const SizedBox(width: 6),
                Text(
                  'Costo de delivery: \$${DatabaseHelper.deliveryCost.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _orange),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Dirección de entrega',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
            const SizedBox(height: 8),

            // Sugerencia de la dirección guardada en el perfil.
            if (_loadingAddress)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_savedAddress != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F3FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bookmark_outline,
                        size: 18, color: _navy),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Dirección guardada',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF888888))),
                          Text(_savedAddress!,
                              style: const TextStyle(
                                  fontSize: 13, color: _navy)),
                        ],
                      ),
                    ),
                    if (_addressCtrl.text.trim() != _savedAddress)
                      TextButton(
                        onPressed: () => setState(
                            () => _addressCtrl.text = _savedAddress!),
                        style: TextButton.styleFrom(
                            foregroundColor: _orange,
                            padding: const EdgeInsets.symmetric(horizontal: 8)),
                        child: const Text('Usar',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _addressCtrl.text.trim() == _savedAddress
                    ? 'Puedes editarla abajo o agregar otra.'
                    : 'O escribe una dirección diferente:',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
            ],

            TextField(
              controller: _addressCtrl,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ej: Residencial Las Palmas, casa #15',
                prefixIcon: const Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            const SizedBox(height: 16),
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
              decoration: InputDecoration(
                hintText: 'Ej: 88887777',
                prefixIcon: const Icon(Icons.phone_outlined),
                counterText: '',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 20),
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
                    : const Text('Confirmar delivery',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
