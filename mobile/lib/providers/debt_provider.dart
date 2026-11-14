import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class DebtProvider extends ChangeNotifier {
  final ApiService api;
  List<Debtor> _debtors = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _totalUnpaidCentavos = 0;
  int _activeDebtorsCount = 0;
  String _filter = 'active'; // 'active' | 'paid' | 'all'
  String _searchQuery = '';

  DebtProvider({required this.api});

  List<Debtor> get allDebtors => List.unmodifiable(_debtors);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get filter => _filter;
  String get searchQuery => _searchQuery;

  int get totalUnpaidCentavos => _totalUnpaidCentavos;
  double get totalUnpaidPesos => _totalUnpaidCentavos / 100.0;
  String get formattedTotalUnpaid => '₱${totalUnpaidPesos.toStringAsFixed(2)}';
  int get activeDebtorsCount => _activeDebtorsCount;
  int get fullyPaidCount => _debtors.where((d) => d.currentBalance <= 0).length;

  List<Debtor> get filteredDebtors {
    return _debtors.where((d) {
      // Status filter
      if (_filter == 'active' && d.currentBalance <= 0) return false;
      if (_filter == 'paid' && d.currentBalance > 0) return false;

      // Search query filter
      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.trim().toLowerCase();
        return d.name.toLowerCase().contains(query);
      }
      return true;
    }).toList();
  }

  void setFilter(String newFilter) {
    _filter = newFilter;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> loadDebts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final summaryFuture = api.getDebtsSummary();
      final listFuture = api.getDebtors();

      final results = await Future.wait([summaryFuture, listFuture]);
      final summary = results[0] as Map<String, dynamic>;
      _debtors = results[1] as List<Debtor>;

      _totalUnpaidCentavos = (summary['total_unpaid_debts'] as int?) ?? 0;
      _activeDebtorsCount = (summary['active_debtors_count'] as int?) ?? 0;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<Debtor?> createDebtor(String name) async {
    try {
      final newDebtor = await api.createDebtor(name);
      await loadDebts();
      return newDebtor;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> recordPayment(int customerId, int amountCentavos, {String? notes}) async {
    try {
      await api.recordPayment(customerId, amountCentavos, notes: notes);
      await loadDebts();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }
}
