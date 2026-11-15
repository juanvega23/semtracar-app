import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testapp/screens/admin_home_screen.dart';
import 'package:testapp/screens/home_screen.dart';
import 'package:testapp/screens/repartidor_home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/PageView.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:app_links/app_links.dart';
import 'screens/reset_password_screen.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await dotenv.load(fileName: "assets/.env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLinks _appLinks;
  StreamSubscription? _linkSubscription;
  StreamSubscription? _authSubscription;
  bool _navigatedToReset = false;
  RealtimeChannel? _roleChannel;
  String? _currentEffectiveRole;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _initAuthListener();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _authSubscription?.cancel();
    _roleChannel?.unsubscribe();
    super.dispose();
  }

  void _initAuthListener() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.passwordRecovery && session != null) {
        // Supabase procesó el token de recovery automáticamente
        _goToResetPassword();
      } else if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession) {
        if (session != null) _setupRoleWatch();
      } else if (event == AuthChangeEvent.signedOut) {
        _roleChannel?.unsubscribe();
        _roleChannel = null;
        _currentEffectiveRole = null;
      }
    });
  }

  String _effectiveRole(Map<String, dynamic> row) {
    final role = (row['role'] as String?) ?? '';
    if (role == 'repartidor') return 'repartidor';
    if (role == 'almacen') return 'almacen';
    if (role == 'admin' || row['is_admin'] == true) return 'admin';
    return 'cliente';
  }

  /// Escucha en tiempo real la fila del usuario actual. Si su rol cambia
  /// (p. ej. el admin lo promueve/degrada), lo lleva a la pantalla correcta
  /// sin que tenga que cerrar sesión.
  Future<void> _setupRoleWatch() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final row = await supabase
          .from('users')
          .select('role, is_admin')
          .eq('id', user.id)
          .single();
      _currentEffectiveRole = _effectiveRole(row);
    } catch (_) {
      // sin baseline, igual seguimos escuchando
    }

    _roleChannel?.unsubscribe();
    _roleChannel = supabase
        .channel('role-watch-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: user.id,
          ),
          callback: (payload) {
            final newRole = _effectiveRole(payload.newRecord);
            if (_currentEffectiveRole != null &&
                newRole != _currentEffectiveRole) {
              _currentEffectiveRole = newRole;
              _routeToRole(newRole, user.id);
            }
          },
        )
        .subscribe();
  }

  void _routeToRole(String role, String userId) {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    final Widget screen = role == 'repartidor'
        ? const RepartidorHomeScreen()
        : (role == 'admin' || role == 'almacen')
            ? AdminHomeScreen()
            : HomeScreen(userId: userId);
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
    final ctx = _navigatorKey.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(role == 'cliente'
            ? 'Tu rol cambió a Cliente.'
            : role == 'repartidor'
                ? 'Ahora eres Repartidor.'
                : role == 'almacen'
                    ? 'Ahora eres Encargado de almacén.'
                    : 'Ahora eres Administrador.'),
        backgroundColor: const Color(0xFF12327F),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Navega a la pantalla de restablecer contraseña de forma robusta:
  /// reintenta si el navigator aún no está montado (arranque en frío) y evita
  /// navegar dos veces (evento + deep link).
  void _goToResetPassword() {
    if (_navigatedToReset) return;
    final nav = _navigatorKey.currentState;
    if (nav == null) {
      Future.delayed(const Duration(milliseconds: 300), _goToResetPassword);
      return;
    }
    _navigatedToReset = true;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
      (route) => false,
    );
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Maneja el deep link si la app estaba cerrada
    final initialLink = await _appLinks.getInitialLink();
    if (initialLink != null) {
      _handleDeepLink(initialLink);
    }

    // Maneja deep links mientras la app está abierta
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  void _handleDeepLink(Uri uri) async {
    if (uri.host == 'login-callback') {
      // Espera un momento para que Supabase procese la sesión
      await Future.delayed(const Duration(milliseconds: 500));

      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user != null) {
        final userData =
            await supabase
                .from('users')
                .select('is_admin, role')
                .eq('id', user.id)
                .single();

        final screen = _screenForRole(userData, user.id);

        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => screen),
          (route) => false,
        );
      } else {
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LoginScreen()),
          (route) => false,
        );
        _showVerifiedMessage();
      }
    } else if (uri.host == 'reset-callback') {
      // Normalmente el listener de passwordRecovery navega solo. Pero por si
      // ese evento no dispara (variaciones del flujo), damos un respaldo:
      // esperamos a que Supabase procese la sesión de recuperación y, si quedó
      // sesión activa, navegamos a la pantalla de restablecer.
      await Future.delayed(const Duration(milliseconds: 900));
      if (Supabase.instance.client.auth.currentSession != null) {
        _goToResetPassword();
      }
    }
  }

  void _showVerifiedMessage() {
    ScaffoldMessenger.of(_navigatorKey.currentContext!).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: Colors.green,
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 10),
            Text(
              '¡Correo verificado con éxito!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: FutureBuilder(
        future: _getInitialScreen(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data ?? LoginScreen();
        },
      ),
    );
  }

  Widget _screenForRole(Map<String, dynamic> userData, String userId) {
    final role = userData['role'] as String? ?? '';
    if (role == 'repartidor') return const RepartidorHomeScreen();
    if (role == 'almacen') return AdminHomeScreen(); // panel admin en modo almacén
    if (role == 'admin' || userData['is_admin'] == true) return AdminHomeScreen();
    return HomeScreen(userId: userId);
  }

  Future<Widget> _getInitialScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final supabase = Supabase.instance.client;

    final user = supabase.auth.currentUser;
    if (user != null) {
      final userData =
          await supabase
              .from('users')
              .select('is_admin, role')
              .eq('id', user.id)
              .single();

      return _screenForRole(userData, user.id);
    }

    final hasSeenWelcome = prefs.getBool('hasSeenWelcome') ?? false;
    if (!hasSeenWelcome) {
      await prefs.setBool('hasSeenWelcome', true);
      return WelcomePageView();
    }

    return LoginScreen();
  }
}
