import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_theme.dart';
import '../../services/database_helper.dart';
import '../../models/delivery.dart';
import '../../models/user.dart' as app_models;

class PedidosTab extends StatefulWidget {
  const PedidosTab({super.key});

  @override
  State<PedidosTab> createState() => _PedidosTabState();
}

class _PedidosTabState extends State<PedidosTab>
    with SingleTickerProviderStateMixin {
  final _db = DatabaseHelper();
  late final TabController _tabCtrl;

  List<Delivery> _deliveries = [];
  List<app_models.User> _repartidores = [];
  bool _loading = true;
  Timer? _timer;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
    // Realtime: entregas nuevas/cambios de estado y disponibilidad de
    // repartidores llegan al instante.
    _channel = Supabase.instance.client
        .channel('admin-pedidos')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'deliveries',
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            final id = rec['id'] as String?;
            final status = rec['status'] as String?;
            // Ignorar pings de ubicación (misma entrega, mismo estado).
            final match = _deliveries.where((d) => d.id == id);
            if (match.isNotEmpty && match.first.status == status) return;
            _load(silent: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          callback: (payload) {
            if (!mounted) return;
            // Solo interesa el estado en línea de los repartidores.
            if (payload.newRecord['role'] == 'repartidor') {
              _load(silent: true);
            }
          },
        )
        .subscribe();
    // Respaldo por si un evento realtime se pierde.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel?.unsubscribe();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final d = await _db.getAllDeliveries();
      final r = await _db.getAllRepartidores();
      if (mounted) {
        setState(() {
          _deliveries = d;
          _repartidores = r;
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgPage,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabCtrl,
            labelColor: navy,
            unselectedLabelColor: const Color(0xFF888780),
            indicatorColor: orange,
            labelStyle: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13),
            tabs: const [
              Tab(text: 'Entregas'),
              Tab(text: 'Repartidores'),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: navy))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _EntregasView(
                    deliveries: _deliveries, onRefresh: _load),
                _RepartidoresView(
                    repartidores: _repartidores,
                    deliveries: _deliveries,
                    db: _db,
                    onRefresh: _load),
              ],
            ),
    );
  }
}

// ─── Vista Entregas ────────────────────────────────────────────────────────────

class _EntregasView extends StatelessWidget {
  final List<Delivery> deliveries;
  final Future<void> Function() onRefresh;

  const _EntregasView(
      {required this.deliveries, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (deliveries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: purpleLight,
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.local_shipping_outlined,
                  size: 30, color: purpleMid),
            ),
            const SizedBox(height: 14),
            const Text('Sin entregas aún',
                style: TextStyle(
                    fontSize: 15, color: Color(0xFF888780))),
          ],
        ),
      );
    }

    final grouped = <String, List<Delivery>>{};
    for (final d in deliveries) {
      grouped.putIfAbsent(d.status, () => []).add(d);
    }

    final order = [
        'disponible', 'aceptado', 'en_camino', 'entregado', 'cancelado'];

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          for (final status in order)
            if (grouped.containsKey(status)) ...[
              _SectionHeader(
                  label: Delivery.statusLabel(status),
                  count: grouped[status]!.length,
                  color: _statusFg(status)),
              const SizedBox(height: 8),
              for (final d in grouped[status]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DeliveryAdminCard(delivery: d),
                ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  static Color _statusFg(String status) {
    switch (status) {
      case 'disponible': return const Color(0xFF854F0B);
      case 'aceptado':   return const Color(0xFF185FA5);
      case 'en_camino':  return const Color(0xFF185FA5);
      case 'entregado':  return const Color(0xFF0F6E56);
      default:           return Colors.red.shade700;
    }
  }
}

class _DeliveryAdminCard extends StatelessWidget {
  final Delivery delivery;
  const _DeliveryAdminCard({required this.delivery});

  Color get _bg {
    switch (delivery.status) {
      case 'disponible': return transitBg;
      case 'aceptado':   return customsBg;
      case 'en_camino':  return customsBg;
      case 'entregado':  return readyBg;
      default:           return const Color(0xFFFFEBEB);
    }
  }

  Color get _fg {
    switch (delivery.status) {
      case 'disponible': return transitFg;
      case 'aceptado':   return customsFg;
      case 'en_camino':  return customsFg;
      case 'entregado':  return readyFg;
      default:           return Colors.red.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lavenderBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  delivery.clientName ?? 'Cliente',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: navy),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(Delivery.statusLabel(delivery.status),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _fg)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 13, color: orange),
              const SizedBox(width: 4),
              Expanded(
                child: Text(delivery.deliveryAddress,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF666666))),
              ),
            ],
          ),
          if (delivery.delivererName != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.delivery_dining_rounded,
                    size: 13, color: purpleMid),
                const SizedBox(width: 4),
                Text(delivery.delivererName!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF666666))),
              ],
            ),
          ],
          if (delivery.proofUrl != null) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _showProof(context),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.photo_camera_outlined, size: 15, color: navy),
                  SizedBox(width: 5),
                  Text('Ver evidencia de entrega',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: navy,
                          decoration: TextDecoration.underline)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showProof(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: navy,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'Evidencia · ${delivery.clientName ?? 'Cliente'}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ),
            Flexible(
              child: Image.network(
                delivery.proofUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(color: navy),
                      ),
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(30),
                  child: Text('No se pudo cargar la imagen'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Vista Repartidores ────────────────────────────────────────────────────────

class _RepartidoresView extends StatelessWidget {
  final List<app_models.User> repartidores;
  final List<Delivery> deliveries;
  final DatabaseHelper db;
  final Future<void> Function() onRefresh;

  const _RepartidoresView({
    required this.repartidores,
    required this.deliveries,
    required this.db,
    required this.onRefresh,
  });

  int _activeCount(String id) => deliveries
      .where((d) =>
          d.delivererId == id &&
          ['aceptado', 'en_camino'].contains(d.status))
      .length;

  int _doneCount(String id) => deliveries
      .where((d) => d.delivererId == id && d.status == 'entregado')
      .length;

  void _openPromote(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _PromoteRepartidorSheet(db: db, onPromoted: onRefresh),
    );
  }

  Widget _buildOnlineHeader() {
    final online = repartidores.where((r) => r.isAvailable).length;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: readyBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.podcasts_rounded, color: readyFg, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$online de ${repartidores.length}',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: readyFg)),
              const Text('Repartidores en línea',
                  style: TextStyle(fontSize: 13, color: readyFg)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgPage,
      body: repartidores.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                        color: purpleLight,
                        borderRadius: BorderRadius.circular(16)),
                    child: const Icon(
                        Icons.delivery_dining_outlined,
                        size: 30,
                        color: purpleMid),
                  ),
                  const SizedBox(height: 14),
                  const Text('Sin repartidores registrados',
                      style: TextStyle(
                          fontSize: 15, color: Color(0xFF888780))),
                  const SizedBox(height: 8),
                  const Text('Toca + para registrar uno',
                      style: TextStyle(
                          fontSize: 13, color: Color(0xFFAAAAAA))),
                ],
              ),
            )
          : Column(
              children: [
                _buildOnlineHeader(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: onRefresh,
                    color: navy,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: repartidores.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final r = repartidores[i];
                        return _RepartidorCard(
                          repartidor: r,
                          activeCount: _activeCount(r.id),
                          doneCount: _doneCount(r.id),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'repartidores_fab',
        onPressed: () => _openPromote(context),
        backgroundColor: navy,
        icon: const Icon(Icons.person_add_outlined, color: Colors.white),
        label: const Text('Agregar repartidor',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _RepartidorCard extends StatelessWidget {
  final app_models.User repartidor;
  final int activeCount;
  final int doneCount;

  const _RepartidorCard({
    required this.repartidor,
    required this.activeCount,
    required this.doneCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lavenderBorder),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: purpleLight,
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.delivery_dining_rounded,
                    color: purpleMid, size: 24),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: repartidor.isAvailable
                        ? const Color(0xFF16A34A)
                        : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${repartidor.name} ${repartidor.lastName}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: navy),
                ),
                const SizedBox(height: 2),
                Text(
                  repartidor.isAvailable ? 'En línea' : 'Desconectado',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: repartidor.isAvailable
                          ? readyFg
                          : Colors.grey.shade500),
                ),
                if (repartidor.phone != null) ...[
                  const SizedBox(height: 2),
                  Text(repartidor.phone!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF888780))),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatChip(
                  label: '$activeCount activos',
                  color: customsFg,
                  bg: customsBg),
              const SizedBox(height: 4),
              _StatChip(
                  label: '$doneCount entregados',
                  color: readyFg,
                  bg: readyBg),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _StatChip(
      {required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ─── Sheet: promover usuario a repartidor ─────────────────────────────────────

class _PromoteRepartidorSheet extends StatefulWidget {
  final DatabaseHelper db;
  final Future<void> Function() onPromoted;

  const _PromoteRepartidorSheet(
      {required this.db, required this.onPromoted});

  @override
  State<_PromoteRepartidorSheet> createState() =>
      _PromoteRepartidorSheetState();
}

class _PromoteRepartidorSheetState
    extends State<_PromoteRepartidorSheet> {
  final _phoneCtrl = TextEditingController();
  List<app_models.User> _clientes = [];
  app_models.User? _selected;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await widget.db.getClientesParaPromover();
      setState(() => _clientes = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _promote() async {
    if (_selected == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.db.promoteToRepartidor(
        _selected!.id,
        phone: _phoneCtrl.text.trim(),
      );
      await widget.onPromoted();
      if (mounted) Navigator.pop(context);
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
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: lavenderBorder,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Agregar repartidor',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: navy)),
            const SizedBox(height: 6),
            const Text(
              'Selecciona un usuario registrado y cámbialo a repartidor.',
              style: TextStyle(fontSize: 13, color: Color(0xFF888780)),
            ),
            const SizedBox(height: 20),

            if (_loading)
              const Center(child: CircularProgressIndicator(color: navy))
            else if (_clientes.isEmpty)
              const Text(
                'No hay usuarios disponibles para promover.',
                style: TextStyle(color: Color(0xFF888780), fontSize: 13),
              )
            else ...[
              const Text('Usuario',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: navy)),
              const SizedBox(height: 8),
              DropdownButton<app_models.User>(
                value: _selected,
                isExpanded: true,
                hint: const Text('Seleccionar usuario'),
                underline: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    border: Border.all(color: lavenderBorder),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: _clientes
                    .map((u) => DropdownMenuItem(
                          value: u,
                          child: Text(
                            '${u.name} ${u.lastName}',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ))
                    .toList(),
                onChanged: (u) => setState(() => _selected = u),
              ),
              const SizedBox(height: 16),
              const Text('Teléfono (opcional)',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: navy)),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: InputDecoration(
                  hintText: 'Ej: 88881234',
                  counterText: '',
                  prefixIcon: const Icon(Icons.phone_outlined),
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
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_selected != null && !_saving) ? _promote : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: navy,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: lavenderBorder,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Hacer repartidor',
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

// ─── Helpers UI ────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SectionHeader(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.8)),
        const SizedBox(width: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20)),
          child: Text('$count',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }
}
