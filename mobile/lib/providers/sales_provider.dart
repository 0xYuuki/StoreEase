import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class SalesProvider extends ChangeNotifier {
  final ApiService api;
  List<SalesSummary> _sales = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _page = 1;
  bool _hasMore = false;

  SalesProvider({required this.api});

  List<SalesSummary> get sales => List.unmodifiable(_sales);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get page => _page;
  bool get hasMore => _hasMore;

  Future<void> loadSales({int page = 1, String? from, String? to}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await api.getSales(from: from, to: to, page: page);
      final rawSales = data['sales'] as List<SalesSummary>;
      final more = data['has_more'] as bool? ?? false;

      if (page == 1) {
        _sales = rawSales;
      } else {
        _sales.addAll(rawSales);
      }
      _page = page;
      _hasMore = more;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<SaleReceipt> getReceipt(int saleId) async {
    return await api.getReceipt(saleId);
  }
}
