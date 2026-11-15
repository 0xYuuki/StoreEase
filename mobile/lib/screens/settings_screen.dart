import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;

  Map<String, dynamic> _stats = {
    'product_count': 0,
    'sales_count': 0,
    'customer_count': 0,
    'total_debt': 0,
    'integrity': 'ok',
  };

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final db = context.read<DatabaseService>();
      final health = await db.checkHealth();
      if (mounted) {
        setState(() {
          _stats = health;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _testDatabase() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final db = context.read<DatabaseService>();
      final health = await db.checkHealth();
      await _loadStats();

      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _testSuccess = health['integrity'] == 'ok';
        _testResult = _testSuccess
            ? 'Local SQLite database is healthy! (Integrity: ${health['integrity']}, Products: ${health['product_count']}, Sales: ${health['sales_count']})'
            : 'Database integrity warning: ${health['integrity']}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testResult = 'Database error: $e';
      });
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to Starter Catalog?'),
        content: const Text(
          'This will clear existing sales and reset products and customer ledger back to the default starter dataset. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final db = context.read<DatabaseService>();
        await db.resetToSampleData();
        await _loadStats();
        if (mounted) {
          context.read<DebtProvider>().loadDebts();
          context.read<ProductProvider>().loadProducts();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Database reset and seeded successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to reset: $e'), backgroundColor: AppTheme.dangerRed),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final totalDebtPesos = ((_stats['total_debt'] as int? ?? 0) / 100.0).toStringAsFixed(2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Storage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Stats',
            onPressed: _loadStats,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            Image.asset(
              'assets/logo.png',
              height: 70,
              errorBuilder: (_, _, _) => const Icon(Icons.store, size: 64, color: AppTheme.primaryGreen),
            ),
            const SizedBox(height: 8),
            const Text(
              "Helen's Store Mobile POS",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Version 1.0.0 (Native Offline Flutter)',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),

            // Storage Mode Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.storage_rounded, color: AppTheme.primaryDark, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Offline SQLite Database',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                '100% Offline · Local Device Storage',
                                style: TextStyle(fontSize: 12, color: AppTheme.primaryGreen, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text(
                      'DATABASE METRICS',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildMetricTile('Products', '${_stats['product_count']}', Icons.inventory_2_outlined),
                        const SizedBox(width: 8),
                        _buildMetricTile('Sales Recorded', '${_stats['sales_count']}', Icons.receipt_long_outlined),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildMetricTile('Debtors', '${_stats['customer_count']}', Icons.people_outline),
                        const SizedBox(width: 8),
                        _buildMetricTile('Total Debt', '₱$totalDebtPesos', Icons.account_balance_wallet_outlined),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: _isTesting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.health_and_safety_outlined, size: 18),
                            label: const Text('Test Database'),
                            onPressed: _isTesting ? null : _testDatabase,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
                            icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
                            label: const Text('Reset Sample', style: TextStyle(color: Colors.white)),
                            onPressed: _confirmReset,
                          ),
                        ),
                      ],
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _testSuccess ? AppTheme.primaryLight : AppTheme.dangerLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _testSuccess ? AppTheme.primaryGreen : AppTheme.dangerRed,
                          ),
                        ),
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _testSuccess ? AppTheme.primaryDark : AppTheme.dangerRed,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Store Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.info_outline, color: AppTheme.primaryGreen, size: 20),
                        SizedBox(width: 8),
                        Text('Store Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Store Name', "Helen's Store"),
                    _buildInfoRow('Currency', 'Philippine Peso (PHP, ₱)'),
                    _buildInfoRow('Storage Engine', 'SQLite 3 (Embedded)'),
                    _buildInfoRow('Scanner Mode', 'Camera Mobile Barcode'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.primaryGreen),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
