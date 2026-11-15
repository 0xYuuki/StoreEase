import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/sales_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialogs.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _activeDateFilter = 'all'; // 'all', 'today', 'yesterday', 'week', 'month', 'custom'
  DateTimeRange? _customDateRange;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesProvider>().loadSales();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _viewReceipt(int saleId) async {
    try {
      final salesProv = context.read<SalesProvider>();
      final receipt = await salesProv.getReceipt(saleId);
      if (mounted) {
        AppDialogs.showReceiptDialog(context, receipt);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load receipt: $e'), backgroundColor: AppTheme.dangerRed),
        );
      }
    }
  }

  void _applyFilters() {
    String? from;
    String? to;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    if (_activeDateFilter == 'today') {
      from = todayStart.toIso8601String();
      to = todayEnd.toIso8601String();
    } else if (_activeDateFilter == 'yesterday') {
      final yStart = todayStart.subtract(const Duration(days: 1));
      final yEnd = DateTime(yStart.year, yStart.month, yStart.day, 23, 59, 59, 999);
      from = yStart.toIso8601String();
      to = yEnd.toIso8601String();
    } else if (_activeDateFilter == 'week') {
      final daysSinceSunday = todayStart.weekday % 7;
      final weekStart = todayStart.subtract(Duration(days: daysSinceSunday));
      from = weekStart.toIso8601String();
      to = todayEnd.toIso8601String();
    } else if (_activeDateFilter == 'month') {
      final monthStart = DateTime(now.year, now.month, 1);
      from = monthStart.toIso8601String();
      to = todayEnd.toIso8601String();
    } else if (_activeDateFilter == 'custom' && _customDateRange != null) {
      final cStart = DateTime(_customDateRange!.start.year, _customDateRange!.start.month, _customDateRange!.start.day);
      final cEnd = DateTime(_customDateRange!.end.year, _customDateRange!.end.month, _customDateRange!.end.day, 23, 59, 59, 999);
      from = cStart.toIso8601String();
      to = cEnd.toIso8601String();
    }

    final search = _searchController.text.trim();
    context.read<SalesProvider>().loadSales(
      page: 1,
      from: from,
      to: to,
      search: search.isEmpty ? null : search,
      isFilterChange: true,
    );
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryGreen,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppTheme.textDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _activeDateFilter = 'custom';
        _customDateRange = picked;
      });
      _applyFilters();
    }
  }

  void _clearAllFilters() {
    setState(() {
      _searchController.clear();
      _activeDateFilter = 'all';
      _customDateRange = null;
    });
    context.read<SalesProvider>().clearFilters();
  }

  @override
  Widget build(BuildContext context) {
    final salesProv = context.watch<SalesProvider>();
    final sales = salesProv.sales;
    final isLoading = salesProv.isLoading;
    final hasMore = salesProv.hasMore;
    final page = salesProv.page;
    final hasActiveFilters = salesProv.hasActiveFilters || _searchController.text.isNotEmpty || _activeDateFilter != 'all';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _applyFilters(),
          ),
        ],
      ),
      body: Column(
        children: [
          // --- Filter Header Area ---
          Material(
            color: Colors.white,
            elevation: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by receipt # or customer name...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _applyFilters();
                              },
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _applyFilters(),
                    onChanged: (val) {
                      // Trigger search immediately
                      _applyFilters();
                    },
                  ),
                ),

                // 2. Quick Date Filter Chips
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _buildFilterChip('All Time', 'all', Icons.all_inclusive),
                      const SizedBox(width: 6),
                      _buildFilterChip('Today', 'today', Icons.today),
                      const SizedBox(width: 6),
                      _buildFilterChip('Yesterday', 'yesterday', Icons.history),
                      const SizedBox(width: 6),
                      _buildFilterChip('This Week', 'week', Icons.date_range),
                      const SizedBox(width: 6),
                      _buildFilterChip('This Month', 'month', Icons.calendar_month),
                      const SizedBox(width: 6),
                      _buildCustomDateChip(),
                    ],
                  ),
                ),

                // 3. Filter Summary Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSlate,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, size: 16, color: Colors.grey.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${sales.length} ${sales.length == 1 ? 'sale' : 'sales'} • Total: ₱${(salesProv.totalFilteredAmount / 100.0).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                      if (hasActiveFilters)
                        InkWell(
                          onTap: _clearAllFilters,
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.close, size: 14, color: AppTheme.dangerRed),
                                SizedBox(width: 2),
                                Text(
                                  'Clear Filters',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.dangerRed,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- Sales Records List ---
          Expanded(
            child: isLoading && sales.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : sales.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                hasActiveFilters ? Icons.filter_alt_off_outlined : Icons.receipt_long_outlined,
                                size: 56,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                hasActiveFilters
                                    ? 'No sales found matching your filters'
                                    : 'No sales records found',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                hasActiveFilters
                                    ? 'Try checking a different date range or search keyword.'
                                    : 'Completed transactions from POS will appear here.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                              ),
                              if (hasActiveFilters) ...[
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: _clearAllFilters,
                                  icon: const Icon(Icons.clear_all, size: 18),
                                  label: const Text('Reset All Filters'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: sales.length + (hasMore ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          if (index == sales.length) {
                            return Center(
                              child: TextButton(
                                onPressed: () => context.read<SalesProvider>().loadSales(page: page + 1),
                                child: const Text('Load More Sales'),
                              ),
                            );
                          }

                          final sale = sales[index];
                          final isDebt = sale.paymentType == 'debt' || (sale.customerName != null && sale.customerName!.isNotEmpty);

                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _viewReceipt(sale.id),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: isDebt ? Colors.orange.shade50 : AppTheme.primaryLight,
                                      child: Text(
                                        '#${sale.id}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isDebt ? Colors.orange.shade900 : AppTheme.primaryDark,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                'Sale #${sale.id}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              ),
                                              const SizedBox(width: 6),
                                              if (isDebt)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange.shade100,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    'Utang • ${sale.customerName ?? 'Customer'}',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.orange.shade900,
                                                    ),
                                                  ),
                                                )
                                              else
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.primaryLight,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Text(
                                                    'Cash',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppTheme.primaryDark,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${_formatTimestamp(sale.timestamp)} • ${sale.itemCount} ${sale.itemCount == 1 ? 'item' : 'items'}',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          sale.formattedTotal,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: AppTheme.primaryDark,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'View Receipt',
                                          style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right, size: 20, color: AppTheme.textMuted),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, IconData icon) {
    final isSelected = _activeDateFilter == value;
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 14,
        color: isSelected ? Colors.white : AppTheme.textMuted,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : AppTheme.textDark,
        ),
      ),
      backgroundColor: Colors.grey.shade100,
      selectedColor: AppTheme.primaryGreen,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      onSelected: (_) {
        setState(() {
          _activeDateFilter = value;
          _customDateRange = null;
        });
        _applyFilters();
      },
    );
  }

  Widget _buildCustomDateChip() {
    final isCustom = _activeDateFilter == 'custom' && _customDateRange != null;
    final label = isCustom
        ? '${DateFormat('MMM d').format(_customDateRange!.start)} - ${DateFormat('MMM d').format(_customDateRange!.end)}'
        : 'Custom Range...';

    return FilterChip(
      selected: isCustom,
      showCheckmark: false,
      avatar: Icon(
        Icons.calendar_month,
        size: 14,
        color: isCustom ? Colors.white : AppTheme.textMuted,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isCustom ? FontWeight.bold : FontWeight.normal,
          color: isCustom ? Colors.white : AppTheme.textDark,
        ),
      ),
      backgroundColor: Colors.grey.shade100,
      selectedColor: AppTheme.primaryDark,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      onSelected: (_) => _pickCustomDateRange(),
    );
  }

  String _formatTimestamp(String timestamp) {
    if (timestamp.isEmpty) return '';
    try {
      final dt = DateTime.parse(timestamp);
      return DateFormat('MMM d, yyyy • h:mm a').format(dt);
    } catch (_) {
      return timestamp.split('T').first;
    }
  }
}
