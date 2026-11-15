import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:testapp/models/package.dart';
import 'package:testapp/models/invoice.dart';
import 'package:testapp/models/delivery.dart';
import 'package:timeline_tile/timeline_tile.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/database_helper.dart';
import '../../widgets/delivery_request_sheet.dart';
import '../../widgets/multi_delivery_request_sheet.dart';
import '../delivery_route_map.dart';
import 'dart:async';

class TrackingTab extends StatefulWidget {
  final String userId;

  const TrackingTab({Key? key, required this.userId}) : super(key: key);

  @override
  _TrackingTabState createState() => _TrackingTabState();
}

class _TrackingTabState extends State<TrackingTab> {
  List<Map<String, dynamic>> _statusTimeline = [];
  bool _isLoading = true;
  late DatabaseHelper _dbHelper;
  String _currentTrackingCode = '';
  String _currentPackageId = '';
  Package? _activePackage;
  List<Package> _activePackages = [];
  String _lastSignature = '';
  Invoice? _currentInvoice;
  Delivery? _currentDelivery;
  String _deliverySignature = '';
  Timer? _refreshTimer;
  RealtimeChannel? _invoiceChannel;
  final MapController _mapController = MapController();
  final MapController _dialogMapController = MapController();
  final GlobalKey _mapCardKey = GlobalKey();

  static const _locations = {
    'recibido': LatLng(25.801208, -80.330274),
    'en tránsito': LatLng(17.5, -83.0),
    'en aduana': LatLng(12.133663, -86.194260),
    'listo para recoger': LatLng(12.134748, -86.248654),
  };

  static const _locationNames = {
    'recibido': 'Almacén Miami',
    'en tránsito': 'En camino',
    'en aduana': 'Aduana Managua',
    'listo para recoger': 'Semtracar',
  };

  @override
  void initState() {
    super.initState();
    _dbHelper = DatabaseHelper();
    _loadUserPackages();
    _setupRefreshTimer();
    _watchRealtime();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _invoiceChannel?.unsubscribe();
    super.dispose();
  }

  /// Recarga al instante cuando cambia algo relevante para el usuario:
  /// - invoices: el recibo se crea/actualiza (llegó a "Listo para recoger").
  /// - package_status_history: el paquete cambió de estado (RLS limita los
  ///   eventos a los paquetes propios del usuario).
  void _watchRealtime() {
    _invoiceChannel = Supabase.instance.client
        .channel('tracking-watch-${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'invoices',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (_) {
            if (mounted) _loadUserPackages();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'package_status_history',
          callback: (_) {
            if (mounted) _loadUserPackages();
          },
        )
        .subscribe();
  }

  void _setupRefreshTimer() {
    // Respaldo por si algún evento realtime se pierde; la actualización
    // inmediata la dan los canales realtime (invoices y status de paquetes).
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadUserPackages();
    });
  }

  Future<void> _loadUserPackages() async {
    try {
      final packages = await _dbHelper.getPackagesByUser(widget.userId);

      // Activos = paquetes aún no pagados. Una vez pagados, ya están
      // completos y desaparecen del rastreo (quedan en el historial).
      final active = packages.where((p) => !p.isPaid).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (active.isEmpty) {
        setState(() {
          _isLoading = false;
          _activePackages = [];
          _statusTimeline = [];
          _currentTrackingCode = '';
          _currentPackageId = '';
          _activePackage = null;
        });
        return;
      }

      // Mantener la selección actual si sigue activa; si no, elegir el primero
      final selected = active.firstWhere(
        (p) => p.id == _currentPackageId,
        orElse: () => active.first,
      );

      // Refrescar info de delivery ANTES de pintar, para que la tarjeta de
      // delivery aparezca junto con el resto (y no "cargue de último").
      await _refreshDeliveryInfo(selected);

      // Evitar reconstruir (y refrescar el mapa) si nada cambió
      final newSignature =
          '${active.map((p) => p.id).join(',')}|${selected.id}|'
          '${selected.statusHistory?.length ?? 0}|'
          '${selected.statusHistory?.isNotEmpty ?? false ? selected.statusHistory!.last['status'] : ''}';
      if (newSignature == _lastSignature) return;
      _lastSignature = newSignature;

      _applyPackage(selected, active);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusTimeline = _createErrorTimeline();
      });
    }
  }

  void _applyPackage(Package package, List<Package> active) {
    final statuses =
        List<Map<String, dynamic>>.from(package.statusHistory ?? []);
    statuses.sort((a, b) =>
        DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));

    setState(() {
      _activePackages = active;
      _activePackage = package;
      _statusTimeline = statuses;
      _currentTrackingCode = package.trackingCode;
      _currentPackageId = package.id ?? '';
      _isLoading = false;
    });
  }

  void _selectPackage(Package package) {
    // Limpiar de inmediato la info de delivery del paquete anterior para no
    // mostrar un estado obsoleto (p. ej. "Buscando repartidor" del otro pedido)
    // mientras carga la del nuevo.
    setState(() {
      _currentInvoice = null;
      _currentDelivery = null;
      _deliverySignature = '';
    });
    _applyPackage(package, _activePackages);
    _refreshDeliveryInfo(package);
  }

  Future<void> _refreshDeliveryInfo(Package p) async {
    final last = (p.statusHistory?.isNotEmpty ?? false)
        ? p.statusHistory!.last['status'] as String
        : '';
    if (last != 'Listo para recoger' || p.id == null) {
      if (_currentInvoice != null || _currentDelivery != null) {
        setState(() {
          _currentInvoice = null;
          _currentDelivery = null;
          _deliverySignature = '';
        });
      }
      return;
    }
    try {
      // En paralelo para reducir la espera.
      final results = await Future.wait([
        _dbHelper.getInvoiceForPackage(p.id!),
        _dbHelper.getDeliveryForPackage(p.id!),
      ]);
      final invoice = results[0] as Invoice?;
      final delivery = results[1] as Delivery?;
      if (!mounted) return;
      final sig =
          '${invoice?.deliveryChoice}|${invoice?.hasDelivery}|${delivery?.status}';
      if (sig == _deliverySignature) return;
      _deliverySignature = sig;
      setState(() {
        _currentInvoice = invoice;
        _currentDelivery = delivery;
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _solicitarDelivery() async {
    final invoice = _currentInvoice;
    final pkg = _activePackage;
    if (invoice == null || pkg?.id == null) return;

    // Si hay más de un paquete entregable, ofrecer elegir cuáles enviar juntos
    // (incluye los que se declinaron antes). Si solo hay uno, formulario directo.
    List<Invoice> deliverable = [];
    try {
      deliverable = await _dbHelper.getDeliverableInvoices();
    } catch (_) {}
    if (!mounted) return;

    bool? ok;
    if (deliverable.length > 1) {
      ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            MultiDeliveryRequestSheet(pendingInvoices: deliverable),
      );
    } else {
      ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DeliveryRequestSheet(
          invoiceId: invoice.id,
          packageId: pkg!.id!,
          userAddress: invoice.deliveryAddress,
        ),
      );
    }
    if (ok == true) {
      _deliverySignature = '';
      await _refreshDeliveryInfo(pkg!);
    }
  }

  Future<void> _recogerEnLocal() async {
    final invoice = _currentInvoice;
    final pkg = _activePackage;
    if (invoice == null || pkg == null) return;
    try {
      await _dbHelper.declineDelivery(invoice.id);
      _deliverySignature = '';
      await _refreshDeliveryInfo(pkg);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    }
  }

  /// True cuando la tarjeta muestra la PREGUNTA "¿cómo quieres recibirlo?"
  /// (decisión pendiente). En ese caso va arriba; en los demás estados
  /// (solicitado, en camino, rechazado…) la tarjeta va debajo del código.
  bool get _deliveryPromptPending {
    final inv = _currentInvoice;
    if (inv == null) return false;
    if (_currentDelivery != null) return false; // ya solicitado
    if (inv.balance <= 0.009) return false; // ya pagado
    return inv.deliveryChoice != 'rechazado'; // pendiente de decidir
  }

  Widget _buildDeliveryCard() {
    final invoice = _currentInvoice;
    if (invoice == null) return const SizedBox.shrink();

    // Si ya está pagado, no se ofrece delivery
    final isPaid = invoice.balance <= 0.009;

    // ── Caso: delivery ya solicitado → mostrar estado del pedido ──────────────
    if (_currentDelivery != null) {
      final d = _currentDelivery!;
      String label;
      IconData icon;
      Color color;
      switch (d.status) {
        case 'disponible':
          label = 'Buscando un repartidor disponible…';
          icon = Icons.schedule_rounded;
          color = const Color(0xFF854F0B);
          break;
        case 'aceptado':
          label = 'Un repartidor tomó tu pedido';
          icon = Icons.person_pin_circle_rounded;
          color = const Color(0xFF1D4ED8);
          break;
        case 'en_camino':
          label = 'Tu pedido va en camino 🛵';
          icon = Icons.delivery_dining_rounded;
          color = const Color(0xFF1D4ED8);
          break;
        case 'entregado':
          label = 'Pedido entregado ✅';
          icon = Icons.check_circle_rounded;
          color = const Color(0xFF16A34A);
          break;
        default:
          label = d.status;
          icon = Icons.local_shipping_rounded;
          color = const Color(0xFF12327F);
      }
      return _deliveryCardShell(
        color: color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DELIVERY',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF888888),
                              letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(label,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: color)),
                      if (d.packageCount > 1) ...[
                        const SizedBox(height: 2),
                        Text('Delivery de ${d.packageCount} paquetes',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700])),
                      ],
                      if (d.delivererName != null &&
                          d.status != 'disponible') ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.person_rounded,
                                size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text('Repartidor: ${d.delivererName}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700])),
                          ],
                        ),
                      ],
                      if (d.deliveryAddress.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(d.deliveryAddress,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (d.status == 'en_camino') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          DeliveryRouteMap(packageId: d.packageId),
                    ),
                  ),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Ver ruta'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1D4ED8),
                    side: const BorderSide(color: Color(0xFF1D4ED8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Si ya pagó y no hay delivery, no mostramos nada (recogió en local)
    if (isPaid) return const SizedBox.shrink();

    // ── Caso: ya rechazó → ofrecer cambiar de opinión ─────────────────────────
    if (invoice.deliveryChoice == 'rechazado') {
      return _deliveryCardShell(
        color: const Color(0xFFFA4B0C),
        child: Row(
          children: [
            const Icon(Icons.store_mall_directory_outlined,
                color: Color(0xFF12327F), size: 24),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Elegiste recoger en el local. ¿Cambiaste de opinión?',
                  style: TextStyle(fontSize: 13, color: Color(0xFF12327F))),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _solicitarDelivery,
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFA4B0C)),
              child: const Text('Delivery',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }

    // ── Caso: decisión pendiente → preguntar cómo lo quiere recibir ───────────
    return _deliveryCardShell(
      color: const Color(0xFFFA4B0C),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded,
                  color: Color(0xFFFA4B0C), size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Tu paquete llegó a las instalaciones',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF12327F))),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('¿Cómo quieres recibirlo?',
              style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _recogerEnLocal,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF12327F),
                    side: const BorderSide(color: Color(0xFF12327F)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Recoger en local',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _solicitarDelivery,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFA4B0C),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                      'Delivery +\$${DatabaseHelper.deliveryCost.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _deliveryCardShell({required Color color, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildPackageSelector() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'TUS PAQUETES (${_activePackages.length})',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _activePackages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final p = _activePackages[i];
                final selected = p.id == _currentPackageId;
                return GestureDetector(
                  onTap: () => _selectPackage(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF12327F)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF12327F)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.inventory_2_rounded,
                          size: 15,
                          color: selected
                              ? Colors.white
                              : const Color(0xFFFA4B0C),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          p.trackingCode,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF12327F),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _createErrorTimeline() {
    return [
      {
        'status': 'Error',
        'date': DateTime.now().toUtc().toIso8601String(),
        'location': 'No se pudo cargar el historial',
      },
    ];
  }

  String get _currentStatus {
    if (_statusTimeline.isEmpty) return '';
    return _statusTimeline.last['status']?.toString().toLowerCase() ?? '';
  }

  LatLng get _currentMapLocation {
    return _locations[_currentStatus] ?? LatLng(17.5, -83.0);
  }

  List<Marker> get _mapMarkers {
    final markers = <Marker>[];

    for (final status in _statusTimeline) {
      final statusText = status['status']?.toString().toLowerCase() ?? '';
      final location = _locations[statusText];
      if (location == null) continue;

      final color = _getStatusColor(status['status']?.toString() ?? '');
      final isCurrentStatus = statusText == _currentStatus;

      markers.add(
        Marker(
          point: location,
          width: isCurrentStatus ? 50 : 36,
          height: isCurrentStatus ? 50 : 36,
          child: Tooltip(
            message: _locationNames[statusText] ?? statusText,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: isCurrentStatus ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: isCurrentStatus ? 10 : 5,
                    spreadRadius: isCurrentStatus ? 3 : 1,
                  ),
                ],
              ),
              child: Icon(
                _getStatusIcon(status['status']?.toString() ?? ''),
                color: Colors.white,
                size: isCurrentStatus ? 26 : 18,
              ),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  List<LatLng> get _routePoints {
    final points = <LatLng>[];
    for (final status in _statusTimeline) {
      final statusText = status['status']?.toString().toLowerCase() ?? '';
      final location = _locations[statusText];
      if (location != null) points.add(location);
    }
    return points;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'recibido':
        return Color(0xFF4CAF50);
      case 'en tránsito':
        return Color(0xFFFF9800);
      case 'en aduana':
        return Color(0xFFF44336);
      case 'listo para recoger':
        return Color(0xFF2196F3);
      case 'error':
        return Color(0xFF9C27B0);
      default:
        return Color(0xFF9E9E9E);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'recibido':
        return Icons.warehouse;
      case 'en tránsito':
        final method = _activePackage?.shippingMethodName ?? '';
        if (method == 'Aéreo') return Icons.flight;
        if (method == 'Marítimo') return Icons.directions_boat;
        return Icons.local_shipping;
      case 'en aduana':
        return Icons.assignment;
      case 'listo para recoger':
        return Icons.store;
      case 'error':
        return Icons.error;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildMapContent(MapController controller) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: _currentMapLocation,
        initialZoom: _currentStatus == 'en tránsito' ? 4.5 : 13,
        interactionOptions: InteractionOptions(
          flags:
              InteractiveFlag.pinchZoom |
              InteractiveFlag.drag |
              InteractiveFlag.doubleTapZoom,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.testapp',
        ),
        if (_routePoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                strokeWidth: 3,
                color: Color(0xFF12327F).withOpacity(0.6),
                pattern: StrokePattern.dotted(),
              ),
            ],
          ),
        MarkerLayer(markers: _mapMarkers),
      ],
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children:
            _statusTimeline.map((status) {
              final statusText = status['status']?.toString() ?? '';
              final color = _getStatusColor(statusText);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    _locationNames[statusText.toLowerCase()] ?? statusText,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              );
            }).toList(),
      ),
    );
  }

  void _showMapDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          insetPadding: EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.fromLTRB(20, 8, 12, 8),
                color: Color(0xFF12327F),
                child: Row(
                  children: [
                    Icon(Icons.map, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'UBICACIÓN DEL PAQUETE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.fullscreen_exit, color: Colors.white),
                      tooltip: 'Cerrar',
                    ),
                  ],
                ),
              ),
              // Mapa
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.60,
                child: _buildMapContent(_dialogMapController),
              ),
              // Leyenda
              _buildLegend(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMap() {
    return SizedBox(
      height: 250,
      child: Stack(
        children: [
          _buildMapContent(_mapController),
          Positioned(
            right: 10,
            bottom: 10,
            child: _MapRecenterButton(onTap: _fitRoute),
          ),
        ],
      ),
    );
  }

  /// Encuadra toda la ruta del paquete (o centra en el único punto disponible).
  void _fitRoute() {
    final pts = _routePoints;
    try {
      if (pts.length > 1) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: const EdgeInsets.all(50),
            maxZoom: 13,
          ),
        );
      } else if (pts.length == 1) {
        _mapController.move(pts.first, 13);
      } else {
        _mapController.move(_currentMapLocation, 5);
      }
    } catch (_) {
      // el mapa puede no estar listo; se ignora
    }
  }

  /// Mueve el mapa al ícono del estado indicado y desplaza la vista hasta el
  /// mapa para que se vea (al tocar "Ver" en el timeline).
  void _focusStatusOnMap(String statusText) {
    final loc = _locations[statusText.toLowerCase()];
    if (loc == null) return;
    final ctx = _mapCardKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(loc, 14);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 10,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: _buildContent(context),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF12327F)),
        ),
      );
    }

    if (_statusTimeline.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                  SizedBox(height: 20),
                  Text(
                    'No hay seguimientos activos',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loadUserPackages,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF12327F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: Size(double.infinity, 50),
                    ),
                    child: Text(
                      'Reintentar',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Selector de paquete (solo si hay más de uno activo)
        if (_activePackages.length > 1) _buildPackageSelector(),

        // Solo la PREGUNTA de delivery va arriba (¿cómo quieres recibirlo?).
        if (_deliveryPromptPending) _buildDeliveryCard(),

        // Tarjeta código de seguimiento
        Card(
          elevation: 8,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'CÓDIGO DE SEGUIMIENTO',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.confirmation_number, color: Color(0xFF12327F)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _currentTrackingCode,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF12327F),
                          ),
                        ),
                      ),
                      Icon(Icons.content_copy, color: Colors.grey[500]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Estado del delivery (en camino, etc.) va debajo del código.
        if (!_deliveryPromptPending) ...[
          const SizedBox(height: 16),
          _buildDeliveryCard(),
        ],

        SizedBox(height: 20),

        // Mapa
        Card(
          key: _mapCardKey,
          elevation: 8,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Icon(Icons.map, color: Color(0xFF12327F)),
                    SizedBox(width: 8),
                    Text(
                      'UBICACIÓN DEL PAQUETE',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Spacer(),
                    GestureDetector(
                      onTap: () => _showMapDialog(context),
                      child: Icon(Icons.fullscreen, color: Color(0xFF12327F)),
                    ),
                  ],
                ),
              ),
              _buildMap(),
              _buildLegend(),
            ],
          ),
        ),

        SizedBox(height: 20),

        // Timeline de estados
        Card(
          elevation: 8,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                ..._statusTimeline.asMap().entries.map((entry) {
                  final index = entry.key;
                  final status = entry.value;
                  final isFirst = index == 0;
                  final isLast = index == _statusTimeline.length - 1;
                  final statusText =
                      status['status']?.toString() ?? 'Estado desconocido';
                  final utcDate = DateTime.parse(
                    status['date']?.toString() ?? '',
                  );
                  final localDate = utcDate.toLocal();
                  final location =
                      status['location']?.toString() ?? 'Ubicación desconocida';
                  final statusColor = _getStatusColor(statusText);
                  final isCompleted = index < _statusTimeline.length - 1;

                  return Container(
                    margin: EdgeInsets.only(bottom: 20),
                    child: TimelineTile(
                      alignment: TimelineAlign.start,
                      isFirst: isFirst,
                      isLast: isLast,
                      indicatorStyle: IndicatorStyle(
                        width: 32,
                        height: 32,
                        color: isCompleted ? statusColor : Colors.white,
                        iconStyle: IconStyle(
                          iconData: _getStatusIcon(statusText),
                          color: isCompleted ? Colors.white : statusColor,
                        ),
                        padding: EdgeInsets.all(6),
                        indicator: Container(
                          decoration: BoxDecoration(
                            color: isCompleted ? statusColor : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: statusColor, width: 2),
                          ),
                          child: Center(
                            child: Icon(
                              _getStatusIcon(statusText),
                              size: 18,
                              color: isCompleted ? Colors.white : statusColor,
                            ),
                          ),
                        ),
                      ),
                      beforeLineStyle: LineStyle(
                        color: isFirst ? Colors.transparent : Color(0xFFE0E0E0),
                        thickness: 3,
                      ),
                      afterLineStyle: LineStyle(
                        color: isLast ? Colors.transparent : Color(0xFFE0E0E0),
                        thickness: 3,
                      ),
                      endChild: Container(
                        margin: EdgeInsets.only(left: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    statusText.toUpperCase(),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (isCompleted) ...[
                                  SizedBox(width: 10),
                                  Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF4CAF50),
                                    size: 20,
                                  ),
                                ],
                                if (_locations.containsKey(
                                    statusText.toLowerCase())) ...[
                                  const Spacer(),
                                  _SeeOnMapButton(
                                    color: statusColor,
                                    onTap: () => _focusStatusOnMap(statusText),
                                  ),
                                ],
                              ],
                            ),
                            SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 18,
                                  color: Colors.grey[600],
                                ),
                                SizedBox(width: 8),
                                Text(
                                  DateFormat(
                                    'dd MMM yyyy - HH:mm',
                                  ).format(localDate),
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.location_pin,
                                  size: 18,
                                  color: Colors.grey[600],
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    location,
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Botón "Ver" del timeline (lleva el mapa a ese estado) ──────────────────────

class _SeeOnMapButton extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _SeeOnMapButton({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.place_outlined, size: 14, color: color),
            const SizedBox(width: 4),
            Text('Ver',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ─── Botón flotante para recentrar el mapa ──────────────────────────────────────

class _MapRecenterButton extends StatelessWidget {
  final VoidCallback onTap;
  const _MapRecenterButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.center_focus_strong,
              color: Color(0xFF12327F), size: 22),
        ),
      ),
    );
  }
}
