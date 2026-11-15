import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/package.dart';
import 'package:testapp/models/user.dart' as app_models;
import '../models/invoice.dart';
import '../models/delivery.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;

  final SupabaseClient _supabase = Supabase.instance.client;

  DatabaseHelper._internal();

  // Query reutilizable para paquetes con joins
  static const String _packageQuery = '''
    *,
    shipping_methods:shipping_method_id(name),
    package_types:package_type_id(name),
    status_history:package_status_history(
      status_types:status_id(name),
      created_at,
      notes
    )
  ''';

  // Mapa de estados a IDs — fuente única de verdad
  static const Map<String, int> _statusMap = {
    'Recibido': 1,
    'En tránsito': 2,
    'En aduana': 3,
    'Listo para recoger': 4,
  };

  int _mapStatusToId(String status) {
    final id = _statusMap[status];
    if (id == null) throw Exception('Estado no válido: $status');
    return id;
  }

  // ── Validaciones ───────────────────────────────────────────────────────────

  Future<bool> checkEmailExists(String email) async {
    final response =
        await _supabase
            .from('users')
            .select('id')
            .ilike('email', email.trim())
            .maybeSingle();
    return response != null;
  }

  Future<bool> checkNameLastNameExists(String name, String lastName) async {
    final response =
        await _supabase
            .from('users')
            .select('id')
            .eq('name', name)
            .eq('last_name', lastName)
            .maybeSingle();
    return response != null;
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  Future<AuthResponse> registerUser(
    String name,
    String lastName,
    String email,
    String password,
  ) async {
    try {
      // Verificar email en la tabla users (ya confirmados)
      final emailExists =
          await _supabase
              .from('users')
              .select('id')
              .ilike('email', email.trim())
              .maybeSingle();

      if (emailExists != null) throw 'El email ya está registrado';

      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'name': name, 'last_name': lastName},
      );

      if (authResponse.user == null) throw 'Error al registrar usuario';

      // Supabase devuelve identities vacío cuando el email ya existe en auth
      if (authResponse.user!.identities != null &&
          authResponse.user!.identities!.isEmpty) {
        throw 'El email ya está registrado';
      }

      return authResponse;
    } catch (e) {
      throw '${e.toString()}';
    }
  }

  Future<app_models.User?> validateUser(String email, String password) async {
    try {
      final authResponse = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (authResponse.user == null) return null;

      final userData =
          await _supabase
              .from('users')
              .select()
              .eq('id', authResponse.user!.id)
              .single();

      return app_models.User.fromMap(userData);
    } on AuthException catch (e) {
      debugPrint('Error de autenticación: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Error inesperado en validateUser: $e');
      return null;
    }
  }

  // ── Usuarios ───────────────────────────────────────────────────────────────

  Future<List<app_models.User>> getAllUsers() async {
    final response = await _supabase
        .from('users')
        .select()
        .order('name', ascending: true);
    return (response as List)
        .map((map) => app_models.User.fromMap(map))
        .toList();
  }

  Future<app_models.User> getUser(String userId) async {
    final response =
        await _supabase.from('users').select().eq('id', userId).single();
    return app_models.User.fromMap(response);
  }

  Future<void> updateUserProfile(
    String userId,
    String name,
    String lastName,
    String email, {
    String? address,
  }) async {
    await _supabase
        .from('users')
        .update({
          'name': name,
          'last_name': lastName,
          'email': email,
          if (address != null) 'address': address,
        })
        .eq('id', userId);
  }

  // ── Paquetes ───────────────────────────────────────────────────────────────

  Future<List<Package>> getAllPackages() async {
    final response = await _supabase
        .from('packages')
        .select(_packageQuery)
        .order('created_at', ascending: false)
        .limit(50);
    return (response as List).map((map) => Package.fromMap(map)).toList();
  }

  Future<List<Package>> getPackagesByUser(String userId) async {
    final response = await _supabase
        .from('packages')
        .select(_packageQuery)
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    if (response.isEmpty) return [];

    return response.map((map) => Package.fromMap(map)).toList();
  }

  Future<List<Package>> getCurrentUserPackages() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Usuario no autenticado');
    return getPackagesByUser(userId);
  }

  Future<Package?> getPackageByTrackingCode(String trackingCode) async {
    try {
      final data =
          await _supabase
              .from('packages')
              .select()
              .eq('tracking_code', trackingCode)
              .maybeSingle();

      if (data == null) return null;
      return Package.fromMap(data);
    } catch (e) {
      throw Exception(
        'El código de seguimiento ya está en uso. Por favor, use un código único.',
      );
    }
  }

  Future<String> insertPackage(Package package) async {
    final response =
        await _supabase
            .from('packages')
            .insert(package.toMap())
            .select('id')
            .single();

    final packageId = response['id'] as String;

    await _supabase.from('package_status_history').insert({
      'package_id': packageId,
      'status_id': 1,
      'notes': 'Recibido en Estados Unidos',
      'created_at': package.createdAt.toUtc().toIso8601String(),
    });

    return packageId;
  }

  Future<void> updatePackagePaymentStatus(String packageId, bool isPaid) async {
    await _supabase
        .from('packages')
        .update({'is_paid': isPaid})
        .eq('id', packageId);
  }

  Future<void> updatePackageStatus(
    String packageId,
    String newStatus,
    String location,
  ) async {
    try {
      await _supabase.from('package_status_history').insert({
        'package_id': packageId,
        'status_id': _mapStatusToId(newStatus),
        'notes': location,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error en updatePackageStatus: $e');
      rethrow;
    }
  }
  // ── Facturación (recibos + pagos) ───────────────────────────────────────────

  static const double deliveryCost = 3.58;

  static const String _invoiceQuery = '''
    *,
    invoice_items(*),
    payments(*),
    issuer:issued_by(name, last_name)
  ''';

  Future<List<Package>> getUnpaidPackagesByUser(String userId) async {
    final packages = await getPackagesByUser(userId);
    return packages.where((p) =>
      !p.isPaid &&
      (p.statusHistory?.isNotEmpty ?? false) &&
      p.statusHistory!.last['status'] == 'Listo para recoger'
    ).toList();
  }

  Future<Invoice> createInvoice({
    required String userId,
    required List<Package> packages,
  }) async {
    if (packages.isEmpty) throw 'Selecciona al menos un paquete';

    // RPC transaccional: crea el recibo y sus ítems en una sola transacción
    // (evita recibos huérfanos si falla la inserción de ítems).
    final invoiceId = await _supabase.rpc('create_invoice', params: {
      'p_user_id': userId,
      'p_package_ids': packages.map((p) => p.id).toList(),
    });

    return getInvoiceById(invoiceId as String);
  }

  Future<Invoice> getInvoiceById(String invoiceId) async {
    final data =
        await _supabase
            .from('invoices')
            .select(_invoiceQuery)
            .eq('id', invoiceId)
            .single();
    return Invoice.fromMap(data);
  }

  Future<List<Invoice>> getAllInvoices() async {
    final response = await _supabase
        .from('invoices')
        .select(_invoiceQuery)
        .order('created_at', ascending: false);
    return (response as List).map((m) => Invoice.fromMap(m)).toList();
  }

  Future<List<Invoice>> getInvoicesByUser(String userId) async {
    final response = await _supabase
        .from('invoices')
        .select(_invoiceQuery)
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (response as List).map((m) => Invoice.fromMap(m)).toList();
  }

  Future<void> registerPayment({
    required String invoiceId,
    required double amount,
    required String method,
    String? reference,
    String? bankName,
  }) async {
    // RPC transaccional: registra el pago, recalcula el estado del recibo y
    // sincroniza is_paid en los paquetes, todo en una sola transacción con
    // bloqueo de fila (evita estados inconsistentes con pagos concurrentes).
    await _supabase.rpc('register_payment', params: {
      'p_invoice_id': invoiceId,
      'p_amount': amount,
      'p_method': method,
      'p_reference': reference,
      'p_bank_name': bankName,
    });
  }

  Future<void> cancelInvoice(String invoiceId) async {
    await _supabase
        .from('invoices')
        .update({'status': 'anulada'})
        .eq('id', invoiceId);
  }

  Future<bool> hasInvoiceForPackage(String packageId) async {
    final result = await _supabase
        .from('invoice_items')
        .select('id')
        .eq('package_id', packageId)
        .maybeSingle();
    return result != null;
  }

  Future<Invoice?> getInvoiceForPackage(String packageId) async {
    final item = await _supabase
        .from('invoice_items')
        .select('invoice_id')
        .eq('package_id', packageId)
        .maybeSingle();
    if (item == null) return null;
    return getInvoiceById(item['invoice_id'] as String);
  }

  // ── Repartidores ────────────────────────────────────────────────────────────

  static const String _deliveryQuery = '''
    *,
    client:client_id(name, last_name, phone),
    deliverer:deliverer_id(name, last_name)
  ''';

  Future<void> promoteToRepartidor(String userId, {String? phone}) async {
    await _supabase.rpc('promote_to_repartidor', params: {
      'target_user_id': userId,
      if (phone != null && phone.isNotEmpty) 'user_phone': phone,
    });
  }

  Future<app_models.User?> getUserById(String id) async {
    final res =
        await _supabase.from('users').select().eq('id', id).maybeSingle();
    if (res == null) return null;
    return app_models.User.fromMap(res);
  }

  Future<List<app_models.User>> getClientesParaPromover() async {
    final response = await _supabase
        .from('users')
        .select()
        .eq('is_admin', false)
        .order('name', ascending: true);
    return (response as List)
        .map((m) => app_models.User.fromMap(m))
        .where((u) => u.role != 'repartidor' && u.role != 'almacen')
        .toList();
  }

  Future<List<app_models.User>> getAllRepartidores() async {
    final response = await _supabase
        .from('users')
        .select()
        .eq('role', 'repartidor')
        .order('name', ascending: true);
    return (response as List)
        .map((m) => app_models.User.fromMap(m))
        .toList();
  }

  Future<void> setAvailability(String userId, bool isAvailable) async {
    await _supabase
        .from('users')
        .update({'is_available': isAvailable})
        .eq('id', userId);
  }

  Future<bool> getMyAvailability(String userId) async {
    final response = await _supabase
        .from('users')
        .select('is_available')
        .eq('id', userId)
        .single();
    return response['is_available'] ?? false;
  }

  Future<List<String>> getAvailableRepartidorIds() async {
    final response = await _supabase
        .from('users')
        .select('id')
        .eq('role', 'repartidor')
        .eq('is_available', true);
    return (response as List).map((m) => m['id'] as String).toList();
  }

  // ── Deliveries ──────────────────────────────────────────────────────────────

  Future<void> createDelivery({
    required String invoiceId,
    required String packageId,
    required String clientId,
    required String deliveryAddress,
  }) async {
    await _supabase.from('deliveries').insert({
      'invoice_id': invoiceId,
      'package_id': packageId,
      'client_id': clientId,
      'delivery_address': deliveryAddress,
      'status': 'disponible',
    });
  }

  Future<List<Delivery>> getAvailableDeliveries() async {
    final response = await _supabase
        .from('deliveries')
        .select(_deliveryQuery)
        .eq('status', 'disponible')
        .order('created_at', ascending: false);
    return (response as List).map((m) => Delivery.fromMap(m)).toList();
  }

  Future<List<Delivery>> getMyDeliveries(String delivererId) async {
    final response = await _supabase
        .from('deliveries')
        .select(_deliveryQuery)
        .eq('deliverer_id', delivererId)
        .inFilter('status', ['aceptado', 'en_camino'])
        .order('accepted_at', ascending: false);
    return (response as List).map((m) => Delivery.fromMap(m)).toList();
  }

  Future<List<Delivery>> getMyDeliveryHistory(String delivererId) async {
    final response = await _supabase
        .from('deliveries')
        .select(_deliveryQuery)
        .eq('deliverer_id', delivererId)
        .inFilter('status', ['entregado', 'cancelado'])
        .order('delivered_at', ascending: false);
    return (response as List).map((m) => Delivery.fromMap(m)).toList();
  }

  Future<bool> acceptDelivery(String deliveryId, String delivererId) async {
    final result = await _supabase.rpc('accept_delivery', params: {
      'p_delivery_id': deliveryId,
      'p_deliverer_id': delivererId,
    });
    return result as bool;
  }

  Future<void> updateDeliveryStatus(String deliveryId, String status) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final update = <String, dynamic>{'status': status};
    if (status == 'en_camino') update['on_the_way_at'] = now;
    if (status == 'entregado') update['delivered_at'] = now;
    await _supabase
        .from('deliveries')
        .update(update)
        .eq('id', deliveryId);
  }

  /// Saldo pendiente del recibo asociado a una entrega. Vía RPC security
  /// definer para que el repartidor pueda consultarlo sin permisos RLS sobre
  /// invoices/payments. Sirve para decidir si debe cobrar al entregar.
  Future<double> deliveryBalance(String deliveryId) async {
    final res = await _supabase.rpc('delivery_balance', params: {
      'p_delivery_id': deliveryId,
    });
    return (res as num).toDouble();
  }

  /// Cierra una entrega: marca la entrega como entregada, registra el pago por
  /// el saldo del recibo con el método indicado (si hay saldo), lo marca pagado
  /// y sincroniza is_paid en los paquetes. Atómico y vía RPC security definer
  /// para que el repartidor pueda hacerlo sin permisos RLS amplios.
  Future<void> completeDelivery(String deliveryId, String method) async {
    await _supabase.rpc('complete_delivery', params: {
      'p_delivery_id': deliveryId,
      'p_method': method,
    });
  }

  /// Sube la foto de evidencia de entrega a Storage y la liga a la entrega.
  Future<void> uploadDeliveryProof(String deliveryId, Uint8List bytes) async {
    final path = '$deliveryId.jpg';
    await _supabase.storage.from('delivery-proofs').uploadBinary(
          path,
          bytes,
          fileOptions:
              const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    final url = _supabase.storage.from('delivery-proofs').getPublicUrl(path);
    await _supabase
        .from('deliveries')
        .update({'proof_url': url}).eq('id', deliveryId);
  }

  /// El repartidor reporta su ubicación actual para el pedido. Vía RPC security
  /// definer (solo afecta su propia entrega activa).
  Future<void> updateDelivererLocation(
      String deliveryId, double lat, double lng) async {
    await _supabase.rpc('update_deliverer_location', params: {
      'p_delivery_id': deliveryId,
      'p_lat': lat,
      'p_lng': lng,
    });
  }

  Future<List<Delivery>> getAllDeliveries() async {
    final response = await _supabase
        .from('deliveries')
        .select(_deliveryQuery)
        .order('created_at', ascending: false);
    return (response as List).map((m) => Delivery.fromMap(m)).toList();
  }

  Future<Map<String, int>> getDelivererStats(String delivererId) async {
    final all = await _supabase
        .from('deliveries')
        .select('status')
        .eq('deliverer_id', delivererId);
    final list = all as List;
    return {
      'entregados': list.where((d) => d['status'] == 'entregado').length,
      'activos': list
          .where((d) => ['aceptado', 'en_camino'].contains(d['status']))
          .length,
    };
  }

  Future<List<Delivery>> getDeliveriesByClient(String clientId) async {
    final response = await _supabase
        .from('deliveries')
        .select(_deliveryQuery)
        .eq('client_id', clientId)
        .order('created_at', ascending: false);
    return (response as List).map((m) => Delivery.fromMap(m)).toList();
  }

  Future<void> requestDelivery({
    required String invoiceId,
    required String packageId,
    required String deliveryAddress,
    String? phone,
  }) async {
    // 1) Guardar dirección y teléfono en el perfil ANTES de crear el pedido,
    //    para que el trigger que denormaliza el contacto en la entrega capture
    //    los datos frescos (y para reutilizarlos / reflejarlos en el perfil).
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      final update = <String, dynamic>{};
      if (deliveryAddress.trim().isNotEmpty) {
        update['address'] = deliveryAddress.trim();
      }
      if (phone != null && phone.trim().isNotEmpty) {
        update['phone'] = phone.trim();
      }
      if (update.isNotEmpty) {
        try {
          await _supabase.from('users').update(update).eq('id', userId);
        } catch (e) {
          debugPrint('No se pudo guardar contacto en el perfil: $e');
        }
      }
    }

    // 2) Crear el pedido (el RPC inserta la entrega; un trigger en la BD copia
    //    nombre/teléfono del cliente y tracking del paquete a la fila).
    await _supabase.rpc('request_delivery', params: {
      'p_invoice_id': invoiceId,
      'p_package_id': packageId,
      'p_delivery_address': deliveryAddress,
    });

    // 3) Notificar a los repartidores disponibles. La resolución de quiénes están
    // en línea se hace en la Edge Function (service_role), porque desde el
    // cliente las políticas RLS de `users` impiden ver otras filas y la lista
    // saldría vacía.
    await _notifyRepartidores();
  }

  /// Solicita delivery de VARIOS paquetes en un solo viaje (una sola tarifa).
  /// Crea un único delivery que agrupa los paquetes seleccionados.
  Future<void> requestDeliveryMulti({
    required List<String> packageIds,
    required String deliveryAddress,
    String? phone,
  }) async {
    if (packageIds.isEmpty) return;
    await _saveContactToProfile(deliveryAddress, phone);

    await _supabase.rpc('request_delivery_multi', params: {
      'p_package_ids': packageIds,
      'p_delivery_address': deliveryAddress,
    });

    await _notifyRepartidores();
  }

  /// Guarda dirección/teléfono en el perfil antes de crear el pedido.
  Future<void> _saveContactToProfile(String address, String? phone) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final update = <String, dynamic>{};
    if (address.trim().isNotEmpty) update['address'] = address.trim();
    if (phone != null && phone.trim().isNotEmpty) {
      update['phone'] = phone.trim();
    }
    if (update.isEmpty) return;
    try {
      await _supabase.from('users').update(update).eq('id', userId);
    } catch (e) {
      debugPrint('No se pudo guardar contacto en el perfil: $e');
    }
  }

  Future<void> _notifyRepartidores() async {
    await sendNotification(
      title: '📦 Nuevo pedido de delivery',
      body: 'Hay un nuevo pedido disponible. ¡Sé el primero en aceptarlo!',
      role: 'repartidor',
    );
  }

  /// Dirección y teléfono guardados en el perfil del usuario actual (para
  /// precargarlos al solicitar delivery). Claves: 'address', 'phone'.
  Future<Map<String, String?>> getCurrentUserContact() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return {'address': null, 'phone': null};
    final res = await _supabase
        .from('users')
        .select('address, phone')
        .eq('id', userId)
        .maybeSingle();
    String? clean(dynamic v) {
      final s = v as String?;
      return (s != null && s.trim().isNotEmpty) ? s.trim() : null;
    }

    return {
      'address': clean(res?['address']),
      'phone': clean(res?['phone']),
    };
  }

  Future<void> declineDelivery(String invoiceId) async {
    await _supabase.rpc('decline_delivery', params: {
      'p_invoice_id': invoiceId,
    });
  }

  /// Recibos del usuario actual cuya decisión de delivery sigue pendiente
  /// y que aún no están pagados (para mostrar el popup).
  Future<List<Invoice>> getPendingDeliveryInvoices() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final response = await _supabase
        .from('invoices')
        .select(_invoiceQuery)
        .eq('user_id', userId)
        .eq('delivery_choice', 'pendiente')
        .neq('status', 'pagada')
        .order('created_at', ascending: false);
    return (response as List).map((m) => Invoice.fromMap(m)).toList();
  }

  /// Recibos del usuario que TODAVÍA se pueden enviar por delivery: listos y
  /// no pagados, con delivery aún no solicitado (pendiente o rechazado).
  /// Sirve para la selección multi-paquete, incluyendo los que dijo "recoger
  /// en local" pero cambió de opinión.
  Future<List<Invoice>> getDeliverableInvoices() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final response = await _supabase
        .from('invoices')
        .select(_invoiceQuery)
        .eq('user_id', userId)
        .inFilter('delivery_choice', ['pendiente', 'rechazado'])
        .neq('status', 'pagada')
        .order('created_at', ascending: false);
    return (response as List).map((m) => Invoice.fromMap(m)).toList();
  }

  Future<Delivery?> getDeliveryForPackage(String packageId) async {
    // 1) Multi-paquete: el paquete puede estar agrupado en un delivery cuyo
    //    package_id es otro (el primario). Lo buscamos vía delivery_packages.
    final link = await _supabase
        .from('delivery_packages')
        .select('delivery_id')
        .eq('package_id', packageId)
        .maybeSingle();
    if (link != null) {
      final res = await _supabase
          .from('deliveries')
          .select(_deliveryQuery)
          .eq('id', link['delivery_id'])
          .maybeSingle();
      if (res != null) return Delivery.fromMap(res);
    }
    // 2) Delivery de un solo paquete (camino clásico).
    final response = await _supabase
        .from('deliveries')
        .select(_deliveryQuery)
        .eq('package_id', packageId)
        .maybeSingle();
    if (response == null) return null;
    return Delivery.fromMap(response);
  }

  // ── Notificaciones ──────────────────────────────────────────────────────────

  Future<void> sendNotification({
    required String title,
    required String body,
    List<String>? userIds,
    String? role,
  }) async {
    try {
      final res = await _supabase.functions.invoke('send-push-notification',
          body: {
            'title': title,
            'body': body,
            if (userIds != null) 'user_ids': userIds,
            if (role != null) 'role': role,
          });
      debugPrint(
          'sendNotification status=${res.status} data=${res.data}');
    } catch (e) {
      debugPrint('Error enviando notificación: $e');
    }
  }
}
