import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class CartProvider extends ChangeNotifier {
  final ApiService api;
  final List<CartItem> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  CartProvider({required this.api});

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get itemCount =>
      _items.fold(0, (sum, i) => sum + (i.isWeighted ? 1 : i.quantity));

  int get totalCentavos =>
      _items.fold(0, (sum, item) => sum + item.lineTotalCentavos);

  double get totalPesos => totalCentavos / 100.0;
  String get formattedTotal => '₱${totalPesos.toStringAsFixed(2)}';

  void addProduct(Product product, {double? weight}) {
    final existingIndex =
        _items.indexWhere((i) => i.product.id == product.id);
    if (product.isWeighted) {
      final w = weight ?? 1.0;
      if (existingIndex >= 0) {
        final currentWeight = _items[existingIndex].weight ?? 0.0;
        _items[existingIndex].weight = currentWeight + w;
      } else {
        _items.add(CartItem(product: product, quantity: 1, weight: w));
      }
    } else {
      if (existingIndex >= 0) {
        _items[existingIndex].quantity += 1;
      } else {
        _items.add(CartItem(product: product, quantity: 1));
      }
    }
    _errorMessage = null;
    notifyListeners();
  }

  void updateWeight(int productId, double newWeight) {
    final index = _items.indexWhere((i) => i.product.id == productId);
    if (index >= 0) {
      if (newWeight <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].weight = newWeight;
      }
      notifyListeners();
    }
  }

  void updateQuantity(int productId, int newQuantity) {
    final index = _items.indexWhere((i) => i.product.id == productId);
    if (index >= 0) {
      if (newQuantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].quantity = newQuantity;
      }
      notifyListeners();
    }
  }

  void incrementQuantity(int productId) {
    final index = _items.indexWhere((i) => i.product.id == productId);
    if (index >= 0) {
      if (_items[index].isWeighted) {
        _items[index].weight = (_items[index].weight ?? 1.0) + 0.25;
      } else {
        _items[index].quantity += 1;
      }
      notifyListeners();
    }
  }

  void decrementQuantity(int productId) {
    final index = _items.indexWhere((i) => i.product.id == productId);
    if (index >= 0) {
      if (_items[index].isWeighted) {
        final current = _items[index].weight ?? 1.0;
        if (current > 0.25) {
          _items[index].weight = current - 0.25;
        } else {
          _items.removeAt(index);
        }
      } else {
        if (_items[index].quantity > 1) {
          _items[index].quantity -= 1;
        } else {
          _items.removeAt(index);
        }
      }
      notifyListeners();
    }
  }

  void removeItem(int productId) {
    _items.removeWhere((i) => i.product.id == productId);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _errorMessage = null;
    notifyListeners();
  }

  Future<SaleReceipt?> checkout({
    required int tenderedAmountCentavos,
    int? debtorId,
    String? newDebtorName,
  }) async {
    if (_items.isEmpty) {
      _errorMessage = 'Cart is empty';
      notifyListeners();
      return null;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final receipt = await api.checkout(
        items: _items,
        tenderedAmount: tenderedAmountCentavos,
        debtorId: debtorId,
        newDebtorName: newDebtorName,
      );
      _items.clear();
      _isLoading = false;
      notifyListeners();
      return receipt;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }
}
