import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/user.dart' as app_models;
import '../../services/database_helper.dart';
import '../../models/package.dart';
import '../../models/invoice.dart';
import '../../widgets/status_timeline.dart';
import '../../utils/shipping_calculator.dart';
import 'admin_theme.dart';

class PackagesTab extends StatefulWidget {
  /// Modo encargado de almacén: solo puede asignar paquetes y poner los
  /// estados "Recibido" y "En tránsito"; no puede marcar pagos.
  final bool isWarehouse;
  const PackagesTab({super.key, this.isWarehouse = false});

  @override
  PackagesTabState createState() => PackagesTabState();
}

class PackagesTabState extends State<PackagesTab>
    with SingleTickerProviderStateMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // ── Capacidades según el rol ────────────────────────────────────────────
  bool get _canAssign => widget.isWarehouse;       // solo almacén asigna
  bool get _canMarkPaid => !widget.isWarehouse;    // solo admin completo cobra
  // Estados que este rol puede asignar.
  List<String> get _allowedStatuses => widget.isWarehouse
      ? const ['Recibido', 'En tránsito']
      : const ['Recibido', 'En tránsito', 'En aduana', 'Listo para recoger'];

  // El almacén solo ve paquetes en Recibido / En tránsito en la lista.
  List<Package> get _visiblePackages => widget.isWarehouse
      ? _packages.where((p) => _allowedStatuses.contains(_statusLabel(p))).toList()
      : _packages;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _trackingController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  final List<Map<String, dynamic>> _packageTypes = [
    {'id': '1', 'name': 'Ropa'},
    {'id': '2', 'name': 'Joyeria'},
    {'id': '3', 'name': 'Electronica/Tecnologia'},
    {'id': '4', 'name': 'Otros'},
  ];

  final List<Map<String, dynamic>> _shippingMethods = [
    {'id': '1', 'name': 'Aéreo'},
    {'id': '2', 'name': 'Marítimo'},
  ];

  String? _selectedShippingMethodId;
  String? _selectedPackageTypeId;
  String? _selectedUserId;
  List<app_models.User> _users = [];
  List<Package> _packages = [];
  bool _isLoading = false;
  double _calculatedPrice = 0.0;

  // ── Refresco público (lo usa el shell desde el botón de la AppBar) ─────────
  Future<void> refresh() => _loadData();

  String? get _selectedUserLabel {
    if (_selectedUserId == null) return null;
    final u = _users.firstWhere(
      (u) => u.id == _selectedUserId,
      orElse: () => app_models.User(
        id: '', name: '', lastName: '', email: '',
        casillero: '', isAdmin: false,
      ),
    );
    if (u.id.isEmpty) return null;
    return '${u.name} ${u.lastName} · ${u.casillero}';
  }

  Future<void> _openUserSearch() async {
    FocusScope.of(context).unfocus();
    final clientes = _users
        .where((u) =>
            !u.isAdmin &&
            u.role != 'admin' &&
            u.role != 'repartidor' &&
            u.role != 'almacen')
        .toList();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserSearchSheet(users: clientes),
    );
    if (selected != null) {
      setState(() => _selectedUserId = selected);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _calculatePrice() {
    if (_selectedShippingMethodId == null ||
        _selectedPackageTypeId == null ||
        _weightController.text.isEmpty) {
      setState(() => _calculatedPrice = 0.0);
      return;
    }
    try {
      final weight = double.parse(_weightController.text.replaceAll(',', '.'));
      final shippingMethod =
          _shippingMethods.firstWhere(
            (m) => m['id'] == _selectedShippingMethodId,
          )['name'];
      final method =
          shippingMethod == 'Aéreo' ? ShippingMethod.air : ShippingMethod.sea;
      final packageType =
          _packageTypes.firstWhere(
            (t) => t['id'] == _selectedPackageTypeId,
          )['name'];
      PackageCategory category;
      switch (packageType) {
        case 'Joyeria':
          category = PackageCategory.jewelry;
          break;
        case 'Electronica/Tecnologia':
          category = PackageCategory.electronics;
          break;
        default:
          category = PackageCategory.clothes;
      }
      setState(() {
        _calculatedPrice = ShippingCalculator.calculatePrice(
          weightLbs: weight,
          method: method,
          category: category,
        );
      });
    } catch (_) {
      setState(() => _calculatedPrice = 0.0);
    }
  }

  String _statusLabel(Package package) {
    if (package.statusHistory?.isNotEmpty ?? false) {
      return package.statusHistory!.last['status'] as String? ?? 'Recibido';
    }
    return 'Recibido';
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'En tránsito':
        return transitBg;
      case 'En aduana':
        return customsBg;
      case 'Listo para recoger':
        return readyBg;
      default:
        return receivedBg;
    }
  }

  Color _statusFg(String status) {
    switch (status) {
      case 'En tránsito':
        return transitFg;
      case 'En aduana':
        return customsFg;
      case 'Listo para recoger':
        return readyFg;
      default:
        return receivedFg;
    }
  }

  IconData _packageIcon(int typeId) {
    switch (typeId) {
      case 2:
        return Icons.diamond_outlined;
      case 3:
        return Icons.laptop_outlined;
      case 1:
        return Icons.checkroom_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  Color _packageIconBg(int typeId) {
    switch (typeId) {
      case 2:
        return jewelryBg;
      case 3:
        return electronicsBg;
      case 1:
        return clothesBg;
      default:
        return otherBg;
    }
  }

  Color _packageIconFg(int typeId) {
    switch (typeId) {
      case 2:
        return jewelryFg;
      case 3:
        return electronicsFg;
      case 1:
        return clothesFg;
      default:
        return otherFg;
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
    _weightController.addListener(_calculatePrice);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _weightController.removeListener(_calculatePrice);
    _trackingController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _fadeCtrl.reset();
    final users = await _dbHelper.getAllUsers();
    final packages = await _dbHelper.getAllPackages();
    setState(() {
      _users = users;
      _packages = packages;
      _isLoading = false;
    });
    _fadeCtrl.forward();
  }


  Future<void> _assignPackage() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUserId == null) {
      _showSnack('Selecciona un usuario', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final existing = await _dbHelper.getPackageByTrackingCode(
        _trackingController.text,
      );
      if (existing != null) {
        throw 'El código de seguimiento ya está en uso. Por favor, use un código único.';
      }
      final newPackage = Package(
        trackingCode: _trackingController.text,
        shippingMethodId: int.parse(_selectedShippingMethodId!),
        packageTypeId: int.parse(_selectedPackageTypeId!),
        userId: _selectedUserId!,
        weight: double.parse(_weightController.text.replaceAll(',', '.')),
        price: _calculatedPrice,
        isPaid: false,
      );
      await _dbHelper.insertPackage(newPackage);
      _trackingController.clear();
      _weightController.clear();
      setState(() {
        _selectedUserId = null;
        _selectedShippingMethodId = null;
        _selectedPackageTypeId = null;
        _calculatedPrice = 0.0;
      });
      await _loadData();
      if (!mounted) return;
      _showSnack('Paquete asignado exitosamente', isError: false);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsPaid(Package package) async {
    // 1) Obtener (o crear) el recibo del paquete. Normalmente ya existe porque
    //    se genera al pasar a "Listo para recoger".
    setState(() => _isLoading = true);
    Invoice invoice;
    try {
      invoice = await _dbHelper.getInvoiceForPackage(package.id!) ??
          await _dbHelper.createInvoice(
            userId: package.userId,
            packages: [package],
          );
    } catch (e) {
      if (mounted) _showSnack('Error: ${e.toString()}', isError: true);
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) setState(() => _isLoading = false);
    if (!mounted) return;

    // 2) Elegir método de pago (efectivo / transferencia).
    final method = await _selectPaymentMethod(invoice.balance);
    if (method == null) return;

    // 3) Registrar el pago por el saldo. registerPayment cierra el recibo y
    //    sincroniza is_paid en los paquetes.
    setState(() => _isLoading = true);
    try {
      if (invoice.balance > 0.009) {
        await _dbHelper.registerPayment(
          invoiceId: invoice.id,
          amount: invoice.balance,
          method: method,
        );
      } else {
        await _dbHelper.updatePackagePaymentStatus(package.id!, true);
      }
      await _loadData();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showSnack('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Diálogo para elegir el método de pago. Devuelve 'efectivo' o
  /// 'transferencia', o null si se cancela.
  Future<String?> _selectPaymentMethod(double amount) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Registrar pago',
            style: TextStyle(
                color: navy, fontWeight: FontWeight.w700, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total a cobrar: \$${amount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
            const SizedBox(height: 14),
            const Text('¿Cómo pagó el cliente?',
                style: TextStyle(fontSize: 13, color: navy)),
            const SizedBox(height: 10),
            _payMethodTile(ctx, 'efectivo', 'Efectivo',
                Icons.payments_outlined),
            const SizedBox(height: 8),
            _payMethodTile(ctx, 'transferencia', 'Transferencia',
                Icons.account_balance_outlined),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: navy)),
          ),
        ],
      ),
    );
  }

  Widget _payMethodTile(
      BuildContext ctx, String value, String label, IconData icon) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: lavenderBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: navy),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: navy)),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Color(0xFFBBBBBB)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmStatusUpdate(Package package, String newStatus) async {
    if (package.id == null || package.id!.isEmpty) {
      _showSnack('Error: Paquete no válido', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final location = _getStatusLocation(newStatus);
      await _dbHelper.updatePackageStatus(package.id!, newStatus, location);

      if (newStatus == 'Listo para recoger') {
        final yaFacturado = await _dbHelper.hasInvoiceForPackage(package.id!);
        if (!yaFacturado) {
          await _dbHelper.createInvoice(
            userId: package.userId,
            packages: [package],
          );
        }
        if (mounted) {
          _showSnack('Estado actualizado · Recibo generado', isError: false);
        }
      } else {
        if (mounted) _showSnack('Estado actualizado', isError: false);
      }

      await _loadData();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        _showSnack('Error al actualizar: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getStatusLocation(String status) {
    switch (status) {
      case 'Recibido':
        return 'Recibido en Estados Unidos';
      case 'En tránsito':
        return 'En camino a Nicaragua';
      case 'En aduana':
        return 'Aduana Nicaragua';
      case 'Listo para recoger':
        return 'Oficina local';
      default:
        return 'Ubicación desconocida';
    }
  }

  void _updatePackageStatus(Package package) {
    final last = _statusLabel(package);
    String? next;
    if (last == 'Recibido') next = 'En tránsito';
    else if (last == 'En tránsito') next = 'En aduana';
    else if (last == 'En aduana') next = 'Listo para recoger';

    if (next == null) {
      _showSnack('El paquete ya está en su estado final', isError: false);
      return;
    }

    // Encargado de almacén: solo puede llevar hasta "En tránsito".
    if (!_allowedStatuses.contains(next)) {
      _showSnack(
          '🔒 Solo un administrador puede asignar el estado "$next".',
          isError: true);
      return;
    }

    showDialog(
      context: context,
      builder: (_) => _StyledDialog(
        title: 'Actualizar estado',
        message: '¿Cambiar estado a "$next"?',
        confirmLabel: 'Confirmar',
        onConfirm: () async {
          Navigator.pop(context);
          await _confirmStatusUpdate(package, next!);
        },
      ),
    );
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 14)),
        backgroundColor:
            isError ? const Color(0xFFA32D2D) : const Color(0xFF3B6D11),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Envuelve un widget mostrándolo atenuado, sin interacción y con un
  /// candado encima (para acciones que el rol actual no puede usar).
  Widget _lockedCard({required Widget child, required String message}) {
    return Stack(
      children: [
        Opacity(opacity: 0.4, child: IgnorePointer(child: child)),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.35),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: navy,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(message,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  app_models.User _findUser(String userId) {
    return _users.firstWhere(
      (u) => u.id == userId,
      orElse:
          () => app_models.User(
            id: 'unknown',
            name: 'Desconocido',
            lastName: '',
            email: '',
            casillero: '',
            isAdmin: false,
          ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _isLoading && _packages.isEmpty ? _buildLoader() : _buildBody();
  }

  Widget _buildLoader() {
    return const Center(child: CircularProgressIndicator(color: navy));
  }

  Widget _buildBody() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Assignment card ──────────────────────────────────────────────
            _canAssign
                ? _SurfaceCard(child: _buildAssignmentForm())
                : _lockedCard(
                    child: _SurfaceCard(child: _buildAssignmentForm()),
                    message:
                        'Solo el encargado de almacén puede asignar paquetes.'),
            const SizedBox(height: 20),

            // ── Packages list ────────────────────────────────────────────────
            _buildPackagesHeader(),
            const SizedBox(height: 12),
            if (_visiblePackages.isEmpty)
              _buildEmptyState()
            else
              ...List.generate(
                _visiblePackages.length,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildPackageCard(_visiblePackages[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Assignment form ────────────────────────────────────────────────────────

  Widget _buildAssignmentForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Asignar nuevo paquete',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: navy,
                letterSpacing: 0.1,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Tracking code
          _FieldLabel('Código de seguimiento'),
          _StyledField(
            icon: Icons.confirmation_number_outlined,
            child: TextFormField(
              controller: _trackingController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                LengthLimitingTextInputFormatter(20),
              ],
              style: const TextStyle(fontSize: 14),
              decoration: _bareDecoration('Ej. ABCD1234'),
              validator: (v) {
                if (v!.isEmpty) return 'Campo requerido';
                if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(v))
                  return 'Solo letras y números';
                return null;
              },
            ),
          ),
          const SizedBox(height: 10),

          // Weight
          _FieldLabel('Peso'),
          _StyledField(
            icon: Icons.monitor_weight_outlined,
            suffix: const Text(
              'lbs',
              style: TextStyle(fontSize: 12, color: Color(0xFF888780)),
            ),
            child: TextFormField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                LengthLimitingTextInputFormatter(7),
              ],
              style: const TextStyle(fontSize: 14),
              decoration: _bareDecoration('0.00'),
              validator: (v) {
                if (v!.isEmpty) return 'Ingrese el peso';
                final w = double.tryParse(v.replaceAll(',', '.'));
                if (w == null) return 'Peso inválido';
                if (w <= 0) return 'Debe ser > 0';
                if (w > 1000) return 'Máximo 1000 lbs';
                return null;
              },
              onChanged: (v) {
                if (v.isNotEmpty) {
                  final n = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                  if (n > 1000) {
                    _weightController.text = '1000';
                    _weightController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _weightController.text.length),
                    );
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 10),

          // User
          _FieldLabel('Usuario'),
          GestureDetector(
            onTap: _openUserSearch,
            child: _StyledField(
              icon: Icons.person_outline_rounded,
              suffix: const Icon(Icons.search_rounded,
                  color: Color(0xFF888780), size: 20),
              child: Text(
                _selectedUserLabel ?? 'Buscar usuario',
                style: TextStyle(
                  fontSize: 14,
                  color: _selectedUserId == null
                      ? const Color(0xFFB4B2A9)
                      : const Color(0xFF2C2C2A),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Package type
          _FieldLabel('Tipo de paquete'),
          _StyledField(
            icon: Icons.category_outlined,
            child: DropdownButtonFormField<String>(
              value: _selectedPackageTypeId,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF888780),
                size: 20,
              ),
              style: const TextStyle(fontSize: 14, color: Color(0xFF2C2C2A)),
              decoration: _bareDecoration('Seleccionar tipo'),
              items:
                  _packageTypes
                      .map(
                        (t) => DropdownMenuItem(
                          value: t['id'].toString(),
                          child: Text(t['name']),
                        ),
                      )
                      .toList(),
              onChanged: (v) {
                setState(() => _selectedPackageTypeId = v);
                _calculatePrice();
              },
              validator: (v) => v == null ? 'Seleccione un tipo' : null,
            ),
          ),
          const SizedBox(height: 10),

          // Shipping method
          _FieldLabel('Método de envío'),
          _StyledField(
            icon: Icons.local_shipping_outlined,
            child: DropdownButtonFormField<String>(
              value: _selectedShippingMethodId,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF888780),
                size: 20,
              ),
              style: const TextStyle(fontSize: 14, color: Color(0xFF2C2C2A)),
              decoration: _bareDecoration('Seleccionar método'),
              items:
                  _shippingMethods
                      .map(
                        (m) => DropdownMenuItem(
                          value: m['id'].toString(),
                          child: Text(m['name']),
                        ),
                      )
                      .toList(),
              onChanged: (v) {
                setState(() => _selectedShippingMethodId = v);
                _calculatePrice();
              },
              validator: (v) => v == null ? 'Seleccione un método' : null,
            ),
          ),
          const SizedBox(height: 16),

          // Price display
          Container(
            decoration: BoxDecoration(
              color: purpleLight,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Precio calculado',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: purpleMid,
                  ),
                ),
                Text(
                  '\$${_calculatedPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: navy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _assignPackage,
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text(
                'Asignar paquete',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: navy,
                foregroundColor: Colors.white,
                disabledBackgroundColor: navy.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _bareDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFB4B2A9)),
      border: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  // ── Package list ───────────────────────────────────────────────────────────

  Widget _buildPackagesHeader() {
    return Row(
      children: [
        const Text(
          'PAQUETES REGISTRADOS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF888780),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: orange,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_visiblePackages.length}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: purpleLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 30,
                color: purpleMid,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No hay paquetes registrados',
              style: TextStyle(fontSize: 15, color: Color(0xFF888780)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageCard(Package package) {
    final user = _findUser(package.userId);
    final status = _statusLabel(package);
    final typeId = package.packageTypeId;

    return GestureDetector(
      onTap: () => _showPackageDetails(package),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD3D1C7), width: 0.5),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _packageIconBg(typeId),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _packageIcon(typeId),
                color: _packageIconFg(typeId),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    package.trackingCode,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2C2C2A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${package.packageTypeName ?? ''} · ${package.shippingMethodName ?? ''} · ${user.name} ${user.lastName}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF888780),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Status + arrow
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusBg(status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _statusFg(status),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: orange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Package detail bottom sheet ────────────────────────────────────────────

  void _showPackageDetails(Package package) {
    final user = _findUser(package.userId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD3D1C7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Detalles del paquete',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: navy,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1EFE8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Color(0xFF5F5E5A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFD3D1C7), height: 1),
                const SizedBox(height: 16),

                // Details grid
                _DetailRow('Código de seguimiento', package.trackingCode),
                _DetailRow(
                  'Tipo de paquete',
                  package.packageTypeName ?? package.packageTypeId.toString(),
                ),
                _DetailRow('Peso', '${package.weight} libras'),
                _DetailRow(
                  'Método de envío',
                  package.shippingMethodName ??
                      package.shippingMethodId.toString(),
                ),
                _DetailRow('Usuario', '${user.name} ${user.lastName}'),
                _DetailRow('Casillero', user.casillero),
                _DetailRow(
                  'Fecha creación',
                  DateFormat(
                    'dd/MM/yyyy HH:mm',
                  ).format(package.createdAt.toLocal()),
                ),
                _DetailRow('Precio', '\$${package.price.toStringAsFixed(2)}'),

                // Estado de pago + cobro (oculto para el encargado de almacén)
                if (!widget.isWarehouse) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 130,
                        child: Text(
                          'Estado de pago:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Color(0xFF444441),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: package.isPaid ? receivedBg : transitBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              package.isPaid
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.schedule_rounded,
                              size: 14,
                              color: package.isPaid ? receivedFg : transitFg,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              package.isPaid ? 'Pagado' : 'Pendiente',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color:
                                    package.isPaid ? receivedFg : transitFg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Mark as paid button — solo si el paquete está en su estado final
                if (!package.isPaid) ...[
                  const SizedBox(height: 4),
                  if (_statusLabel(package) == 'Listo para recoger')
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _canMarkPaid
                            ? () => _markAsPaid(package)
                            : () => _showSnack(
                                '🔒 Solo un administrador puede registrar pagos.',
                                isError: true),
                        icon: Icon(
                            _canMarkPaid
                                ? Icons.payments_outlined
                                : Icons.lock_outline,
                            size: 18),
                        label: const Text('Marcar como pagado'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _canMarkPaid
                              ? navy
                              : Colors.grey.shade500,
                          side: const BorderSide(color: lavenderBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1EFE8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 16, color: Color(0xFF888780)),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Solo se puede cobrar cuando el paquete esté "Listo para recoger".',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF5F5E5A)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                ], // fin: estado de pago oculto para el almacén

                const SizedBox(height: 20),
                const Text(
                  'Historial de estados',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: navy,
                  ),
                ),
                const SizedBox(height: 12),
                StatusTimeline(
                  statusTimeline: widget.isWarehouse
                      ? (package.statusHistory ?? [])
                          .where((s) =>
                              _allowedStatuses.contains(s['status']))
                          .toList()
                      : (package.statusHistory ?? []),
                ),
                const SizedBox(height: 20),

                // Update status button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => _updatePackageStatus(package),
                    icon: const Icon(Icons.update_rounded, size: 18),
                    label: const Text(
                      'Actualizar estado',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Sub-widgets usados solo por esta pestaña ───────────────────────────────────

class _SurfaceCard extends StatelessWidget {
  final Widget child;
  const _SurfaceCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD3D1C7), width: 0.5),
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFF888780),
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _StyledField extends StatelessWidget {
  final IconData icon;
  final Widget child;
  final Widget? suffix;
  const _StyledField({required this.icon, required this.child, this.suffix});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F3FF),
        border: Border.all(color: const Color(0xFFC5C2E8), width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: orange, size: 20),
          const SizedBox(width: 10),
          Expanded(child: child),
          if (suffix != null) suffix!,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF444441),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF2C2C2A)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Buscador de usuarios ──────────────────────────────────────────────────────

class _UserSearchSheet extends StatefulWidget {
  final List<app_models.User> users;
  const _UserSearchSheet({required this.users});

  @override
  State<_UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<_UserSearchSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<app_models.User> get _filtered {
    if (_query.trim().isEmpty) return widget.users;
    final q = _query.toLowerCase();
    return widget.users.where((u) {
      return '${u.name} ${u.lastName}'.toLowerCase().contains(q) ||
          u.casillero.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: lavenderBorder,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Buscar usuario',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: navy)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Nombre, casillero o correo',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: lavenderBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: lavenderBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: navy)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('Sin resultados',
                        style: TextStyle(color: Color(0xFF888780))),
                  )
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey.shade100),
                    itemBuilder: (_, i) {
                      final u = _filtered[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: purpleLight,
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.person_outline,
                              color: purpleMid, size: 20),
                        ),
                        title: Text('${u.name} ${u.lastName}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: navy)),
                        subtitle: Text(u.casillero,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF888780))),
                        onTap: () => Navigator.pop(context, u.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StyledDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;
  const _StyledDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: navy,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(fontSize: 14, color: Color(0xFF444441)),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel ?? () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF5F5E5A),
                      side: const BorderSide(color: Color(0xFFD3D1C7)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: Text(confirmLabel),
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
