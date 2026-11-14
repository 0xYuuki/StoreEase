import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helen_store_mobile/main.dart';
import 'package:helen_store_mobile/providers/cart_provider.dart';
import 'package:helen_store_mobile/providers/debt_provider.dart';
import 'package:helen_store_mobile/services/api_service.dart';
import 'package:helen_store_mobile/services/storage_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('HelensStoreApp renders shell with all 5 navigation tabs', (WidgetTester tester) async {
    final storage = StorageService();
    final api = ApiService(storage: storage);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storage),
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider(create: (_) => CartProvider(api: api)),
          ChangeNotifierProvider(create: (_) => DebtProvider(api: api)),
        ],
        child: const HelensStoreApp(),
      ),
    );

    await tester.pump();

    // Verify all 5 navigation tabs exist
    expect(find.text('POS'), findsOneWidget);
    expect(find.text('Debts'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Initial view is POS
    expect(find.text("Helen's Store POS"), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);

    // Tap Debts Tab
    await tester.tap(find.text('Debts'));
    await tester.pump();
    expect(find.text('Customer Debts'), findsOneWidget);

    // Tap Settings Tab
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.text('Settings & Connection'), findsOneWidget);
    expect(find.text('Backend Server Connection'), findsOneWidget);
  });
}
