import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/delivery.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';
import 'login_screen.dart';

const _navy = Color(0xFF12327F);
const _green = Color(0xFF16A34A);
const _greenBg = Color(0xFFDCFCE7);
const _orange = Color(0xFFFA4B0C);
const _orangeBg = Color(0xFFFFF0EB);
const _blueBg = Color(0xFFEFF6FF);
const _blue = Color(0xFF1D4ED8);
class RepartidorHomeScreen extends StatefulWidget {
  const RepartidorHomeScreen({super.key});

  @override
  State<RepartidorHomeScreen> createState() => _RepartidorHomeScreenState();
}

class _RepartidorHomeScreenState extends State<RepartidorHomeScreen> {
  int _currentIndex = 0;
  final _supabase = Supabase.instance.client;
  final _db = DatabaseHelper();

  String get _userId => _supabase.auth.currentUser?.id ?? '';

  bool _isAvailable = false;
  bool _loadingAvailability = true;

  final _disponiblesKey = GlobalKey<_DisponiblesTabState>();
  final _misPedidosKey = GlobalKey<_MisPedidosTabState>();
  final _historialKey = GlobalKey<_HistorialTabState>();

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    NotificationService.initialize();
    _loadAvailability();
    _tabs = [
      _DisponiblesTab(key: _disponiblesKey, delivererId: _userId),
      _MisPedidosTab(key: _misPedidosKey, delivererId: _userId),
      _HistorialTab(key: _historialKey, delivererId: _userId),
    ];
  }

  Future<void> _loadAvailability() async {
    try {
      final value = await _db.getMyAvailability(_userId);
      if (mounted) setState(() => _isAvailable = value);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingAvailability = false);
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    setState(() => _isAvailable = value);
    try {
      await _db.setAvailability(_userId, value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(value
              ? 'Estás disponible. Recibirás nuevos pedidos.'
              : 'Estás desconectado. No recibirás pedidos.'),
          backgroundColor: value ? _green : Colors.grey.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      // Revertir si falla
      if (mounted) setState(() => _isAvailable = !value);
    }
  }

  void _onTabSelected(int index) {
    setState(() => _currentIndex = index);
    // Recargar el tab seleccionado para mostrar datos frescos
    if (index == 0) _disponiblesKey.currentState?.reload();
    if (index == 1) _misPedidosKey.currentState?.reload();
    if (index == 2) _historialKey.currentState?.reload();
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabSelected(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? _green.withValues(alpha: 0.1) : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? _green : Colors.grey.shade500, size: 24),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? _green : Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityBanner() {
    final on = _isAvailable;
    return Container(
      width: double.infinity,
      color: on ? _greenBg : const Color(0xFFF1F1F1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: on ? _green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(on ? 'Disponible' : 'Desconectado',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: on ? _green : Colors.grey.shade700)),
                Text(
                  on
                      ? 'Recibirás nuevos pedidos'
                      : 'No recibirás pedidos',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (_loadingAvailability)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: _green, strokeWidth: 2))
          else
            Switch(
              value: on,
              onChanged: _toggleAvailability,
              activeThumbColor: _green,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text(
          'SEMTRACAR',
          style: TextStyle(
            color: _orange,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: _navy),
            onPressed: () async {
              final nav = Navigator.of(context);
              await _supabase.auth.signOut();
              nav.pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 0.5),
        ),
      ),
      body: Column(
        children: [
          _buildAvailabilityBanner(),
          Expanded(
            child: IndexedStack(index: _currentIndex, children: _tabs),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 16,
                offset: const Offset(0, -3))
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(0, Icons.local_shipping_outlined, 'Disponibles'),
                _navItem(1, Icons.delivery_dining_rounded, 'Mis pedidos'),
                _navItem(2, Icons.history_rounded, 'Historial'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tab: Disponibles ──────────────────────────────────────────────────────────

class _DisponiblesTab extends StatefulWidget {
  final String delivererId;
  const _DisponiblesTab({super.key, required this.delivererId});

  @override
  State<_DisponiblesTab> createState() => _DisponiblesTabState();
}

class _DisponiblesTabState extends State<_DisponiblesTab> {
  final _db = DatabaseHelper();
  List<Delivery> _deliveries = [];
  bool _loading = true;
  final Set<String> _accepting = {};
  Timer? _timer;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    // Realtime: nuevos pedidos y cambios de estado llegan al instante.
    _channel = Supabase.instance.client
        .channel('repartidor-disponibles-${widget.delivererId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'deliveries',
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            final id = rec['id'] as String?;
            final status = rec['status'] as String?;
            final inList = _deliveries.any((d) => d.id == id);
            // Recargar solo si aparece un pedido disponible o cambió uno de la
            // lista; ignora los pings de ubicación de pedidos en camino.
            if (id == null || status == 'disponible' || inList) {
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
    super.dispose();
  }

  void reload() => _load();

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await _db.getAvailableDeliveries();
      if (mounted) setState(() => _deliveries = list);
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _accept(Delivery delivery) async {
    // Evitar doble toque sobre el mismo pedido
    if (_accepting.contains(delivery.id)) return;
    _accepting.add(delivery.id);
    final ok = await _db.acceptDelivery(delivery.id, widget.delivererId);
    _accepting.remove(delivery.id);
    if (!mounted) return;
    if (ok) {
      await _db.sendNotification(
        title: '🛵 Tu pedido fue aceptado',
        body: 'Un repartidor va en camino a recoger tu paquete.',
        userIds: [delivery.clientId],
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('¡Pedido aceptado! Ve a "Mis pedidos"'),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
      ));
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Otro repartidor ya tomó este pedido'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _green));
    }
    if (_deliveries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: _green,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 56, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('No hay pedidos disponibles',
                        style: TextStyle(
                            fontSize: 16, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _green,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _deliveries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _DeliveryCard(
          delivery: _deliveries[i],
          action: ElevatedButton.icon(
            onPressed: () => _accept(_deliveries[i]),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Aceptar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tab: Mis pedidos ──────────────────────────────────────────────────────────

class _MisPedidosTab extends StatefulWidget {
  final String delivererId;
  const _MisPedidosTab({super.key, required this.delivererId});

  @override
  State<_MisPedidosTab> createState() => _MisPedidosTabState();
}

class _MisPedidosTabState extends State<_MisPedidosTab> {
  final _db = DatabaseHelper();
  List<Delivery> _deliveries = [];
  bool _loading = true;
  Timer? _timer;
  StreamSubscription<Position>? _posSub;
  bool _locationActive = false;
  bool _locationStarting = false;
  String _gpsStatus = ''; // indicador visible del estado del GPS

  void _setGps(String s) {
    if (mounted) setState(() => _gpsStatus = s);
    debugPrint('🛰️GPS estado: $s');
  }

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    // Realtime: cambios en las entregas llegan al instante.
    _channel = Supabase.instance.client
        .channel('repartidor-mispedidos-${widget.delivererId}')
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
    _posSub?.cancel();
    super.dispose();
  }

  void reload() => _load();

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await _db.getMyDeliveries(widget.delivererId);
      if (mounted) setState(() => _deliveries = list);
      _syncLocationSharing();
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  // ── Compartir ubicación mientras hay pedidos "en camino" ──────────────────
  List<Delivery> get _enCamino =>
      _deliveries.where((d) => d.status == 'en_camino').toList();

  void _syncLocationSharing() {
    debugPrint('🛰️GPS sync: enCamino=${_enCamino.length} '
        'active=$_locationActive starting=$_locationStarting');
    if (_enCamino.isNotEmpty) {
      _startLocationSharing();
    } else {
      _stopLocationSharing();
    }
  }

  Future<void> _startLocationSharing() async {
    // Evitar solicitudes concurrentes de permiso (Android solo permite una a
    // la vez). El flag se activa de inmediato, antes de cualquier await.
    if (_locationActive || _locationStarting) return;
    _locationStarting = true;
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      debugPrint('🛰️GPS serviceEnabled=$serviceOn');
      if (!serviceOn) {
        _setGps('GPS del teléfono apagado — actívalo');
        return;
      }
      var permission = await Geolocator.checkPermission();
      debugPrint('🛰️GPS permission(check)=$permission');
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        debugPrint('🛰️GPS permission(request)=$permission');
      }
      // Denegado permanentemente: Android ya no muestra el diálogo, hay que ir
      // a Ajustes a habilitarlo manualmente.
      if (permission == LocationPermission.deniedForever) {
        _setGps('Permiso de ubicación bloqueado — abre Ajustes');
        if (mounted) {
          final goSettings = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Permiso de ubicación'),
              content: const Text(
                  'El permiso de ubicación está bloqueado. Actívalo en Ajustes '
                  'para que el cliente pueda ver tu ruta.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Ahora no')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Abrir Ajustes')),
              ],
            ),
          );
          if (goSettings == true) {
            await Geolocator.openAppSettings();
          }
        }
        return;
      }
      if (permission == LocationPermission.denied) {
        _setGps('Sin permiso de ubicación');
        return;
      }

      _locationActive = true;
      _setGps('Activando ubicación…');
      debugPrint('🛰️GPS sharing ACTIVADO');

      // Stream de ubicación con SERVICIO EN PRIMER PLANO: sigue compartiendo
      // aunque el repartidor minimice la app o apague la pantalla (con una
      // notificación persistente, como Uber).
      final settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // actualiza cuando se mueve ~10m
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Semtracar',
          notificationText: 'Compartiendo tu ubicación con el cliente',
          enableWakeLock: true,
        ),
      );

      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen(_onPosition, onError: (e) {
        debugPrint('🛰️GPS stream error: $e');
        _setGps('Error al compartir: $e');
      });
    } finally {
      _locationStarting = false;
    }
  }

  void _stopLocationSharing() {
    _posSub?.cancel();
    _posSub = null;
    _locationActive = false;
    if (_gpsStatus.isNotEmpty) _setGps('');
  }

  void _onPosition(Position pos) {
    final activos = _enCamino;
    if (activos.isEmpty) {
      _stopLocationSharing();
      return;
    }
    debugPrint('🛰️GPS pos=${pos.latitude},${pos.longitude} '
        '-> ${activos.length} pedido(s)');
    for (final d in activos) {
      _db.updateDelivererLocation(d.id, pos.latitude, pos.longitude);
    }
    final hora = TimeOfDay.now();
    _setGps('Compartiendo ubicación ✓ '
        '(${hora.hour.toString().padLeft(2, '0')}:'
        '${hora.minute.toString().padLeft(2, '0')})');
  }

  Future<void> _updateStatus(Delivery d, String newStatus) async {
    if (newStatus == 'entregado') {
      await _confirmDelivery(d);
      return;
    }

    // En camino
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Marcar como en camino',
            style: TextStyle(
                color: _navy, fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
            '¿Confirmas que el pedido de ${d.clientName ?? 'el cliente'} está en camino?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            child: const Text('Confirmar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _db.updateDeliveryStatus(d.id, 'en_camino');
    await _db.sendNotification(
      title: '🚀 Tu pedido va en camino',
      body: 'El repartidor está llevando tu paquete a tu dirección.',
      userIds: [d.clientId],
    );
    _load();
  }

  /// Flujo de entrega + cobro contra entrega. Si el recibo ya está pagado
  /// (p. ej. transferencia por adelantado), solo confirma la entrega.
  Future<void> _confirmDelivery(Delivery d) async {
    // Consultar saldo pendiente (server-side, RLS-safe).
    double balance;
    try {
      balance = await _db.deliveryBalance(d.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
      return;
    }
    if (!mounted) return;

    String method = 'efectivo';

    if (balance <= 0.009) {
      // Ya pagado: solo confirmar la entrega.
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Confirmar entrega',
              style: TextStyle(
                  color: _navy, fontWeight: FontWeight.w700, fontSize: 16)),
          content: Text(
              'Este pedido de ${d.clientName ?? 'el cliente'} ya está pagado. '
              '¿Confirmas la entrega?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: _green),
              child: const Text('Entregado',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    } else {
      // Hay saldo: cobrar y elegir método.
      final chosen = await _askPaymentMethod(balance);
      if (chosen == null) return;
      method = chosen;
    }

    // Evidencia de entrega: foto del paquete entregado (protege ante disputas
    // del cobro contra entrega). Se puede omitir si no es posible tomarla.
    final photo = await _captureProofPhoto();

    await _db.completeDelivery(d.id, method);

    if (photo != null) {
      try {
        await _db.uploadDeliveryProof(d.id, photo);
      } catch (e) {
        debugPrint('Error subiendo evidencia: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('La entrega se registró, pero la foto no se pudo subir.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    }

    await _db.sendNotification(
      title: '✅ ¡Pedido entregado!',
      body: 'Tu paquete fue entregado exitosamente.',
      userIds: [d.clientId],
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Entrega registrada'),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
      ));
    }
    _load();
  }

  /// Pide al repartidor una foto del paquete entregado como evidencia.
  /// Devuelve los bytes de la imagen, o null si la omitió o falló la cámara.
  Future<Uint8List?> _captureProofPhoto() async {
    final take = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Foto de evidencia',
            style: TextStyle(
                color: _navy, fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text(
            'Toma una foto del paquete entregado como comprobante de la entrega.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Omitir'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _green, foregroundColor: Colors.white),
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: const Text('Tomar foto'),
          ),
        ],
      ),
    );
    if (take != true) return null;
    try {
      final shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        imageQuality: 70,
      );
      if (shot == null) return null;
      return await shot.readAsBytes();
    } catch (e) {
      debugPrint('Error tomando foto de evidencia: $e');
      return null;
    }
  }

  /// Pregunta cómo cobró el repartidor. Devuelve 'efectivo' o 'transferencia',
  /// o null si se cancela.
  Future<String?> _askPaymentMethod(double amount) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Registrar cobro',
            style: TextStyle(
                color: _navy, fontWeight: FontWeight.w700, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total a cobrar: \$${amount.toStringAsFixed(2)}',
                style:
                    const TextStyle(fontSize: 13, color: Color(0xFF666666))),
            const SizedBox(height: 14),
            const Text('¿Cómo pagó el cliente?',
                style: TextStyle(fontSize: 13, color: _navy)),
            const SizedBox(height: 10),
            _methodTile(ctx, 'efectivo', 'Efectivo', Icons.payments_outlined),
            const SizedBox(height: 8),
            _methodTile(ctx, 'transferencia', 'Transferencia',
                Icons.account_balance_outlined),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: _navy)),
          ),
        ],
      ),
    );
  }

  Widget _methodTile(
      BuildContext ctx, String value, String label, IconData icon) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: _navy),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: _navy)),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Color(0xFFBBBBBB)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _green));
    }
    if (_deliveries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: _green,
        child: ListView(children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delivery_dining_outlined,
                      size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('No tienes pedidos activos',
                      style: TextStyle(
                          fontSize: 16, color: Colors.grey.shade500)),
                ],
              ),
            ),
          )
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _green,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_gpsStatus.isNotEmpty) ...[
            _buildGpsBanner(),
            const SizedBox(height: 12),
          ],
          for (int i = 0; i < _deliveries.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _DeliveryCard(
              delivery: _deliveries[i],
              showClientContact: true,
              action: _deliveries[i].status == 'aceptado'
                  ? ElevatedButton.icon(
                      onPressed: () =>
                          _updateStatus(_deliveries[i], 'en_camino'),
                      icon: const Icon(Icons.directions_run_rounded, size: 18),
                      label: const Text('En camino'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: () =>
                          _updateStatus(_deliveries[i], 'entregado'),
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 18),
                      label: const Text('Entregado'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGpsBanner() {
    final ok = _gpsStatus.startsWith('Compartiendo');
    final color = ok ? _green : _orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.my_location : Icons.location_disabled,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_gpsStatus,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ),
        ],
      ),
    );
  }
}

// ─── Tab: Historial ────────────────────────────────────────────────────────────

class _HistorialTab extends StatefulWidget {
  final String delivererId;
  const _HistorialTab({super.key, required this.delivererId});

  @override
  State<_HistorialTab> createState() => _HistorialTabState();
}

class _HistorialTabState extends State<_HistorialTab> {
  final _db = DatabaseHelper();
  List<Delivery> _deliveries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void reload() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _db.getMyDeliveryHistory(widget.delivererId);
      if (mounted) setState(() => _deliveries = list);
    } catch (e) {
      debugPrint('Error cargando historial repartidor: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _green));
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _load,
        color: _green,
        child: ListView(children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48, color: Colors.red.shade300),
                    const SizedBox(height: 12),
                    Text('No se pudo cargar el historial',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ),
          )
        ]),
      );
    }

    final entregados = _deliveries.where((d) => d.status == 'entregado').length;

    return RefreshIndicator(
      onRefresh: _load,
      color: _green,
      child: _deliveries.isEmpty
          ? ListView(children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_toggle_off_outlined,
                          size: 56, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('Sin historial aún',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              )
            ])
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Resumen
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _greenBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.local_shipping_rounded,
                          color: _green, size: 32),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$entregados',
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: _green)),
                          const Text('Pedidos entregados',
                              style: TextStyle(
                                  fontSize: 13, color: _green)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ..._deliveries.map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DeliveryCard(delivery: d),
                    )),
              ],
            ),
    );
  }
}

// ─── Tarjeta de delivery reutilizable ─────────────────────────────────────────

class _DeliveryCard extends StatelessWidget {
  final Delivery delivery;
  final Widget? action;
  final bool showClientContact;

  const _DeliveryCard({
    required this.delivery,
    this.action,
    this.showClientContact = false,
  });

  Color get _statusBg {
    switch (delivery.status) {
      case 'disponible': return _orangeBg;
      case 'aceptado':   return _blueBg;
      case 'en_camino':  return _blueBg;
      case 'entregado':  return _greenBg;
      default:           return const Color(0xFFF1EFE8);
    }
  }

  Color get _statusFg {
    switch (delivery.status) {
      case 'disponible': return _orange;
      case 'aceptado':   return _blue;
      case 'en_camino':  return _blue;
      case 'entregado':  return _green;
      default:           return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: _statusBg,
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.delivery_dining_rounded,
                    color: _statusFg, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(delivery.clientName ?? 'Cliente',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: _navy)),
                    const SizedBox(height: 2),
                    Text(
                      delivery.deliveryAddress,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF666666)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                child: Text(Delivery.statusLabel(delivery.status),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _statusFg)),
              ),
            ],
          ),

          // Dirección completa
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 15, color: _orange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(delivery.deliveryAddress,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF444444))),
              ),
            ],
          ),

          // Paquete(s) — código(s) de seguimiento
          if (delivery.packageTracking != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 15, color: _navy),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    delivery.packageCount > 1
                        ? '${delivery.packageCount} paquetes: ${delivery.packageTracking}'
                        : 'Paquete: ${delivery.packageTracking}',
                    style: const TextStyle(
                        fontSize: 13,
                        color: _navy,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],

          // Teléfono (solo en "Mis pedidos")
          if (showClientContact && delivery.clientPhone != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 15, color: _green),
                const SizedBox(width: 6),
                Text(delivery.clientPhone!,
                    style: const TextStyle(
                        fontSize: 13,
                        color: _green,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],

          // Acción
          if (action != null) ...[
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: action!),
          ],
        ],
      ),
    );
  }
}
