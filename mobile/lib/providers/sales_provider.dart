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

  // Active filter state
  String? _from;
  String? _to;
  String? _search;

  SalesProvider({required this.api});

  List<SalesSummary> get sales => List.unmodifiable(_sales);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get page => _page;
  bool get hasMore => _hasMore;
  String? get from => _from;
  String? get to => _to;
  String? get search => _search;

  bool get hasActiveFilters =>
      _from != null || _to != null || (_search != null && _search!.trim().isNotEmpty);

  int get totalFilteredAmount => _sales.fold(0, (sum, s) => sum + s.totalAmount);

  Future<void> loadSales({
    int page = 1,
    String? from,
    String? to,
    String? search,
    bool isFilterChange = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    if (isFilterChange) {
      _from = from;
      _to = to;
      _search = search;
    }

    final effectiveFrom = isFilterChange ? from : (from ?? _from);
    final effectiveTo = isFilterChange ? to : (to ?? _to);
    final effectiveSearch = isFilterChange ? search : (search ?? _search);

    try {
      final data = await api.getSales(
        from: effectiveFrom,
        to: effectiveTo,
        search: effectiveSearch,
        page: page,
      );
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

  Future<void> clearFilters() async {
    _from = null;
    _to = null;
    _search = null;
    await loadSales(page: 1, isFilterChange: true);
  }

  Future<SaleReceipt> getReceipt(int saleId) async {
    return await api.getReceipt(saleId);
  }
}
