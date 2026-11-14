import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final String message;
  final String? code;
  final int statusCode;

  ApiException(this.message, {this.code, this.statusCode = 500});

  @override
  String toString() => message;
}

class ApiService {
  final StorageService storage;
  final http.Client client;
  final Uuid _uuid = const Uuid();

  ApiService({required this.storage, http.Client? client})
      : client = client ?? http.Client();

  Future<Map<String, String>> _headers({String? idempotencyKey}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = await storage.getAuthToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (idempotencyKey != null) {
      headers['Idempotency-Key'] = idempotencyKey;
    }
    return headers;
  }

  Future<Uri> _uri(String path, [Map<String, dynamic>? query]) async {
    final baseUrl = await storage.getServerUrl();
    final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$cleanBase$cleanPath').replace(queryParameters: query);
  }

  dynamic _processResponse(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      body = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    String message = 'Request failed (${response.statusCode})';
    String? code;

    if (body is Map<String, dynamic>) {
      message = body['error'] ?? body['message'] ?? message;
      code = body['code'];
    }

    throw ApiException(message, code: code, statusCode: response.statusCode);
  }

  // Session & Connection test
  Future<String> testConnection() async {
    final uri = await _uri('/api/session');
    final response = await client.get(uri, headers: await _headers());
    final data = _processResponse(response);
    return (data is Map && data['role'] != null) ? data['role'] as String : 'connected';
  }

  // Products
  Future<List<Product>> getProducts() async {
    final uri = await _uri('/api/products');
    final response = await client.get(uri, headers: await _headers());
    final data = _processResponse(response);
    if (data is List) {
      return data.map((json) => Product.fromJson(json as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<Product?> lookupBarcode(String barcode) async {
    final encoded = Uri.encodeComponent(barcode.trim());
    final uri = await _uri('/api/products/$encoded');
    try {
      final response = await client.get(uri, headers: await _headers());
      final data = _processResponse(response);
      if (data is Map<String, dynamic>) {
        return Product.fromJson(data);
      }
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
    return null;
  }

  // Stock Adjustment
  Future<Product> adjustStock(int productId, int delta, String reason) async {
    final uri = await _uri('/api/products/$productId/stock');
    final response = await client.post(
      uri,
      headers: await _headers(),
      body: jsonEncode({'delta': delta, 'reason': reason.trim()}),
    );
    final data = _processResponse(response);
    return Product.fromJson(data as Map<String, dynamic>);
  }

  // Stock History
  Future<Map<String, dynamic>> getStockHistory(int productId, {int page = 1}) async {
    final uri = await _uri('/api/products/$productId/stock-history', {'page': '$page'});
    final response = await client.get(uri, headers: await _headers());
    final data = _processResponse(response) as Map<String, dynamic>;
    final rawEntries = (data['entries'] as List<dynamic>? ?? []);
    final entries = rawEntries
        .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
        .toList();
    return {
      'entries': entries,
      'has_more': data['has_more'] as bool? ?? false,
    };
  }

  // Checkout (Atomic sale)
  Future<SaleReceipt> checkout({
    required List<CartItem> items,
    required int tenderedAmount,
    int? debtorId,
    String? newDebtorName,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? _uuid.v4();
    final uri = await _uri('/api/sales');
    final payload = <String, dynamic>{
      'items': items.map((i) => {
        'product_id': i.product.id,
        'quantity': i.quantity,
      }).toList(),
      'tendered_amount': tenderedAmount,
    };

    if (debtorId != null) {
      payload['debtor_id'] = debtorId;
    } else if (newDebtorName != null && newDebtorName.trim().isNotEmpty) {
      payload['debtor_name'] = newDebtorName.trim();
    }

    final response = await client.post(
      uri,
      headers: await _headers(idempotencyKey: key),
      body: jsonEncode(payload),
    );
    final data = _processResponse(response);
    return SaleReceipt.fromJson(data as Map<String, dynamic>);
  }

  // Debt Management
  Future<Map<String, dynamic>> getDebtsSummary() async {
    final uri = await _uri('/api/debts/summary');
    final response = await client.get(uri, headers: await _headers());
    return _processResponse(response) as Map<String, dynamic>;
  }

  Future<List<Debtor>> getDebtors() async {
    final uri = await _uri('/api/debts/customers');
    final response = await client.get(uri, headers: await _headers());
    final data = _processResponse(response);
    if (data is List) {
      return data.map((d) => Debtor.fromJson(d as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<Debtor> createDebtor(String name) async {
    final uri = await _uri('/api/debts/customers');
    final response = await client.post(
      uri,
      headers: await _headers(),
      body: jsonEncode({'name': name.trim()}),
    );
    final data = _processResponse(response);
    return Debtor.fromJson(data as Map<String, dynamic>);
  }

  Future<List<DebtTransaction>> getCustomerTransactions(int customerId) async {
    final uri = await _uri('/api/debts/customers/$customerId/transactions');
    final response = await client.get(uri, headers: await _headers());
    final data = _processResponse(response);
    if (data is List) {
      return data
          .map((t) => DebtTransaction.fromJson(t as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> recordPayment(int customerId, int amountCentavos, {String? notes}) async {
    final uri = await _uri('/api/debts/customers/$customerId/payment');
    final payload = <String, dynamic>{'amount': amountCentavos};
    if (notes != null && notes.trim().isNotEmpty) {
      payload['notes'] = notes.trim();
    }
    final response = await client.post(
      uri,
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    return _processResponse(response) as Map<String, dynamic>;
  }

  // Sales History
  Future<Map<String, dynamic>> getSales({String? from, String? to, int page = 1}) async {
    final query = <String, dynamic>{'page': '$page'};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;

    final uri = await _uri('/api/sales', query);
    final response = await client.get(uri, headers: await _headers());
    final data = _processResponse(response) as Map<String, dynamic>;
    final rawSales = (data['sales'] as List<dynamic>? ?? []);
    final sales = rawSales
        .map((s) => SalesSummary.fromJson(s as Map<String, dynamic>))
        .toList();
    return {
      'sales': sales,
      'has_more': data['has_more'] as bool? ?? false,
    };
  }

  Future<SaleReceipt> getReceipt(int saleId) async {
    final uri = await _uri('/api/sales/$saleId');
    final response = await client.get(uri, headers: await _headers());
    final data = _processResponse(response);
    return SaleReceipt.fromJson(data as Map<String, dynamic>);
  }
}
