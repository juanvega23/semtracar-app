import 'package:flutter/material.dart';
import 'admin_theme.dart';
import '../../services/database_helper.dart';
import '../../models/invoice.dart';

// ─── Tab principal ─────────────────────────────────────────────────────────────

class FacturacionTab extends StatefulWidget {
  const FacturacionTab({super.key});

  @override
  State<FacturacionTab> createState() => _FacturacionTabState();
}

class _FacturacionTabState extends State<FacturacionTab> {
  final _db = DatabaseHelper();
  List<Invoice> _invoices = [];
  bool _loading = true;
  String? _error;
  String _filter = 'todos'; // todos | pendiente | pagada

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invoices = await _db.getAllInvoices();
      setState(() => _invoices = invoices);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  // Recibos no anulados, para los totales.
  Iterable<Invoice> get _activos =>
      _invoices.where((i) => i.status != 'anulada');

  double get _totalCobrado =>
      _activos.fold(0.0, (s, i) => s + i.paidAmount);
  double get _totalPendiente =>
      _activos.fold(0.0, (s, i) => s + i.balance);

  List<Invoice> get _filtered {
    switch (_filter) {
      case 'pendiente':
        return _invoices
            .where((i) => i.status == 'pendiente' || i.status == 'parcial')
            .toList();
      case 'pagada':
        return _invoices.where((i) => i.status == 'pagada').toList();
      default:
        return _invoices;
    }
  }

  void _openDetail(Invoice invoice) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) =>
              _InvoiceDetailScreen(invoice: invoice, onChanged: _load),
        ))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: bgPage,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: navy))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: navy,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _buildTotals(),
                      const SizedBox(height: 16),
                      _buildFilters(),
                      const SizedBox(height: 12),
                      if (_invoices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: _EmptyState(),
                        )
                      else if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text('No hay recibos en esta categoría.',
                                style: TextStyle(
                                    color: Color(0xFF888780), fontSize: 13)),
                          ),
                        )
                      else
                        ...filtered.map((inv) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _InvoiceCard(
                                invoice: inv,
                                onTap: () => _openDetail(inv),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }

  Widget _buildTotals() {
    return Row(
      children: [
        Expanded(
          child: _TotalCard(
            label: 'Cobrado',
            value: '\$${_totalCobrado.toStringAsFixed(2)}',
            bg: readyBg,
            fg: readyFg,
            icon: Icons.check_circle_outline,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TotalCard(
            label: 'Pendiente',
            value: '\$${_totalPendiente.toStringAsFixed(2)}',
            bg: customsBg,
            fg: customsFg,
            icon: Icons.schedule_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    Widget chip(String value, String label) {
      final selected = _filter == value;
      return GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? navy : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? navy : lavenderBorder),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : navy)),
        ),
      );
    }

    return Row(
      children: [
        chip('todos', 'Todos'),
        const SizedBox(width: 8),
        chip('pendiente', 'Pendientes'),
        const SizedBox(width: 8),
        chip('pagada', 'Pagados'),
      ],
    );
  }
}

// ─── Tarjeta de total ──────────────────────────────────────────────────────────

class _TotalCard extends StatelessWidget {
  final String label;
  final String value;
  final Color bg;
  final Color fg;
  final IconData icon;

  const _TotalCard({
    required this.label,
    required this.value,
    required this.bg,
    required this.fg,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: fg)),
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
        ],
      ),
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: readyBg, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.receipt_long_outlined,
                  size: 34, color: readyFg),
            ),
            const SizedBox(height: 18),
            const Text('Sin recibos aún',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: navy)),
            const SizedBox(height: 8),
            const Text(
              'Los recibos se generan automáticamente cuando un paquete '
              'pasa a "Listo para recoger".',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF888780)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tarjeta de recibo en la lista ─────────────────────────────────────────────

class _InvoiceCard extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback onTap;

  const _InvoiceCard({required this.invoice, required this.onTap});

  Color get _statusBg {
    switch (invoice.status) {
      case 'pagada':
        return readyBg;
      case 'parcial':
        return transitBg;
      case 'anulada':
        return const Color(0xFFFFEBEB);
      default:
        return customsBg;
    }
  }

  Color get _statusFg {
    switch (invoice.status) {
      case 'pagada':
        return readyFg;
      case 'parcial':
        return transitFg;
      case 'anulada':
        return Colors.red.shade700;
      default:
        return customsFg;
    }
  }

  String get _statusLabel {
    switch (invoice.status) {
      case 'pagada':
        return 'Pagada';
      case 'parcial':
        return 'Parcial';
      case 'anulada':
        return 'Anulada';
      default:
        return 'Pendiente';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: lavenderBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: purpleLight,
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.receipt_long,
                  color: purpleMid, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(invoice.displayNumber,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: navy,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '${invoice.items.length} paquete(s) · \$${invoice.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF666666)),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: _statusBg,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(_statusLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _statusFg)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pantalla detalle del recibo ───────────────────────────────────────────────

class _InvoiceDetailScreen extends StatefulWidget {
  final Invoice invoice;
  final VoidCallback onChanged;

  const _InvoiceDetailScreen(
      {required this.invoice, required this.onChanged});

  @override
  State<_InvoiceDetailScreen> createState() =>
      _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<_InvoiceDetailScreen> {
  late Invoice _invoice;
  final _db = DatabaseHelper();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _invoice = widget.invoice;
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final updated = await _db.getInvoiceById(_invoice.id);
      setState(() => _invoice = updated);
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openPaymentSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSheet(
        db: _db,
        invoice: _invoice,
        onRegistered: _refresh,
      ),
    );
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Anular recibo',
            style: TextStyle(
                color: navy, fontWeight: FontWeight.w700)),
        content: const Text(
            '¿Deseas anular este recibo? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: navy))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Anular',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _loading = true);
    try {
      await _db.cancelInvoice(_invoice.id);
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red));
      }
    }
  }

  Color get _statusBg {
    switch (_invoice.status) {
      case 'pagada':
        return readyBg;
      case 'parcial':
        return transitBg;
      case 'anulada':
        return const Color(0xFFFFEBEB);
      default:
        return customsBg;
    }
  }

  Color get _statusFg {
    switch (_invoice.status) {
      case 'pagada':
        return readyFg;
      case 'parcial':
        return transitFg;
      case 'anulada':
        return Colors.red.shade700;
      default:
        return customsFg;
    }
  }

  String get _statusLabel {
    switch (_invoice.status) {
      case 'pagada':
        return 'Pagada';
      case 'parcial':
        return 'Parcial';
      case 'anulada':
        return 'Anulada';
      default:
        return 'Pendiente';
    }
  }

  bool get _canPay =>
      _invoice.status == 'pendiente' || _invoice.status == 'parcial';

  bool get _canCancel => _invoice.status != 'anulada';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgPage,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: Text(_invoice.displayNumber,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))),
            ),
          if (_canCancel && !_loading)
            IconButton(
              icon: const Icon(Icons.block_outlined),
              tooltip: 'Anular',
              onPressed: _cancel,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabecera ───────────────────────────────────────────────────
            _SectionCard(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(_invoice.displayNumber,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: navy)),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(_invoice.createdAt),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF888780)),
                    ),
                    if (_invoice.issuedByName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Emitido por: ${_invoice.issuedByName}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF888780)),
                      ),
                    ],
                  ]),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                        color: _statusBg,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(_statusLabel,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _statusFg)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _AmountRow(label: 'Paquetes',
                  value: '\$${_invoice.subtotal.toStringAsFixed(2)}'),
              if (_invoice.hasDelivery)
                _AmountRow(label: 'Delivery',
                    value: '\$${_invoice.deliveryCost.toStringAsFixed(2)}'),
              if (_invoice.taxAmount > 0)
                _AmountRow(label: 'Impuesto',
                    value: '\$${_invoice.taxAmount.toStringAsFixed(2)}'),
              const Divider(height: 20),
              _AmountRow(
                  label: 'Total',
                  value: '\$${_invoice.total.toStringAsFixed(2)}',
                  bold: true),
              _AmountRow(
                  label: 'Pagado',
                  value: '\$${_invoice.paidAmount.toStringAsFixed(2)}',
                  valueColor: readyFg),
              if (_invoice.balance > 0)
                _AmountRow(
                    label: 'Saldo pendiente',
                    value: '\$${_invoice.balance.toStringAsFixed(2)}',
                    valueColor: Colors.red.shade700,
                    bold: true),
            ]),

            const SizedBox(height: 14),

            // ── Items ──────────────────────────────────────────────────────
            const _SectionTitle(text: 'Paquetes incluidos'),
            const SizedBox(height: 6),
            _SectionCard(children: [
              if (_invoice.items.isEmpty)
                const Text('Sin ítems',
                    style: TextStyle(
                        color: Color(0xFF888780), fontSize: 13))
              else
                ..._invoice.items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.inventory_2_outlined,
                              size: 16, color: purpleMid),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(item.description,
                                style: const TextStyle(
                                    fontSize: 13, color: navy)),
                          ),
                          const SizedBox(width: 8),
                          Text('\$${item.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: navy)),
                        ],
                      ),
                    )),
            ]),

            if (_invoice.hasDelivery) ...[
              const SizedBox(height: 14),
              const _SectionTitle(text: 'Entrega a domicilio'),
              const SizedBox(height: 6),
              _SectionCard(children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 18, color: orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _invoice.deliveryAddress ?? 'Sin dirección registrada',
                        style: const TextStyle(fontSize: 13, color: navy),
                      ),
                    ),
                  ],
                ),
              ]),
            ],

            const SizedBox(height: 14),

            // ── Pagos registrados ──────────────────────────────────────────
            const _SectionTitle(text: 'Pagos registrados'),
            const SizedBox(height: 6),
            _SectionCard(children: [
              if (_invoice.payments.isEmpty)
                const Text('Ningún pago registrado aún.',
                    style: TextStyle(
                        color: Color(0xFF888780), fontSize: 13))
              else
                ..._invoice.payments.map((p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                                color: readyBg,
                                borderRadius:
                                    BorderRadius.circular(10)),
                            child: const Icon(Icons.check_circle_outline,
                                color: readyFg, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(Payment.methodLabel(p.method),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: navy)),
                                if (p.reference != null ||
                                    p.bankName != null)
                                  Text(
                                    [
                                      if (p.bankName != null)
                                        p.bankName,
                                      if (p.reference != null)
                                        'Ref: ${p.reference}',
                                    ].join(' · '),
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF888780)),
                                  ),
                              ],
                            ),
                          ),
                          Text('\$${p.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: readyFg)),
                        ],
                      ),
                    )),
            ]),
          ],
        ),
      ),
      bottomNavigationBar: _canPay
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: ElevatedButton.icon(
                  onPressed: _openPaymentSheet,
                  icon: const Icon(Icons.add_card),
                  label: Text(
                    'Registrar pago · Saldo \$${_invoice.balance.toStringAsFixed(2)}',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}  '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

// ─── Sheet: registrar pago ─────────────────────────────────────────────────────

class _PaymentSheet extends StatefulWidget {
  final DatabaseHelper db;
  final Invoice invoice;
  final VoidCallback onRegistered;

  const _PaymentSheet(
      {required this.db,
      required this.invoice,
      required this.onRegistered});

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  String _method = 'efectivo';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-rellena el saldo pendiente
    _amountCtrl.text = widget.invoice.balance.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  bool get _needsReference =>
      _method == 'transferencia' || _method == 'tarjeta_datafono';

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Ingresa un monto válido.');
      return;
    }
    if (amount > widget.invoice.balance + 0.009) {
      setState(
          () => _error = 'El monto no puede superar el saldo pendiente.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.db.registerPayment(
        invoiceId: widget.invoice.id,
        amount: amount,
        method: _method,
        reference: _referenceCtrl.text.trim().isEmpty
            ? null
            : _referenceCtrl.text.trim(),
        bankName: _bankCtrl.text.trim().isEmpty
            ? null
            : _bankCtrl.text.trim(),
      );
      widget.onRegistered();
      if (mounted) Navigator.of(context).pop();
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
                      color: lavenderBorder,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            const Text('Registrar pago',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: navy)),
            const SizedBox(height: 6),
            Text(
              'Saldo pendiente: \$${widget.invoice.balance.toStringAsFixed(2)}',
              style:
                  const TextStyle(fontSize: 13, color: Color(0xFF888780)),
            ),
            const SizedBox(height: 20),

            // ── Método de pago ────────────────────────────────────────────
            const Text('Método',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: navy)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MethodChip(
                  label: 'Efectivo',
                  icon: Icons.payments_outlined,
                  selected: _method == 'efectivo',
                  onTap: () => setState(() => _method = 'efectivo'),
                ),
                _MethodChip(
                  label: 'Transferencia',
                  icon: Icons.account_balance_outlined,
                  selected: _method == 'transferencia',
                  onTap: () =>
                      setState(() => _method = 'transferencia'),
                ),
                _MethodChip(
                  label: 'Tarjeta (datáfono)',
                  icon: Icons.credit_card_outlined,
                  selected: _method == 'tarjeta_datafono',
                  onTap: () =>
                      setState(() => _method = 'tarjeta_datafono'),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Monto ─────────────────────────────────────────────────────
            const Text('Monto (USD)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: navy)),
            const SizedBox(height: 8),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '\$ ',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: lavenderBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: lavenderBorder)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),

            // ── Referencia / banco (si aplica) ────────────────────────────
            if (_needsReference) ...[
              const SizedBox(height: 14),
              const Text('Banco',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: navy)),
              const SizedBox(height: 8),
              TextField(
                controller: _bankCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Ej: BAC, LAFISE, Banpro…',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: lavenderBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: lavenderBorder)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Referencia',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: navy)),
              const SizedBox(height: 8),
              TextField(
                controller: _referenceCtrl,
                decoration: InputDecoration(
                  hintText: 'Número de confirmación / voucher',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: lavenderBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: lavenderBorder)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style:
                      const TextStyle(color: Colors.red, fontSize: 13)),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: navy,
                  disabledBackgroundColor: lavenderBorder,
                  foregroundColor: Colors.white,
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
                    : const Text('Guardar pago',
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

// ─── Chip de método de pago ────────────────────────────────────────────────────

class _MethodChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _MethodChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? navy : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? navy : lavenderBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16, color: selected ? Colors.white : navy),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : navy,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers UI ────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: navy));
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lavenderBorder),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const _AmountRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: bold ? navy : const Color(0xFF666666),
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: valueColor ?? navy)),
        ],
      ),
    );
  }
}
