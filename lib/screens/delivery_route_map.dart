import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/delivery.dart';
import '../services/database_helper.dart';

const _navy = Color(0xFF12327F);
const _orange = Color(0xFFFA4B0C);
const _blue = Color(0xFF1D4ED8);

/// Mapa en vivo con la ubicación del repartidor y la del propio cliente.
/// Hace polling cada pocos segundos a la fila de la entrega.
class DeliveryRouteMap extends StatefulWidget {
  final String packageId;
  const DeliveryRouteMap({super.key, required this.packageId});

  @override
  State<DeliveryRouteMap> createState() => _DeliveryRouteMapState();
}

class _DeliveryRouteMapState extends State<DeliveryRouteMap> {
  final _db = DatabaseHelper();
  final _mapController = MapController();
  Delivery? _delivery;
  bool _loading = true;
  Timer? _timer;

  double? _myLat;
  double? _myLng;
  bool _userInteracted = false; // si el usuario movió el mapa a mano

  @override
  void initState() {
    super.initState();
    _loadMyLocation();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  LatLng? get _delivererPoint {
    final d = _delivery;
    if (d != null && d.hasLiveLocation) {
      return LatLng(d.delivererLat!, d.delivererLng!);
    }
    return null;
  }

  LatLng? get _myPoint =>
      (_myLat != null && _myLng != null) ? LatLng(_myLat!, _myLng!) : null;

  Future<void> _loadMyLocation() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _myLat = pos.latitude;
        _myLng = pos.longitude;
      });
      _maybeFit();
    } catch (_) {
      // sin ubicación del cliente, mostramos solo al repartidor
    }
  }

  Future<void> _load() async {
    try {
      final d = await _db.getDeliveryForPackage(widget.packageId);
      if (!mounted) return;
      setState(() {
        _delivery = d;
        _loading = false;
      });
      _maybeFit();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Ajusta la cámara para que se vean ambos puntos (o uno solo si falta el
  /// otro). No hace nada si el usuario ya movió el mapa manualmente.
  void _maybeFit({bool force = false}) {
    if (_userInteracted && !force) return;
    final me = _myPoint;
    final del = _delivererPoint;
    try {
      if (me != null && del != null) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([me, del]),
            padding: const EdgeInsets.all(70),
            maxZoom: 16.5,
          ),
        );
      } else if (del != null) {
        _mapController.move(del, 15);
      } else if (me != null) {
        _mapController.move(me, 15);
      }
    } catch (_) {
      // el mapa puede no estar listo todavía; se reintenta en el próximo poll
    }
  }

  String _ago(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'hace ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    return 'hace ${diff.inHours} h';
  }

  @override
  Widget build(BuildContext context) {
    final d = _delivery;
    final del = _delivererPoint;
    final me = _myPoint;
    final hasLoc = del != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Ruta del repartidor',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _navy))
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        del ?? me ?? const LatLng(12.136389, -86.251389),
                    initialZoom: 13,
                    onPositionChanged: (pos, hasGesture) {
                      if (hasGesture && !_userInteracted) {
                        setState(() => _userInteracted = true);
                      }
                    },
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.pinchZoom |
                          InteractiveFlag.drag |
                          InteractiveFlag.doubleTapZoom,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.testapp',
                    ),
                    // Línea entre ambos
                    if (me != null && del != null)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: [me, del],
                          strokeWidth: 3,
                          color: _navy.withValues(alpha: 0.5),
                          pattern: StrokePattern.dotted(),
                        ),
                      ]),
                    MarkerLayer(markers: [
                      if (del != null)
                        Marker(
                          point: del,
                          width: 54,
                          height: 54,
                          child: _MarkerPin(
                            color: _orange,
                            icon: Icons.delivery_dining_rounded,
                          ),
                        ),
                      if (me != null)
                        Marker(
                          point: me,
                          width: 48,
                          height: 48,
                          child: _MarkerPin(
                            color: _blue,
                            icon: Icons.person_pin_circle_rounded,
                          ),
                        ),
                    ]),
                  ],
                ),

                // Tarjeta de estado arriba
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_pin_circle_rounded,
                                color: _orange, size: 26),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d?.delivererName ?? 'Repartidor',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: _navy)),
                                  Text(
                                    hasLoc
                                        ? 'Ubicación actualizada ${_ago(d!.locationUpdatedAt!)}'
                                        : 'El repartidor aún no comparte su ubicación',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Leyenda
                        Row(
                          children: [
                            _legendDot(_orange, 'Repartidor'),
                            const SizedBox(width: 16),
                            _legendDot(
                                _blue, me != null ? 'Tú' : 'Tú (sin ubicación)'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Botón recentrar (ver ambos)
                Positioned(
                  right: 16,
                  bottom: 24,
                  child: FloatingActionButton(
                    backgroundColor: Colors.white,
                    foregroundColor: _navy,
                    onPressed: () {
                      setState(() => _userInteracted = false);
                      _maybeFit(force: true);
                    },
                    child: const Icon(Icons.center_focus_strong),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }
}

class _MarkerPin extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _MarkerPin({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 26),
    );
  }
}
