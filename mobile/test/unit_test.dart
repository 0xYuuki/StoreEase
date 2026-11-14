import 'package:flutter_test/flutter_test.dart';
import 'package:helen_store_mobile/models/models.dart';
import 'package:helen_store_mobile/providers/cart_provider.dart';
import 'package:helen_store_mobile/services/api_service.dart';
import 'package:helen_store_mobile/services/storage_service.dart';

void main() {
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
      expect(product.isLowStock, true); // stock 5 <= reorder_level 10
    });

    test('CartItem and CartProvider line total & exact money sum', () {
      final p1 = Product(id: 1, barcodeString: '1', name: 'Egg', priceCentavos: 1100);
      final p2 = Product(id: 2, barcodeString: '2', name: 'Bread', priceCentavos: 5550);

      final storage = StorageService();
      final api = ApiService(storage: storage);
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
  });
}
