# Semtracar

Aplicación móvil en **Flutter** para una empresa de envíos y casillero internacional. Permite a los clientes rastrear sus paquetes, cotizar envíos y solicitar entregas a domicilio, mientras que administradores y repartidores gestionan todo el flujo operativo desde la misma app.

## Funcionalidades

**Clientes**
- Registro, inicio de sesión y recuperación de contraseña (con deep links).
- Rastreo de paquetes con línea de tiempo de estados.
- Calculadora de envío (aéreo / marítimo, por peso y categoría).
- Historial de paquetes y facturas.
- Solicitud de delivery de uno o varios paquetes en un solo viaje.

**Administradores**
- Dashboard con resumen de operaciones.
- Gestión de paquetes, pedidos y facturación.
- Escaneo de códigos QR para registrar paquetes.

**Repartidores**
- Lista de entregas asignadas y mapa de ruta.
- Notificaciones push cuando hay nuevos pedidos disponibles.

La app cambia de interfaz automáticamente según el rol del usuario y reacciona en tiempo real si el rol cambia.

## Tecnologías

| Área | Herramientas |
| --- | --- |
| App | Flutter / Dart |
| Backend | Supabase (Auth, PostgreSQL, RLS, RPC, Realtime) |
| Funciones serverless | Supabase Edge Functions (Deno / TypeScript) |
| Notificaciones | Firebase Cloud Messaging + flutter_local_notifications |
| Mapas y ubicación | flutter_map, latlong2, geolocator |
| Otros | mobile_scanner, qr_flutter, image_picker, app_links |

## Estructura

```
lib/
├── models/      # Modelos de datos (usuario, paquete, factura, entrega)
├── screens/     # Pantallas por rol (cliente, admin, repartidor)
├── services/    # Acceso a Supabase y notificaciones
├── utils/       # Lógica de negocio (calculadora de envíos)
└── widgets/     # Componentes reutilizables
supabase/
└── functions/   # Edge Function para enviar notificaciones push
```

## Cómo ejecutarlo

1. Instala [Flutter](https://docs.flutter.dev/get-started/install) (SDK ^3.7.2).
2. Copia `assets/.env.example` a `assets/.env` y completa los datos de tu proyecto de Supabase.
3. Agrega tu propio `android/app/google-services.json` de Firebase.
4. Ejecuta:

```bash
flutter pub get
flutter run
```

> Las credenciales (Supabase, Firebase) no se incluyen en el repositorio.
