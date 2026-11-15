import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class ProductProvider extends ChangeNotifier {
  final ApiService api;
  List<Product> _products = [];
  bool _isLoading = false;
  String? _errorMessage;

  ProductProvider({required this.api});

  List<Product> get products => List.unmodifiable(_products);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadProducts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _products = await api.getProducts();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<Product?> lookupBarcode(String barcode) async {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;

    // Check in-memory list first
    final match = _products.where((p) => p.barcodeString == clean);
    if (match.isNotEmpty) return match.first;

    // Direct database fallback lookup in case a product was just added
    final direct = await api.lookupBarcode(clean);
    if (direct != null) {
      await loadProducts();
      return direct;
    }
    return null;
  }

  Future<Product> createProduct({
    required String barcodeString,
    required String name,
    required int priceCentavos,
    int? initialStock,
    int? reorderLevel,
    String category = 'General',
  }) async {
    try {
      final newProduct = await api.createProduct(
        barcodeString: barcodeString,
        name: name,
        priceCentavos: priceCentavos,
        initialStock: initialStock,
        reorderLevel: reorderLevel,
        category: category,
      );
      await loadProducts();
      return newProduct;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<Product> adjustStock(int productId, int delta, String reason) async {
    try {
      final updated = await api.adjustStock(productId, delta, reason);
      await loadProducts();
      return updated;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }
}
