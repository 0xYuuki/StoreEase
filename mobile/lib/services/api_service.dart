import '../models/models.dart';
import 'database_service.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final String message;
  final String? code;
  final int statusCode;

  ApiException(this.message, {this.code, this.statusCode = 500});

  @override
  String toString() => message;
}

/// Offline Data Service Facade
/// Bridges UI screens and providers directly to the local SQLite database.
class ApiService {
  final DatabaseService database;
  final StorageService? storage;

  ApiService({required this.database, this.storage});

  // Session & Connection test (Verifies local database connectivity)
  Future<String> testConnection() async {
    final health = await database.checkHealth();
    if (health['status'] == 'Healthy') {
      return 'Offline SQLite (Local DB - Healthy)';
    }
    return 'Offline SQLite (Integrity check: ${health['integrity']})';
  }

  // Products
  Future<Product> createProduct({
    String? barcodeString,
    required String name,
    required int priceCentavos,
    num? initialStock,
    num? reorderLevel,
    String category = 'General',
    String pricingType = 'unit',
    String unit = 'pc',
    bool isBarcodeless = false,
  }) async {
    return await database.createProduct(
      barcodeString: barcodeString,
      name: name,
      priceCentavos: priceCentavos,
      initialStock: initialStock,
      reorderLevel: reorderLevel,
      category: category,
      pricingType: pricingType,
      unit: unit,
      isBarcodeless: isBarcodeless,
    );
  }

  Future<List<Product>> getProducts() async {
    return await database.getProducts();
  }

  Future<Product?> lookupBarcode(String barcode) async {
    return await database.lookupBarcode(barcode);
  }

  // Stock Adjustment
  Future<Product> adjustStock(int productId, num delta, String reason) async {
    return await database.adjustStock(productId, delta, reason);
  }

  // Stock History
  Future<Map<String, dynamic>> getStockHistory(int productId, {int page = 1}) async {
    return await database.getStockHistory(productId, page: page);
  }

  // Checkout (Atomic sale)
  Future<SaleReceipt> checkout({
    required List<CartItem> items,
    required int tenderedAmount,
    int? debtorId,
    String? newDebtorName,
    String? idempotencyKey,
  }) async {
    return await database.checkout(
      items: items,
      tenderedAmount: tenderedAmount,
      debtorId: debtorId,
      newDebtorName: newDebtorName,
      idempotencyKey: idempotencyKey,
    );
  }

  // Debt Management
  Future<Map<String, dynamic>> getDebtsSummary() async {
    return await database.getDebtsSummary();
  }

  Future<List<Debtor>> getDebtors() async {
    return await database.getDebtors();
  }

  Future<Debtor> createDebtor(
    String name, {
    int initialDebtCentavos = 0,
    String? phone,
    String? notes,
  }) async {
    return await database.createDebtor(
      name,
      initialDebtCentavos: initialDebtCentavos,
      phone: phone,
      notes: notes,
    );
  }

  Future<List<DebtTransaction>> getCustomerTransactions(int customerId) async {
    return await database.getCustomerTransactions(customerId);
  }

  Future<Map<String, dynamic>> recordPayment(int customerId, int amountCentavos, {String? notes}) async {
    return await database.recordPayment(customerId, amountCentavos, notes: notes);
  }

  // Sales History
  Future<Map<String, dynamic>> getSales({String? from, String? to, String? search, int page = 1}) async {
    return await database.getSales(from: from, to: to, search: search, page: page);
  }

  Future<SaleReceipt> getReceipt(int saleId) async {
    return await database.getReceipt(saleId);
  }

  // Analytics Dashboard
  Future<AnalyticsData> getAnalytics({SalesTrendPeriod period = SalesTrendPeriod.days}) async {
    return await database.getAnalytics(period: period);
  }

  Future<ChartData> getSalesTrend(SalesTrendPeriod period) async {
    return await database.getSalesTrend(period);
  }
}
