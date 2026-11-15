import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class AnalyticsProvider extends ChangeNotifier {
  final ApiService api;
  AnalyticsData? _data;
  SalesTrendPeriod _trendPeriod = SalesTrendPeriod.days;
  bool _isLoading = false;
  String? _errorMessage;

  AnalyticsProvider({required this.api});

  AnalyticsData? get data => _data;
  SalesTrendPeriod get trendPeriod => _trendPeriod;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadAnalytics() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _data = await api.getAnalytics(period: _trendPeriod);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> setTrendPeriod(SalesTrendPeriod period) async {
    if (_trendPeriod == period && _data?.chartData.period == period) return;
    _trendPeriod = period;
    notifyListeners();

    try {
      final trend = await api.getSalesTrend(period);
      if (_data != null) {
        _data = AnalyticsData(
          kpis: _data!.kpis,
          popularItems: _data!.popularItems,
          chartData: trend,
        );
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }
}
