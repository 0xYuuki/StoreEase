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
    expect(find.text('Cart'), findsOneWidget);
    expect(find.text('Debts'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Initial view is Cart
    expect(find.text("Helen's Store"), findsOneWidget);
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
    expect(find.text('Sales Trend (Days)'), findsOneWidget);
    expect(find.text('Days'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Months'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);

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

    // Switch back to Cart tab
    await tester.tap(find.text('Cart'));
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

    // Search by receipt ID '1' -> only Sale #1 appears
    final salesSearch = find.widgetWithText(TextField, 'Search by receipt # or customer name...');
    await tester.enterText(salesSearch, '1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sale #1'), findsOneWidget);

    // Searching item names no longer matches (items removed from receipt search)
    await tester.enterText(salesSearch, 'Egg');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sale #1'), findsNothing);

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

  testWidgets('AnalyticsScreen allows switching Sales Trend period between Days, Week, Months, and Year', (WidgetTester tester) async {
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
          ChangeNotifierProvider(create: (_) => ProductProvider(api: api)),
          ChangeNotifierProvider(create: (_) => CartProvider(api: api)),
          ChangeNotifierProvider(create: (_) => DebtProvider(api: api)),
          ChangeNotifierProvider(create: (_) => SalesProvider(api: api)),
          ChangeNotifierProvider(create: (_) => AnalyticsProvider(api: api)..loadAnalytics()),
        ],
        child: const HelensStoreApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Navigate to Analytics
    await tester.tap(find.text('Analytics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Default period is Days
    expect(find.text('Sales Trend (Days)'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Daily Average: ₱0.00'), findsOneWidget);

    // Tap Week
    await tester.tap(find.text('Week'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sales Trend (Week)'), findsOneWidget);
    expect(find.text('This Wk'), findsOneWidget);
    expect(find.text('Weekly Average: ₱0.00'), findsOneWidget);

    // Tap Months
    await tester.tap(find.text('Months'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sales Trend (Months)'), findsOneWidget);
    expect(find.text('This Mo'), findsOneWidget);
    expect(find.text('Monthly Average: ₱0.00'), findsOneWidget);

    // Tap Year
    await tester.tap(find.text('Year'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sales Trend (Year)'), findsOneWidget);
    expect(find.text('This Yr'), findsOneWidget);
    expect(find.text('Annual Average: ₱0.00'), findsOneWidget);

    // Switch back to Days
    await tester.tap(find.text('Days'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sales Trend (Days)'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    await db.close();
  });

  testWidgets('InventoryScreen displays category sections and filters by category chips', (WidgetTester tester) async {
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
          ChangeNotifierProvider(create: (_) => SalesProvider(api: api)),
          ChangeNotifierProvider(create: (_) => AnalyticsProvider(api: api)),
        ],
        child: const HelensStoreApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Navigate to Inventory tab
    await tester.tap(find.text('Inventory'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify category section headers are displayed
    expect(find.text('BEVERAGES'), findsOneWidget);
    expect(find.text('CANNED GOODS'), findsOneWidget);
    expect(find.text('All (7)'), findsOneWidget);

    // Tap Beverages category filter chip
    await tester.tap(find.text('Beverages (2)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Only Beverages section is shown
    expect(find.text('BEVERAGES'), findsOneWidget);
    expect(find.text('CANNED GOODS'), findsNothing);
    expect(find.text('Nature Spring Bottled Water 500ml'), findsOneWidget);
    expect(find.text('Mega Sardines in Tomato Sauce 155g'), findsNothing);

    // Tap All chip to restore all sections
    await tester.tap(find.text('All (7)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('BEVERAGES'), findsOneWidget);
    expect(find.text('CANNED GOODS'), findsOneWidget);

    await db.close();
  });

  testWidgets('POS searches loose and weighted items cleanly without filter chips', (WidgetTester tester) async {
    final db = DatabaseService();
    await db.init(customPath: inMemoryDatabasePath);
    final storage = StorageService();
    final api = ApiService(database: db, storage: storage);

    // Add a loose item and a weighted item
    await db.createProduct(
      name: 'Fresh Egg',
      priceCentavos: 800,
      initialStock: 20,
      isBarcodeless: true,
    );
    await db.createProduct(
      name: 'Sinandomeng Rice',
      priceCentavos: 5200,
      initialStock: 50.0,
      pricingType: 'weight',
      unit: 'kg',
      isBarcodeless: true,
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
          ChangeNotifierProvider(create: (_) => SalesProvider(api: api)),
          ChangeNotifierProvider(create: (_) => AnalyticsProvider(api: api)),
        ],
        child: const HelensStoreApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify filter chips are removed from POS screen
    expect(find.text('All Items'), findsNothing);
    expect(find.text('Loose Items (No Barcode)'), findsNothing);
    expect(find.text('By Weight (Timbang)'), findsNothing);

    // Search for loose item 'Fresh'
    final searchInput = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search product or barcode...',
    );
    await tester.enterText(searchInput, 'Fresh');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Fresh Egg'), findsOneWidget);

    // Search for weighted item 'Sinandomeng'
    await tester.enterText(searchInput, 'Sinandomeng');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Sinandomeng Rice'), findsOneWidget);

    await db.close();
  });

  testWidgets('InventoryScreen allows deleting a product with confirmation dialog', (WidgetTester tester) async {
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
          ChangeNotifierProvider(create: (_) => SalesProvider(api: api)),
          ChangeNotifierProvider(create: (_) => AnalyticsProvider(api: api)),
        ],
        child: const HelensStoreApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Navigate to Inventory tab
    await tester.tap(find.text('Inventory'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Nature Spring Bottled Water 500ml is at the top of the inventory
    expect(find.text('Nature Spring Bottled Water 500ml'), findsOneWidget);

    // Find and tap delete icon
    final deleteButtons = find.byTooltip('Delete Product');
    expect(deleteButtons, findsWidgets);

    // Tap first delete button (Nature Spring Bottled Water 500ml)
    await tester.tap(deleteButtons.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Confirmation dialog appears
    expect(find.text('Delete Product'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Tap Delete in dialog
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Confirmation snackbar appears and item is removed
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Nature Spring Bottled Water 500ml'), findsNothing);

    await db.close();
  });

  testWidgets('Add Product dialog supports custom category popup and full-width stock alert fields without overflow', (WidgetTester tester) async {
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
          ChangeNotifierProvider(create: (_) => SalesProvider(api: api)),
          ChangeNotifierProvider(create: (_) => AnalyticsProvider(api: api)),
        ],
        child: const HelensStoreApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Navigate to Inventory tab
    await tester.tap(find.text('Inventory'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Tap Add Product FAB
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify Add New Product dialog is opened
    expect(find.text('Add New Product'), findsOneWidget);

    // Verify full-width stock and reorder alert field labels exist
    expect(find.text('Initial Stock (in pieces)'), findsOneWidget);
    expect(find.text('Low Stock Alert Level (in pieces)'), findsOneWidget);

    // Open category dropdown
    await tester.tap(find.text('General'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Select + Custom Category...
    await tester.tap(find.text('+ Custom Category...').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify New Category popup dialog opened
    expect(find.text('New Category'), findsOneWidget);
    final catField = find.widgetWithText(TextField, 'Category Name');
    expect(catField, findsOneWidget);

    // Enter custom category name
    await tester.enterText(catField, 'Bakery');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Category'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Enter product details
    final nameField = find.widgetWithText(TextField, 'Product Name');
    await tester.enterText(nameField, 'Pan de Sal 10s');
    await tester.pump();

    final priceField = find.widgetWithText(TextField, 'Price per piece (₱)');
    await tester.enterText(priceField, '25.00');
    await tester.pump();

    final stockField = find.widgetWithText(TextField, 'Initial Stock (in pieces)');
    await tester.enterText(stockField, '50');
    await tester.pump();

    final reorderField = find.widgetWithText(TextField, 'Low Stock Alert Level (in pieces)');
    await tester.enterText(reorderField, '10');
    await tester.pump();

    // Tap Save Product
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Product'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify product added and visible
    expect(find.text('Pan de Sal 10s'), findsOneWidget);

    await db.close();
  });

  testWidgets('Category field dropdown renders long categories without RenderFlex overflow on narrow screens', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

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
          ChangeNotifierProvider(create: (_) => SalesProvider(api: api)),
          ChangeNotifierProvider(create: (_) => AnalyticsProvider(api: api)),
        ],
        child: const HelensStoreApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Navigate to Inventory tab
    await tester.tap(find.text('Inventory'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Tap Add Product FAB
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Open Category dropdown
    await tester.tap(find.text('General'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Select the longest category name: Household & Personal Care
    await tester.tap(find.text('Household & Personal Care').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify Household & Personal Care is selected without any overflow
    expect(find.text('Household & Personal Care'), findsWidgets);

    // Cancel dialog
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await db.close();
  });
}
