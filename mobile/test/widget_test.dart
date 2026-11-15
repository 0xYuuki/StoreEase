import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helen_store_mobile/main.dart';
import 'package:helen_store_mobile/providers/analytics_provider.dart';
import 'package:helen_store_mobile/providers/cart_provider.dart';
import 'package:helen_store_mobile/providers/debt_provider.dart';
import 'package:helen_store_mobile/providers/product_provider.dart';
import 'package:helen_store_mobile/providers/sales_provider.dart';
import 'package:helen_store_mobile/services/api_service.dart';
import 'package:helen_store_mobile/services/database_service.dart';
import 'package:helen_store_mobile/services/storage_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('HelensStoreApp renders shell with all 5 navigation tabs and offline settings', (WidgetTester tester) async {
    final db = DatabaseService();
    await db.init(customPath: inMemoryDatabasePath);

    final storage = StorageService();
    final api = ApiService(database: db, storage: storage);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DatabaseService>.value(value: db),
          Provider<StorageService>.value(value: storage),
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider(create: (_) => ProductProvider(api: api)..loadProducts()),
          ChangeNotifierProvider(create: (_) => CartProvider(api: api)),
          ChangeNotifierProvider(create: (_) => DebtProvider(api: api)),
          ChangeNotifierProvider(create: (_) => SalesProvider(api: api)..loadSales()),
          ChangeNotifierProvider(create: (_) => AnalyticsProvider(api: api)..loadAnalytics()),
        ],
        child: const HelensStoreApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify all 6 navigation tabs exist
    expect(find.text('POS'), findsOneWidget);
    expect(find.text('Debts'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Initial view is POS
    expect(find.text("Helen's Store POS"), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);

    // Tap Debts Tab
    await tester.tap(find.text('Debts'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Customer Debts'), findsOneWidget);

    // Tap Inventory Tab
    await tester.tap(find.text('Inventory'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Inventory Management'), findsOneWidget);
    expect(find.text('Add Product'), findsOneWidget);

    // Tap Sales Tab
    await tester.tap(find.text('Sales'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sales History'), findsOneWidget);

    // Tap Analytics Tab
    await tester.tap(find.text('Analytics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sales Analytics'), findsOneWidget);
    expect(find.text('Overview & Revenue'), findsOneWidget);
    expect(find.text("Today's Sales"), findsOneWidget);
    expect(find.text('Sales Trend (Last 7 Days)'), findsOneWidget);

    // Tap Settings Tab
    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Settings & Storage'), findsOneWidget);
    expect(find.text('Offline SQLite Database'), findsOneWidget);
    expect(find.text('Test Database'), findsOneWidget);

    await db.close();
  });

  testWidgets('POS camera scanner automatically shuts down when switching tabs and stays closed on return', (WidgetTester tester) async {
    final db = DatabaseService();
    await db.init(customPath: inMemoryDatabasePath);

    final storage = StorageService();
    final api = ApiService(database: db, storage: storage);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DatabaseService>.value(value: db),
          Provider<StorageService>.value(value: storage),
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider(create: (_) => ProductProvider(api: api)..loadProducts()),
          ChangeNotifierProvider(create: (_) => CartProvider(api: api)),
          ChangeNotifierProvider(create: (_) => DebtProvider(api: api)),
          ChangeNotifierProvider(create: (_) => SalesProvider(api: api)..loadSales()),
          ChangeNotifierProvider(create: (_) => AnalyticsProvider(api: api)..loadAnalytics()),
        ],
        child: const HelensStoreApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Initially scanner is closed (outlined camera icon)
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    expect(find.text('Point camera at product barcode'), findsNothing);

    // Tap to open scanner
    await tester.tap(find.byIcon(Icons.camera_alt_outlined));
    await tester.pump();

    // Now scanner is open (filled camera icon and viewfinder hint)
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    expect(find.text('Point camera at product barcode'), findsOneWidget);

    // Switch to Inventory tab
    await tester.tap(find.text('Inventory'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // While on Inventory tab, POS scanner is unmounted and not running
    expect(find.text('Inventory Management'), findsOneWidget);
    expect(find.text('Point camera at product barcode'), findsNothing);

    // Switch back to POS tab
    await tester.tap(find.text('POS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Scanner is automatically closed (not left running)
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    expect(find.text('Point camera at product barcode'), findsNothing);

    await db.close();
  });
}
