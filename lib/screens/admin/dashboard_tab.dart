import 'package:flutter/material.dart';
import 'admin_theme.dart';
import '../../services/database_helper.dart';
import '../../models/invoice.dart';
import '../../models/package.dart';
import '../../models/delivery.dart';
import 'package:testapp/models/user.dart' as app_models;

/// Panel de métricas del negocio: ingresos, cartera, paquetes por estado y
/// desempeño de repartidores. Solo lectura — usa datos que ya existen.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final _db = DatabaseHelper();
  bool _loading = true;
  String? _error;

  List<Invoice> _invoices = [];
  List<Package> _packages = [];
  List<Delivery> _deliveries = [];
  List<app_models.User> _users = [];

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
      final results = await Future.wait([
        _db.getAllInvoices(),
        _db.getAllPackages(),
        _db.getAllDeliveries(),
        _db.getAllUsers(),
      ]);
      if (!mounted) return;
      setState(() {
        _invoices = results[0] as List<Invoice>;
        _packages = results[1] as List<Package>;
        _deliveries = results[2] as List<Delivery>;
        _users = results[3] as List<app_models.User>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Métricas ────────────────────────────────────────────────────────────

  bool _isThisMonth(DateTime d) {
    final now = DateTime.now();
    final local = d.toLocal();
    return local.year == now.year && local.month == now.month;
  }

  double get _ingresosMes => _invoices
      .where((i) => i.status != 'anulada')
      .expand((i) => i.payments)
      .where((p) => _isThisMonth(p.paidAt))
      .fold(0.0, (s, p) => s + p.amount);

  double get _porCobrar => _invoices
      .where((i) => i.status == 'pendiente' || i.status == 'parcial')
      .fold(0.0, (s, i) => s + i.balance);

  Map<String, int> get _paquetesPorEstado {
    final counts = <String, int>{
      'Recibido': 0,
      'En tránsito': 0,
      'En aduana': 0,
      'Listo para recoger': 0,
    };
    for (final p in _packages) {
      final last = (p.statusHistory?.isNotEmpty ?? false)
          ? p.statusHistory!.last['status'] as String
          : 'Recibido';
      // Los pagados ya salieron del flujo activo.
      if (p.isPaid) continue;
      counts[last] = (counts[last] ?? 0) + 1;
    }
    return counts;
  }

  int get _entregasMes => _deliveries
      .where((d) =>
          d.status == 'entregado' &&
          d.deliveredAt != null &&
          _isThisMonth(d.deliveredAt!))
      .length;

  int get _clientes => _users
      .where((u) =>
          !u.isAdmin &&
          u.role != 'admin' &&
          u.role != 'repartidor' &&
          u.role != 'almacen')
      .length;

  /// Entregas completadas por repartidor (nombre → cantidad), ordenado desc.
  List<MapEntry<String, int>> get _topRepartidores {
    final counts = <String, int>{};
    for (final d in _deliveries) {
      if (d.status != 'entregado') continue;
      final name = d.delivererName ?? 'Sin nombre';
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final list = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  static const _estadoColores = {
    'Recibido': Color(0xFF4CAF50),
    'En tránsito': Color(0xFFFF9800),
    'En aduana': Color(0xFFF44336),
    'Listo para recoger': Color(0xFF2196F3),
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: navy));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!,
            style: const TextStyle(color: Colors.red, fontSize: 13)),
      );
    }

    final estados = _paquetesPorEstado;
    final maxEstado =
        estados.values.fold(0, (m, v) => v > m ? v : m).clamp(1, 1 << 30);
    final tops = _topRepartidores;
    final maxTop =
        tops.fold(0, (m, e) => e.value > m ? e.value : m).clamp(1, 1 << 30);

    return RefreshIndicator(
      onRefresh: _load,
      color: navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Tarjetas de dinero ───────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Ingresos del mes',
                  value: '\$${_ingresosMes.toStringAsFixed(2)}',
                  icon: Icons.trending_up_rounded,
                  bg: readyBg,
                  fg: readyFg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Por cobrar',
                  value: '\$${_porCobrar.toStringAsFixed(2)}',
                  icon: Icons.schedule_rounded,
                  bg: customsBg,
                  fg: customsFg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Entregas del mes',
                  value: '$_entregasMes',
                  icon: Icons.delivery_dining_rounded,
                  bg: purpleLight,
                  fg: purpleMid,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Clientes',
                  value: '$_clientes',
                  icon: Icons.people_alt_rounded,
                  bg: transitBg,
                  fg: transitFg,
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // ── Paquetes por estado ──────────────────────────────────────────
          const Text('PAQUETES ACTIVOS POR ESTADO',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF888780),
                  letterSpacing: 0.8)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: lavenderBorder),
            ),
            child: Column(
              children: [
                for (final e in estados.entries) ...[
                  _BarRow(
                    label: e.key,
                    value: e.value,
                    fraction: e.value / maxEstado,
                    color: _estadoColores[e.key] ?? navy,
                  ),
                  if (e.key != estados.keys.last) const SizedBox(height: 12),
                ],
              ],
            ),
          ),

          const SizedBox(height: 22),

          // ── Entregas por repartidor ──────────────────────────────────────
          const Text('ENTREGAS POR REPARTIDOR',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF888780),
                  letterSpacing: 0.8)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: lavenderBorder),
            ),
            child: tops.isEmpty
                ? const Text('Aún no hay entregas completadas.',
                    style:
                        TextStyle(fontSize: 13, color: Color(0xFF888780)))
                : Column(
                    children: [
                      for (final e in tops) ...[
                        _BarRow(
                          label: e.key,
                          value: e.value,
                          fraction: e.value / maxTop,
                          color: orange,
                        ),
                        if (e != tops.last) const SizedBox(height: 12),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Tarjeta de estadística ──────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color bg;
  final Color fg;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.bg,
    required this.fg,
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: fg)),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
        ],
      ),
    );
  }
}

// ─── Fila con barra proporcional ─────────────────────────────────────────────

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final double fraction; // 0..1 relativo al máximo
  final Color color;

  const _BarRow({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: navy)),
            ),
            Text('$value',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 7,
            backgroundColor: const Color(0xFFF1EFE8),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
