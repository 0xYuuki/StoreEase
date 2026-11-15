import 'package:flutter_test/flutter_test.dart';
import 'package:helen_store_mobile/models/models.dart';
import 'package:helen_store_mobile/providers/analytics_provider.dart';
import 'package:helen_store_mobile/providers/product_provider.dart';
import 'package:helen_store_mobile/providers/sales_provider.dart';
import 'package:helen_store_mobile/services/api_service.dart';
import 'package:helen_store_mobile/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('DatabaseService SQLite Offline Operations', () {
    late DatabaseService dbService;

    setUp(() async {
      dbService = DatabaseService();
      await dbService.init(customPath: inMemoryDatabasePath);
    });

    tearDown(() async {
      await dbService.close();
    });

    test('Initializes tables and seeds default starter catalog', () async {
      final products = await dbService.getProducts();
      expect(products.isNotEmpty, true);
      expect(products.any((p) => p.name == 'Egg' && p.category == 'Fresh & Grocery'), true);
      expect(products.any((p) => p.name.contains('Water') && p.category == 'Beverages'), true);

      final debtors = await dbService.getDebtors();
      expect(debtors.isNotEmpty, true);
      expect(debtors.any((d) => d.name == 'Aling Nena'), true);

      final health = await dbService.checkHealth();
      expect(health['status'], 'Healthy');
      expect(health['integrity'], 'ok');
      expect(health['product_count'] >= 5, true);
      expect(health['customer_count'] >= 2, true);
    });

    test('Creates new product with optional initial stock and reorder level', () async {
      final newProduct = await dbService.createProduct(
        barcodeString: '480009999999',
        name: 'Chocnut 24s',
        priceCentavos: 4500,
        initialStock: 30,
        reorderLevel: 5,
        category: 'Snacks & Sweets',
      );

      expect(newProduct.id > 0, true);
      expect(newProduct.name, 'Chocnut 24s');
      expect(newProduct.barcodeString, '480009999999');
      expect(newProduct.priceCentavos, 4500);
      expect(newProduct.pricePesos, 45.00);
      expect(newProduct.stock, 30);
      expect(newProduct.reorderLevel, 5);
      expect(newProduct.category, 'Snacks & Sweets');

      final all = await dbService.getProducts();
      expect(all.any((p) => p.name == 'Chocnut 24s'), true);

      final history = await dbService.getStockHistory(newProduct.id);
      final entries = history['entries'] as List<StockMovement>;
      expect(entries.isNotEmpty, true);
      expect(entries.first.delta, 30);
      expect(entries.first.reason, 'Initial Stock');

      expect(
        () => dbService.createProduct(
          barcodeString: '480009999999',
          name: 'Another item',
          priceCentavos: 1000,
        ),
        throwsException,
      );
    });

    test('ProductProvider updates reactively and barcode lookup finds newly added products', () async {
      final api = ApiService(database: dbService);
      final productProv = ProductProvider(api: api);
      await productProv.loadProducts();

      final initialCount = productProv.products.length;

      final created = await productProv.createProduct(
        barcodeString: '777888999000',
        name: 'Bear Brand Powdered Milk 33g',
        priceCentavos: 1500,
        initialStock: 20,
      );

      expect(productProv.products.length, initialCount + 1);
      expect(productProv.products.any((p) => p.barcodeString == '777888999000'), true);

      final found = await productProv.lookupBarcode('777888999000');
      expect(found, isNotNull);
      expect(found!.name, 'Bear Brand Powdered Milk 33g');
      expect(found.id, created.id);
    });

    test('Barcode lookup returns matching active product', () async {
      final egg = await dbService.lookupBarcode('1');
      expect(egg, isNotNull);
      expect(egg!.name, 'Egg');
      expect(egg.priceCentavos, 1100);

      final hotdog = await dbService.lookupBarcode('333333333331');
      expect(hotdog, isNotNull);
      expect(hotdog!.name, 'Hotdog');

      final unknown = await dbService.lookupBarcode('999999999999');
      expect(unknown, isNull);
    });

    test('Adjusts product stock and records stock movement audit trail', () async {
      final egg = (await dbService.lookupBarcode('1'))!;
      final initialStock = egg.stock ?? 0;

      // Add 10 stock
      final updated = await dbService.adjustStock(egg.id, 10, 'Delivery');
      expect(updated.stock, initialStock + 10);

      // Verify stock movement entry
      final history = await dbService.getStockHistory(egg.id);
      final entries = history['entries'] as List<StockMovement>;
      expect(entries.isNotEmpty, true);
      expect(entries.first.delta, 10);
      expect(entries.first.reason, 'Delivery');
      expect(entries.first.resultingStock, initialStock + 10);

      // Reject negative stock resulting
      expect(
        () => dbService.adjustStock(egg.id, -(initialStock + 100), 'Large deduction'),
        throwsException,
      );
    });

    test('Completes atomic cash checkout and decrements stock', () async {
      final egg = (await dbService.lookupBarcode('1'))!;
      final initialStock = egg.stock!;

      final receipt = await dbService.checkout(
        items: [CartItem(product: egg, quantity: 2)],
        tenderedAmount: 5000, // 50.00 pesos (Total is 2200 = 22.00 pesos)
      );

      expect(receipt.saleId > 0, true);
      expect(receipt.totalAmount, 2200);
      expect(receipt.paymentMethod, 'cash');
      expect(receipt.tenderedAmount, 5000);
      expect(receipt.changeAmount, 2800); // 5000 - 2200 = 2800
      expect(receipt.items.length, 1);
      expect(receipt.items.first.quantity, 2);

      // Stock should have decreased by 2
      final refreshedEgg = (await dbService.lookupBarcode('1'))!;
      expect(refreshedEgg.stock, initialStock - 2);
    });

    test('Completes shortage debt checkout and charges customer', () async {
      final egg = (await dbService.lookupBarcode('1'))!;
      final debtors = await dbService.getDebtors();
      final alingNena = debtors.firstWhere((d) => d.name == 'Aling Nena');
      final initialBalance = alingNena.currentBalance;

      // Bill is 2 * 1100 = 2200 centavos (22 pesos)
      // Cash tendered is 1000 centavos (10 pesos) -> Shortage: 1200 centavos (12 pesos)
      final receipt = await dbService.checkout(
        items: [CartItem(product: egg, quantity: 2)],
        tenderedAmount: 1000,
        debtorId: alingNena.id,
      );

      expect(receipt.paymentMethod, 'debt');
      expect(receipt.debtorName, 'Aling Nena');
      expect(receipt.debtCharged, 1200);
      expect(receipt.debtBalance, initialBalance + 1200);

      // Customer balance in database must be updated
      final updatedDebtors = await dbService.getDebtors();
      final updatedNena = updatedDebtors.firstWhere((d) => d.id == alingNena.id);
      expect(updatedNena.currentBalance, initialBalance + 1200);

      // Customer transactions ledger must include debt entry
      final txs = await dbService.getCustomerTransactions(alingNena.id);
      expect(txs.any((t) => t.type == 'debt' && t.amount == 1200), true);
    });

    test('Creates new customer on the fly during debt checkout', () async {
      final egg = (await dbService.lookupBarcode('1'))!;

      final receipt = await dbService.checkout(
        items: [CartItem(product: egg, quantity: 1)],
        tenderedAmount: 0, // Fully charged to debt
        newDebtorName: 'Mang Kanor',
      );

      expect(receipt.paymentMethod, 'debt');
      expect(receipt.debtorName, 'Mang Kanor');
      expect(receipt.debtCharged, 1100);
      expect(receipt.debtBalance, 1100);

      // Mang Kanor exists in debtors list
      final debtors = await dbService.getDebtors();
      final kanor = debtors.firstWhere((d) => d.name == 'Mang Kanor');
      expect(kanor.currentBalance, 1100);
      expect(kanor.activeDebt, true);
    });

    test('Creates customer directly with initial borrowed debt and logs transaction', () async {
      final debtor = await dbService.createDebtor(
        'Mang Juan',
        initialDebtCentavos: 15000,
        phone: '09123456780',
        notes: 'Borrowed for groceries',
      );

      expect(debtor.id > 0, true);
      expect(debtor.name, 'Mang Juan');
      expect(debtor.currentBalance, 15000);
      expect(debtor.balancePesos, 150.0);
      expect(debtor.activeDebt, true);

      final debtors = await dbService.getDebtors();
      final juan = debtors.firstWhere((d) => d.name == 'Mang Juan');
      expect(juan.currentBalance, 15000);

      final txs = await dbService.getCustomerTransactions(debtor.id);
      expect(txs.isNotEmpty, true);
      expect(txs.first.type, 'debt');
      expect(txs.first.amount, 15000);
      expect(txs.first.resultingBalance, 15000);
      expect(txs.first.notes, 'Initial borrowed balance: Borrowed for groceries');
    });

    test('Records customer payment and reduces debt balance', () async {
      final debtors = await dbService.getDebtors();
      final alingNena = debtors.firstWhere((d) => d.name == 'Aling Nena');
      final initialBalance = alingNena.currentBalance;
      expect(initialBalance > 0, true);

      // Pay 10000 centavos (100.00 pesos)
      final paymentResult = await dbService.recordPayment(
        alingNena.id,
        10000,
        notes: 'Partial cash payment',
      );

      expect(paymentResult['success'], true);
      expect(paymentResult['new_balance'], initialBalance - 10000);

      // Verify transaction ledger
      final txs = await dbService.getCustomerTransactions(alingNena.id);
      expect(txs.first.type, 'payment');
      expect(txs.first.amount, 10000);
      expect(txs.first.resultingBalance, initialBalance - 10000);

      // Rejects payment exceeding debt
      expect(
        () => dbService.recordPayment(alingNena.id, 999999999),
        throwsException,
      );
    });

    test('Retrieves sales history and individual receipt details', () async {
      final egg = (await dbService.lookupBarcode('1'))!;
      final receipt = await dbService.checkout(
        items: [CartItem(product: egg, quantity: 3)],
        tenderedAmount: 5000,
      );

      final salesData = await dbService.getSales();
      final sales = salesData['sales'] as List<SalesSummary>;
      expect(sales.isNotEmpty, true);
      expect(sales.first.id, receipt.saleId);
      expect(sales.first.totalAmount, 3300);

      final fetchedReceipt = await dbService.getReceipt(receipt.saleId);
      expect(fetchedReceipt.saleId, receipt.saleId);
      expect(fetchedReceipt.totalAmount, 3300);
      expect(fetchedReceipt.items.length, 1);
      expect(fetchedReceipt.items.first.quantity, 3);
    });

    test('SalesProvider automatically syncs and retrieves sales after checkout', () async {
      final api = ApiService(database: dbService);
      final salesProv = SalesProvider(api: api);
      await salesProv.loadSales();
      final initialCount = salesProv.sales.length;

      final egg = (await dbService.lookupBarcode('1'))!;
      final receipt = await dbService.checkout(
        items: [CartItem(product: egg, quantity: 2)],
        tenderedAmount: 5000,
      );

      // Provider reloads sales
      await salesProv.loadSales();
      expect(salesProv.sales.length, initialCount + 1);
      expect(salesProv.sales.first.id, receipt.saleId);
      expect(salesProv.sales.first.totalAmount, 2200);

      // Verify receipt retrieval through SalesProvider
      final fetchedReceipt = await salesProv.getReceipt(receipt.saleId);
      expect(fetchedReceipt.saleId, receipt.saleId);
      expect(fetchedReceipt.items.first.productName, 'Egg');
      expect(fetchedReceipt.items.first.quantity, 2);
    });

    test('Computes analytics KPIs, top 5 popular products, and 7-day sales trend', () async {
      final egg = (await dbService.lookupBarcode('1'))!;
      final hotdog = (await dbService.lookupBarcode('333333333331'))!;

      // Checkout a sale
      await dbService.checkout(
        items: [
          CartItem(product: egg, quantity: 4), // 4 * 1100 = 4400
          CartItem(product: hotdog, quantity: 2), // 2 * 1200 = 2400
        ],
        tenderedAmount: 10000,
      );

      final api = ApiService(database: dbService);
      final analyticsProv = AnalyticsProvider(api: api);
      await analyticsProv.loadAnalytics();

      final data = analyticsProv.data;
      expect(data, isNotNull);

      // Verify KPIs
      expect(data!.kpis.today >= 6800, true);
      expect(data.kpis.week >= 6800, true);
      expect(data.kpis.month >= 6800, true);
      expect(data.kpis.year >= 6800, true);

      // Verify Popular Products
      expect(data.popularItems.isNotEmpty, true);
      final popularEgg = data.popularItems.firstWhere((p) => p.name == 'Egg');
      expect(popularEgg.timesSold, 4);
      expect(popularEgg.revenue, 4400);

      // Verify default days trend
      expect(data.chartData.period, SalesTrendPeriod.days);
      expect(data.chartData.labels.length, 7);
      expect(data.chartData.data.length, 7);
      expect(data.chartData.data.last >= 6800, true);

      // Verify Weekly trend
      final weeklyTrend = await dbService.getSalesTrend(SalesTrendPeriod.week);
      expect(weeklyTrend.period, SalesTrendPeriod.week);
      expect(weeklyTrend.labels.length, 7);
      expect(weeklyTrend.data.length, 7);
      expect(weeklyTrend.data.last >= 6800, true);

      // Verify Monthly trend
      final monthlyTrend = await dbService.getSalesTrend(SalesTrendPeriod.months);
      expect(monthlyTrend.period, SalesTrendPeriod.months);
      expect(monthlyTrend.labels.length, 6);
      expect(monthlyTrend.data.length, 6);
      expect(monthlyTrend.data.last >= 6800, true);

      // Verify Yearly trend
      final yearlyTrend = await dbService.getSalesTrend(SalesTrendPeriod.year);
      expect(yearlyTrend.period, SalesTrendPeriod.year);
      expect(yearlyTrend.labels.length, 5);
      expect(yearlyTrend.data.length, 5);
      expect(yearlyTrend.data.last >= 6800, true);
    });

    test('getSales filters records by date range, customer, item name, and receipt ID', () async {
      final egg = (await dbService.lookupBarcode('1'))!;
      final beer = (await dbService.lookupBarcode('4800016644804'))!; // San Miguel Pale Pilsen

      // Sale 1: Cash sale with Egg
      final receipt1 = await dbService.checkout(
        items: [CartItem(product: egg, quantity: 1)],
        tenderedAmount: 5000,
      );

      // Sale 2: Debt sale with Beer to Aling Nena
      final debtors = await dbService.getDebtors();
      final alingNena = debtors.firstWhere((d) => d.name == 'Aling Nena');
      final receipt2 = await dbService.checkout(
        items: [CartItem(product: beer, quantity: 1)],
        tenderedAmount: 0,
        debtorId: alingNena.id,
      );

      // 1. Search by exact receipt ID (e.g. searching '1' only returns sale #1, not others)
      final resId = await dbService.getSales(search: '${receipt1.saleId}');
      final salesId = resId['sales'] as List<SalesSummary>;
      expect(salesId.length, 1);
      expect(salesId.first.id, receipt1.saleId);

      // 2. Searching item names no longer matches (items removed from search)
      final resItem = await dbService.getSales(search: 'Pilsen');
      final salesItem = resItem['sales'] as List<SalesSummary>;
      expect(salesItem.isEmpty, true);

      // 3. Search by customer name
      final resCustomer = await dbService.getSales(search: 'Aling Nena');
      final salesCustomer = resCustomer['sales'] as List<SalesSummary>;
      expect(salesCustomer.any((s) => s.id == receipt2.saleId), true);
      expect(salesCustomer.any((s) => s.id == receipt1.saleId), false);
      expect(salesCustomer.first.customerName, 'Aling Nena');
      expect(salesCustomer.first.paymentType, 'debt');

      // 4. Date range filter
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toIso8601String();
      final resToday = await dbService.getSales(from: todayStart, to: todayEnd);
      final salesToday = resToday['sales'] as List<SalesSummary>;
      expect(salesToday.length >= 2, true);

      // Future date range should return 0
      final futureStart = DateTime(now.year + 1, 1, 1).toIso8601String();
      final futureEnd = DateTime(now.year + 1, 1, 2).toIso8601String();
      final resFuture = await dbService.getSales(from: futureStart, to: futureEnd);
      final salesFuture = resFuture['sales'] as List<SalesSummary>;
      expect(salesFuture.isEmpty, true);
    });

    test('Reset to sample data clears and restores initial dataset', () async {
      // Create extra customer
      await dbService.createDebtor('Temporary Customer');
      var debtors = await dbService.getDebtors();
      expect(debtors.any((d) => d.name == 'Temporary Customer'), true);

      // Reset
      await dbService.resetToSampleData();
      debtors = await dbService.getDebtors();
      expect(debtors.any((d) => d.name == 'Temporary Customer'), false);
      expect(debtors.any((d) => d.name == 'Aling Nena'), true);
    });
  });
}
