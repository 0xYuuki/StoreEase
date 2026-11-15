import 'package:flutter_test/flutter_test.dart';
import 'package:helen_store_mobile/models/models.dart';
import 'package:helen_store_mobile/providers/cart_provider.dart';
import 'package:helen_store_mobile/providers/product_provider.dart';
import 'package:helen_store_mobile/services/api_service.dart';
import 'package:helen_store_mobile/services/database_service.dart';
import 'package:helen_store_mobile/services/storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Models & Calculations', () {
    test('Product JSON deserialization and currency conversion', () {
      final json = {
        'id': 1,
        'barcode_string': '000123',
        'name': 'Egg',
        'price': 1205, // 1205 centavos = 12.05 pesos
        'stock': 5,
        'reorder_level': 10,
        'active': 1,
      };

      final product = Product.fromJson(json);

      expect(product.id, 1);
      expect(product.barcodeString, '000123');
      expect(product.name, 'Egg');
      expect(product.priceCentavos, 1205);
      expect(product.pricePesos, 12.05);
      expect(product.formattedPrice, '₱12.05');
      expect(product.isLowStock, true);
      expect(product.category, 'General');

      final withCategory = Product.fromJson({
        ...json,
        'category': 'Fresh & Grocery',
      });
      expect(withCategory.category, 'Fresh & Grocery');
      expect(withCategory.toJson()['category'], 'Fresh & Grocery'); // stock 5 <= reorder_level 10
    });

    test('CartItem and CartProvider line total & exact money sum', () {
      final p1 = Product(id: 1, barcodeString: '1', name: 'Egg', priceCentavos: 1100);
      final p2 = Product(id: 2, barcodeString: '2', name: 'Bread', priceCentavos: 5550);

      final storage = StorageService();
      final db = DatabaseService();
      final api = ApiService(database: db, storage: storage);
      final cart = CartProvider(api: api);

      expect(cart.items.isEmpty, true);
      expect(cart.totalCentavos, 0);

      cart.addProduct(p1);
      expect(cart.items.length, 1);
      expect(cart.itemCount, 1);
      expect(cart.totalCentavos, 1100);
      expect(cart.formattedTotal, '₱11.00');

      // Adding same product increments quantity
      cart.addProduct(p1);
      expect(cart.items.length, 1);
      expect(cart.itemCount, 2);
      expect(cart.totalCentavos, 2200);

      // Adding distinct product
      cart.addProduct(p2);
      expect(cart.items.length, 2);
      expect(cart.itemCount, 3);
      expect(cart.totalCentavos, 7750); // 2200 + 5550
      expect(cart.formattedTotal, '₱77.50');

      // Decrementing
      cart.decrementQuantity(p1.id);
      expect(cart.items.firstWhere((i) => i.product.id == p1.id).quantity, 1);

      // Removing item
      cart.removeItem(p2.id);
      expect(cart.items.length, 1);
      expect(cart.totalCentavos, 1100);

      // Clear
      cart.clear();
      expect(cart.items.isEmpty, true);
      expect(cart.totalCentavos, 0);
    });

    test('Debtor JSON parsing and balance status', () {
      final jsonActive = {
        'id': 10,
        'name': 'Maria Santos',
        'current_balance': 4500, // 45.00 pesos
        'active_debt': true,
      };

      final activeDebtor = Debtor.fromJson(jsonActive);
      expect(activeDebtor.id, 10);
      expect(activeDebtor.name, 'Maria Santos');
      expect(activeDebtor.currentBalance, 4500);
      expect(activeDebtor.balancePesos, 45.0);
      expect(activeDebtor.formattedBalance, '₱45.00');
      expect(activeDebtor.activeDebt, true);

      final jsonPaid = {
        'id': 11,
        'name': 'Juan Dela Cruz',
        'current_balance': 0,
        'active_debt': false,
      };

      final paidDebtor = Debtor.fromJson(jsonPaid);
      expect(paidDebtor.currentBalance, 0);
      expect(paidDebtor.formattedBalance, '₱0.00');
      expect(paidDebtor.activeDebt, false);
    });

    test('DebtTransaction deserialization and properties', () {
      final json = {
        'id': 101,
        'customer_id': 10,
        'type': 'payment',
        'amount': 2000,
        'resulting_balance': 2500,
        'notes': 'Partial cash payment',
        'sale_id': null,
        'created_at': '2026-11-14T10:00:00Z',
      };

      final tx = DebtTransaction.fromJson(json);
      expect(tx.id, 101);
      expect(tx.isPayment, true);
      expect(tx.amountPesos, 20.0);
      expect(tx.formattedAmount, '₱20.00');
      expect(tx.resultingBalancePesos, 25.0);
      expect(tx.formattedResultingBalance, '₱25.00');
    });

    test('AnalyticsData and AnalyticsKpis deserialization & currency formatting', () {
      final json = {
        'kpis': {
          'today': 45000,
          'week': 125000,
          'month': 350000,
          'year': 1200000,
        },
        'popularItems': [
          {'name': 'Egg', 'times_sold': 50, 'revenue': 55000},
          {'name': 'Lucky Me! Pancit Canton', 'times_sold': 25, 'revenue': 45000},
        ],
        'chartData': {
          'labels': ['2026-11-09', '2026-11-10', '2026-11-11', '2026-11-12', '2026-11-13', '2026-11-14', '2026-11-15'],
          'data': [10000, 15000, 20000, 12000, 25000, 30000, 45000],
        },
      };

      final analytics = AnalyticsData.fromJson(json);
      expect(analytics.kpis.today, 45000);
      expect(analytics.kpis.todayPesos, 450.0);
      expect(analytics.kpis.formattedToday, '₱450.00');
      expect(analytics.kpis.formattedWeek, '₱1250.00');
      expect(analytics.kpis.formattedMonth, '₱3500.00');
      expect(analytics.kpis.formattedYear, '₱12000.00');

      expect(analytics.popularItems.length, 2);
      expect(analytics.popularItems.first.name, 'Egg');
      expect(analytics.popularItems.first.timesSold, 50);
      expect(analytics.popularItems.first.revenuePesos, 550.0);
      expect(analytics.popularItems.first.formattedRevenue, '₱550.00');

      expect(analytics.chartData.labels.length, 7);
      expect(analytics.chartData.data.length, 7);
      expect(analytics.chartData.data.last, 45000);
      expect(analytics.chartData.period, SalesTrendPeriod.days);
      expect(analytics.chartData.totalCentavos, 157000);
      expect(analytics.chartData.peakCentavos, 45000);
      expect(analytics.chartData.averagePesos, closeTo(224.28, 0.01));
    });

    test('ChartData serializes and deserializes period correctly', () {
      final chart = ChartData(
        labels: ['Jan', 'Feb', 'Mar'],
        data: [1000, 2000, 3000],
        period: SalesTrendPeriod.months,
      );

      final json = chart.toJson();
      expect(json['period'], 'months');

      final fromJson = ChartData.fromJson(json);
      expect(fromJson.period, SalesTrendPeriod.months);
      expect(fromJson.labels, ['Jan', 'Feb', 'Mar']);
      expect(fromJson.data, [1000, 2000, 3000]);
      expect(fromJson.totalCentavos, 6000);
      expect(fromJson.peakCentavos, 3000);
      expect(fromJson.averagePesos, 20.0);
    });

    test('Barcodeless & Weighted Product Models and Cart Calculations', () {
      final looseEgg = Product(
        id: 101,
        barcodeString: 'PLU-1001',
        name: 'Native Egg',
        priceCentavos: 800, // ₱8.00 / pc
        stock: 50,
        isBarcodeless: true,
      );
      expect(looseEgg.isBarcodeless, true);
      expect(looseEgg.isWeighted, false);
      expect(looseEgg.formattedPrice, '₱8.00');
      expect(looseEgg.formattedStock, '50 pcs');

      final weightedRice = Product(
        id: 102,
        barcodeString: 'PLU-1002',
        name: 'Sinandomeng Rice',
        priceCentavos: 5200, // ₱52.00 / kg
        stock: 48.5,
        pricingType: 'weight',
        unit: 'kg',
        isBarcodeless: true,
      );
      expect(weightedRice.isBarcodeless, true);
      expect(weightedRice.isWeighted, true);
      expect(weightedRice.formattedPrice, '₱52.00 / kg');
      expect(weightedRice.formattedStock, '48.50 kg');

      // Cart Calculations with Fractional Weights
      final storage = StorageService();
      final db = DatabaseService();
      final api = ApiService(database: db, storage: storage);
      final cart = CartProvider(api: api);

      // Add 0.50 kg (kalahati) of Rice -> 0.50 * 52.00 = ₱26.00 (2600 centavos)
      cart.addProduct(weightedRice, weight: 0.50);
      expect(cart.items.length, 1);
      expect(cart.totalCentavos, 2600);
      expect(cart.formattedTotal, '₱26.00');
      expect(cart.items.first.formattedQuantityOrWeight, '0.50 kg');

      // Add 3 loose eggs -> 3 * 8.00 = ₱24.00 (2400 centavos)
      cart.addProduct(looseEgg);
      cart.addProduct(looseEgg);
      cart.addProduct(looseEgg);
      expect(cart.items.length, 2);
      expect(cart.totalCentavos, 5000); // 2600 + 2400
      expect(cart.formattedTotal, '₱50.00');

      // Increment weight by 0.25 kg -> 0.75 kg * 52.00 = ₱39.00
      cart.incrementQuantity(weightedRice.id);
      expect(cart.items.first.weight, 0.75);
      expect(cart.items.first.lineTotalCentavos, 3900);
      expect(cart.totalCentavos, 6300); // 3900 + 2400

      // Update weight directly to 1/4 kg (0.25 kg) -> 0.25 * 52.00 = ₱13.00
      cart.updateWeight(weightedRice.id, 0.25);
      expect(cart.items.first.weight, 0.25);
      expect(cart.items.first.lineTotalCentavos, 1300);
      expect(cart.totalCentavos, 3700); // 1300 + 2400

      // SaleItem serialization
      final saleItem = SaleItem(
        productId: weightedRice.id,
        productName: weightedRice.name,
        barcodeString: weightedRice.barcodeString,
        quantity: 1,
        weight: 0.50,
        unit: 'kg',
        price: 5200,
        lineTotal: 2600,
      );
      expect(saleItem.isWeighted, true);
      expect(saleItem.formattedQuantityOrWeight, '0.50 kg');
      expect(saleItem.lineTotalPesos, 26.0);
    });

    test('ProductProvider calculates low stock items and generates formatted shopping list', () async {
      final db = DatabaseService();
      await db.init(customPath: inMemoryDatabasePath);
      final storage = StorageService();
      final api = ApiService(database: db, storage: storage);
      final productProv = ProductProvider(api: api);

      // Create products: 2 low stock, 1 healthy
      final p1 = await productProv.createProduct(
        name: 'Lucky Me! Pancit Canton',
        priceCentavos: 1500,
        initialStock: 3,
        reorderLevel: 10,
        category: 'Instant Noodles & Snacks',
      );
      final p2 = await productProv.createProduct(
        name: 'Red Onion',
        priceCentavos: 12000,
        initialStock: 0.5,
        reorderLevel: 5.0,
        category: 'Fresh & Grocery',
        pricingType: 'weight',
        unit: 'kg',
        isBarcodeless: true,
      );
      await productProv.createProduct(
        name: 'Coca-Cola 1.5L',
        priceCentavos: 7500,
        initialStock: 24,
        reorderLevel: 6,
        category: 'Beverages',
      );

      expect(productProv.lowStockCount, 2);
      expect(productProv.lowStockProducts.map((p) => p.name), containsAll(['Lucky Me! Pancit Canton', 'Red Onion']));

      // Test getLowStockItemsByIds
      final lowItems = productProv.getLowStockItemsByIds([p1.id, p2.id]);
      expect(lowItems.length, 2);

      // Test shopping list generation
      final listText = productProv.generateShoppingListText();
      expect(listText, contains("Helen's Store — Restock / Shopping List"));
      expect(listText, contains("[Instant Noodles & Snacks]"));
      expect(listText, contains("Lucky Me! Pancit Canton"));
      expect(listText, contains("[Fresh & Grocery]"));
      expect(listText, contains("Red Onion"));
      expect(listText, contains("Total items to restock: 2"));

      await db.close();
    });
  });
}
