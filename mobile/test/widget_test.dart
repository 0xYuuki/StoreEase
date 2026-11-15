import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helen_store_mobile/main.dart';
import 'package:helen_store_mobile/models/models.dart';
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
    expect(find.text('All Time'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('This Week'), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);

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

  testWidgets('POS search uses first-letter prefix matching and displays vertical up/down preview list', (WidgetTester tester) async {
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

    // Type 'e' in search bar
    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'e');
    await tester.pump();

    // Verify prefix match: 'Egg' matches because it starts with 'e'
    expect(find.text('Egg'), findsOneWidget);
    // 'Lucky Me! Pancit Canton' and 'Mega Sardines' should NOT match even though they contain 'e' inside
    expect(find.text('Lucky Me! Pancit Canton (Original)'), findsNothing);
    expect(find.text('Mega Sardines in Tomato Sauce 155g'), findsNothing);

    // Tap 'Egg' to add it to cart from vertical search preview
    await tester.tap(find.text('Egg'));
    await tester.pump();

    // Cart now has 1 item (Egg) and total is ₱11.00
    expect(find.text('TOTAL (1 items)'), findsOneWidget);
    expect(find.text('₱11.00'), findsWidgets);

    // Type query with no matches
    await tester.enterText(searchField, 'xyz');
    await tester.pump();
    expect(find.text('No products starting with "xyz"'), findsOneWidget);

    await db.close();
  });

  testWidgets('SalesScreen filters receipts by search input and date filter chips', (WidgetTester tester) async {
    final db = DatabaseService();
    await db.init(customPath: inMemoryDatabasePath);

    final storage = StorageService();
    final api = ApiService(database: db, storage: storage);

    // Create a starter sale
    final egg = (await db.lookupBarcode('1'))!;
    await db.checkout(
      items: [CartItem(product: egg, quantity: 2)],
      tenderedAmount: 5000,
    );

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

    // Navigate to Sales tab
    await tester.tap(find.text('Sales'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Sale #1'), findsOneWidget);
    expect(find.text('1 sale • Total: ₱22.00'), findsOneWidget);

    // Type query matching sale
    final salesSearch = find.widgetWithText(TextField, 'Search receipt #, item, or customer...');
    await tester.enterText(salesSearch, 'Egg');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sale #1'), findsOneWidget);

    // Type query not matching
    await tester.enterText(salesSearch, 'NonExistentItem');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sale #1'), findsNothing);
    expect(find.text('No sales found matching your filters'), findsOneWidget);

    // Tap Reset All Filters
    await tester.tap(find.text('Reset All Filters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sale #1'), findsOneWidget);

    // Tap 'Today' chip
    await tester.tap(find.text('Today'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sale #1'), findsOneWidget);

    await db.close();
  });
}
