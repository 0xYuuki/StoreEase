import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class AnalyticsProvider extends ChangeNotifier {
  final ApiService api;
  AnalyticsData? _data;
  bool _isLoading = false;
  String? _errorMessage;

  AnalyticsProvider({required this.api});

  AnalyticsData? get data => _data;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadAnalytics() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _data = await api.getAnalytics();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }
}
