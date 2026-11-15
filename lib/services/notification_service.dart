import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _showLocalNotification(message);
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(InitializationSettings(android: androidSettings));

  final title = message.notification?.title
      ?? message.data['title']
      ?? 'Semtracar';
  final body = message.notification?.body
      ?? message.data['body']
      ?? '';

  await plugin.show(
    message.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        // El id se mantiene: la Edge Function `send-push-notification` lo
        // envía hardcodeado en `android.notification.channel_id`.
        'nica_cargo_channel',
        'Semtracar Notificaciones',
        channelDescription: 'Notificaciones de estado de paquetes',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final SupabaseClient _supabase = Supabase.instance.client;
  static StreamSubscription<RemoteMessage>? _messageSubscription;
  static Future<void>? _initFuture;

  /// Idempotente: llamadas concurrentes/repetidas esperan la misma init.
  /// Evita el error "A request for permissions is already running".
  static Future<void> initialize() => _initFuture ??= _doInitialize();

  static Future<void> _doInitialize() async {
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('Error pidiendo permisos de notificación: $e');
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      InitializationSettings(android: androidSettings),
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      // Ver nota del id en `_showLocalNotification`.
      'nica_cargo_channel',
      'Semtracar Notificaciones',
      description: 'Notificaciones de estado de paquetes',
      importance: Importance.high,
    );

    final dynamic androidPlugin =
        _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
    }

    await _messageSubscription?.cancel();
    _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
      _showLocalNotification(message);
    });

    await _saveToken();

    _messaging.onTokenRefresh.listen((newToken) async {
      await _updateToken(newToken);
    });
  }

  /// Reasigna el token al usuario actual (llamar tras login para asegurar
  /// que el token del dispositivo quede ligado a la cuenta que inició sesión).
  static Future<void> refreshTokenForCurrentUser() async {
    await _saveToken();
  }

  static Future<void> _saveToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('user_push_tokens').upsert({
        'user_id': userId,
        'token': token,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');

      debugPrint('FCM Token guardado: $token');
    } catch (e) {
      debugPrint('Error guardando token FCM: $e');
    }
  }

  static Future<void> _updateToken(String token) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('user_push_tokens').upsert({
        'user_id': userId,
        'token': token,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('Error actualizando token FCM: $e');
    }
  }
}
