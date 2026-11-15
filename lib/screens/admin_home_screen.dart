import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'admin/admin_theme.dart';
import 'admin/packages_tab.dart';
import 'admin/pedidos_tab.dart';
import 'admin/facturacion_tab.dart';
import 'admin/dashboard_tab.dart';
import 'admin/qr_scan_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  _AdminHomeScreenState createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final GlobalKey<PackagesTabState> _packagesTabKey =
      GlobalKey<PackagesTabState>();

  int _currentIndex = 0;
  bool _isWarehouse = false;
  bool _roleLoaded = false;
  List<Widget> _tabs = const [];

  static const _titles = [
    'Panel Administrativo',
    'Pedidos',
    'Facturación',
    'Resumen',
  ];

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    bool warehouse = false;
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid != null) {
        final row = await _supabase
            .from('users')
            .select('role')
            .eq('id', uid)
            .single();
        final role = row['role'] as String?;
        warehouse = role == 'almacen';
        debugPrint('🏷️ AdminHomeScreen rol leído="$role" → isWarehouse=$warehouse');
      }
    } catch (e) {
      debugPrint('🏷️ AdminHomeScreen error leyendo rol: $e');
      // si falla, tratamos como admin completo
    }
    if (!mounted) return;
    setState(() {
      _isWarehouse = warehouse;
      _roleLoaded = true;
      _tabs = [
        PackagesTab(key: _packagesTabKey, isWarehouse: warehouse),
        warehouse
            ? _lockedScreen('Pedidos')
            : const PedidosTab(),
        warehouse
            ? _lockedScreen('Facturación')
            : const FacturacionTab(),
        warehouse
            ? _lockedScreen('Resumen')
            : const DashboardTab(),
      ];
    });
  }

  /// Pantalla bloqueada para secciones no disponibles para el almacén.
  Widget _lockedScreen(String section) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                  color: navy.withOpacity(0.08),
                  shape: BoxShape.circle),
              child: const Icon(Icons.lock_outline, size: 36, color: navy),
            ),
            const SizedBox(height: 16),
            Text('$section no disponible',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: navy)),
            const SizedBox(height: 6),
            const Text(
              'Tu rol de encargado de almacén no tiene acceso a esta sección.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF888780)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen()),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label,
      {bool locked = false}) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? orange.withOpacity(0.08) : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: isSelected ? orange : Colors.grey.shade400,
                  size: 24,
                ),
                if (locked)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Icon(Icons.lock,
                        size: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? orange : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgPage,
      appBar: AppBar(
        backgroundColor: navy,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: _logout,
          tooltip: 'Cerrar sesión',
        ),
        title: Text(
          _titles[_currentIndex],
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 17,
            letterSpacing: 0.2,
          ),
        ),
        centerTitle: true,
        actions:
            _currentIndex == 0
                ? [
                  if (!_isWarehouse)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Tooltip(
                        message: 'Escanear retiro (QR)',
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const QrScanScreen()),
                          ),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.qr_code_scanner_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: 'Actualizar',
                      child: GestureDetector(
                        onTap: () => _packagesTabKey.currentState?.refresh(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ]
                : null,
      ),
      // IndexedStack mantiene viva cada pestaña (no se pierde el formulario
      // ni hay que recargar los datos al cambiar de sección).
      body: !_roleLoaded
          ? const Center(child: CircularProgressIndicator(color: navy))
          : IndexedStack(index: _currentIndex, children: _tabs),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.inventory_2_rounded, 'Paquetes'),
                _buildNavItem(1, Icons.assignment_rounded, 'Pedidos',
                    locked: _isWarehouse),
                _buildNavItem(2, Icons.receipt_long_rounded, 'Facturación',
                    locked: _isWarehouse),
                _buildNavItem(3, Icons.insights_rounded, 'Resumen',
                    locked: _isWarehouse),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
