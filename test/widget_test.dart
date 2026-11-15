// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/main.dart';
void main() {
  testWidgets('Prueba el flujo de login', (WidgetTester tester) async {
  await tester.pumpWidget(MyApp());

  // Ingresa credenciales válidas
  await tester.enterText(find.byType(TextFormField).first, 'admin');
  await tester.enterText(find.byType(TextFormField).last, '123456');
  await tester.tap(find.text('Iniciar Sesión'));
  
  // Espera a que se complete la navegación y animaciones
  await tester.pumpAndSettle();

  // Verifica que HomeScreen se muestre con el texto exacto
  expect(find.text('¡Has iniciado sesión exitosamente!'), findsOneWidget);
});
}