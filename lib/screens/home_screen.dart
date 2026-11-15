import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './tabs/tracking_tab.dart';
import './tabs/history_tab.dart';
import './tabs/profile_tab.dart';
import './tabs/calculator_tab.dart';
import 'package:testapp/services/notification_service.dart';
import 'package:testapp/services/database_helper.dart';
import 'package:testapp/models/invoice.dart';
import 'package:testapp/widgets/delivery_request_sheet.dart';
import 'package:testapp/widgets/multi_delivery_request_sheet.dart';

class HomeScreen extends StatefulWidget {
  final String userId;

  const HomeScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animationController;
  late final Animation<double> _animation;
  late List<Widget> _tabs;
  int _currentIndex = 0;

  final _db = DatabaseHelper();
  bool _checkingDeliveries = false;
  RealtimeChannel? _invoiceChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _animation = Tween<double>(begin: -0.1, end: 0.1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.repeat(reverse: true);

    _tabs = [
      TrackingTab(userId: widget.userId),
      HistoryTab(),
      CalculatorTab(),
      ProfileTab(),
    ];

    NotificationService.initialize();

    // Revisar paquetes que llegaron y aún no decidieron delivery
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingDeliveries();
    });

    _watchInvoices();
  }

  /// Escucha en tiempo real los recibos del usuario. El recibo se crea cuando
  /// el paquete llega a "Listo para recoger", así que al aparecer uno nuevo
  /// mostramos el popup de delivery sin que el cliente tenga que refrescar.
  void _watchInvoices() {
    _invoiceChannel = Supabase.instance.client
        .channel('invoices-watch-${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'invoices',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (_) {
            // Pequeña espera para asegurar que el recibo esté legible.
            Future.delayed(const Duration(milliseconds: 400),
                _checkPendingDeliveries);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _invoiceChannel?.unsubscribe();
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingDeliveries();
    }
  }

  Future<void> _checkPendingDeliveries() async {
    if (_checkingDeliveries || !mounted) return;
    _checkingDeliveries = true;
    try {
      final pending = await _db.getPendingDeliveryInvoices();
      if (!mounted || pending.isEmpty) return;
      await _promptDelivery(pending);
    } catch (_) {
      // ignore
    } finally {
      _checkingDeliveries = false;
    }
  }

  /// Popup chico al entrar/volver a la app: pregunta si desea delivery.
  /// Si acepta, abre la SELECCIÓN de paquetes (checkboxes) cuando hay varios
  /// listos, o el formulario directo cuando hay solo uno.
  Future<void> _promptDelivery(List<Invoice> pending) async {
    final multiple = pending.length > 1;
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_rounded,
                color: Color(0xFFFA4B0C), size: 44),
            const SizedBox(height: 10),
            Text(
                multiple
                    ? 'Tienes ${pending.length} paquetes listos'
                    : '¡Tu paquete llegó!',
                style: const TextStyle(
                    color: Color(0xFF12327F),
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
                textAlign: TextAlign.center),
          ],
        ),
        content: Text(
          multiple
              ? 'Tus paquetes están en nuestras instalaciones. '
                  '¿Deseas solicitar delivery a domicilio?'
              : 'Tu paquete está en nuestras instalaciones. '
                  '¿Deseas solicitar delivery a domicilio '
                  '(+\$${DatabaseHelper.deliveryCost.toStringAsFixed(2)})?',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Color(0xFF555555)),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Recoger en local',
                style: TextStyle(color: Color(0xFF12327F))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFA4B0C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Solicitar delivery'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (choice == true) {
      await _openDeliverySelection(pending);
    } else if (choice == false) {
      // "Recoger en local" → declina todos los pendientes.
      for (final inv in pending) {
        await _db.declineDelivery(inv.id);
      }
    }
  }

  /// Abre la selección: con varios paquetes entregables, la hoja de checkboxes;
  /// con uno solo, el formulario directo. Incluye los paquetes que se
  /// declinaron antes ("recoger en local") por si quiere sumarlos.
  Future<void> _openDeliverySelection(List<Invoice> trigger) async {
    List<Invoice> deliverable = [];
    try {
      deliverable = await _db.getDeliverableInvoices();
    } catch (_) {}
    if (!mounted) return;
    final list = deliverable.isNotEmpty ? deliverable : trigger;
    if (list.length == 1) {
      final inv = list.first;
      final packageId =
          inv.items.isNotEmpty ? inv.items.first.packageId : null;
      if (packageId == null) return;
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DeliveryRequestSheet(
          invoiceId: inv.id,
          packageId: packageId,
          userAddress: inv.deliveryAddress,
        ),
      );
    } else {
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => MultiDeliveryRequestSheet(pendingInvoices: list),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)!.isCurrent) {
      _animationController.repeat(reverse: true);
    } else {
      _animationController.stop();
    }
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color:
              isSelected
                  ? const Color(0xFFFA4B0C).withOpacity(0.08)
                  : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color:
                  isSelected ? const Color(0xFFFA4B0C) : Colors.grey.shade500,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color:
                    isSelected ? const Color(0xFFFA4B0C) : Colors.grey.shade500,
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text(
          'SEMTRACAR',
          style: TextStyle(
            color: Color(0xFFFA4B0C),
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: RotationTransition(
              turns: _animation,
              child: const Icon(Icons.rocket_launch, color: Color(0xFF12327F)),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade300, height: 0.5),
        ),
      ),
      body: _tabs[_currentIndex],
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
                _buildNavItem(0, Icons.track_changes_rounded, 'Rastreo'),
                _buildNavItem(1, Icons.history_rounded, 'Historial'),
                _buildNavItem(2, Icons.calculate_rounded, 'Calcular'),
                _buildNavItem(3, Icons.person_rounded, 'Perfil'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
