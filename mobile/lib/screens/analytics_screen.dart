import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/analytics_provider.dart';
import '../theme/app_theme.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnalyticsProvider>().loadAnalytics();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AnalyticsProvider>();
    final data = prov.data;
    final isLoading = prov.isLoading;
    final errorMessage = prov.errorMessage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Analytics',
            onPressed: () => context.read<AnalyticsProvider>().loadAnalytics(),
          ),
        ],
      ),
      body: isLoading && data == null
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null && data == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppTheme.dangerRed),
                        const SizedBox(height: 12),
                        Text(
                          'Failed to load analytics: $errorMessage',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.dangerRed),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => context.read<AnalyticsProvider>().loadAnalytics(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => context.read<AnalyticsProvider>().loadAnalytics(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (data != null) ...[
                          // --- 1. KPI Grid (2x2) ---
                          _buildKpiGrid(data.kpis),

                          const SizedBox(height: 20),

                          // --- 2. Sales Trend Chart (Days, Week, Months, Year) ---
                          _buildSalesTrendCard(data.chartData, prov.trendPeriod),

                          const SizedBox(height: 20),

                          // --- 3. Most Popular Items (Top 5) ---
                          _buildPopularItemsCard(data.popularItems),
                          
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildKpiGrid(AnalyticsKpis kpis) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview & Revenue',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                title: "Today's Sales",
                value: kpis.formattedToday,
                subtext: 'Real-time daily total',
                icon: Icons.today,
                accentColor: AppTheme.primaryGreen,
                isHighlight: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                title: 'This Week',
                value: kpis.formattedWeek,
                subtext: 'Starting Sunday',
                icon: Icons.date_range,
                accentColor: Colors.blueAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                title: 'This Month',
                value: kpis.formattedMonth,
                subtext: 'Calendar month',
                icon: Icons.calendar_month,
                accentColor: Colors.deepPurpleAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                title: 'This Year',
                value: kpis.formattedYear,
                subtext: 'Annual total',
                icon: Icons.timeline,
                accentColor: Colors.teal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required Color accentColor,
    bool isHighlight = false,
  }) {
    return Card(
      elevation: isHighlight ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isHighlight
            ? const BorderSide(color: AppTheme.accentGreen, width: 1.5)
            : BorderSide(color: Colors.grey.shade200),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: isHighlight
              ? LinearGradient(
                  colors: [AppTheme.primaryLight.withValues(alpha: 0.35), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(icon, size: 18, color: accentColor),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isHighlight ? AppTheme.primaryDark : AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtext,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesTrendCard(ChartData chart, SalesTrendPeriod period) {
    final maxCentavos = chart.peakCentavos;
    final totalCentavos = chart.totalCentavos;
    final totalPesos = totalCentavos / 100.0;
    final averagePesos = chart.averagePesos;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.show_chart, color: AppTheme.primaryGreen, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _trendPeriodTitle(period),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Total: ₱${totalPesos.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Period Selection Tabs: Days | Week | Months | Year
            _buildPeriodSelector(period),

            const SizedBox(height: 16),

            // Bar Chart Area
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(chart.labels.length, (index) {
                  final label = chart.labels[index];
                  final centavos = chart.data[index];
                  final pesos = centavos / 100.0;
                  final isCurrent = index == chart.labels.length - 1;

                  final dayLabel = _formatBucketLabel(label, period, isCurrent);

                  // Calculate ratio: minimum height 6px so 0 is still visible as a notch
                  final ratio = maxCentavos > 0 ? (centavos / maxCentavos) : 0.0;
                  final barHeight = max(6.0, ratio * 105.0);

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (pesos > 0)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '₱${pesos >= 1000 ? '${(pesos / 1000).toStringAsFixed(1)}k' : pesos.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isCurrent ? AppTheme.primaryDark : AppTheme.textMuted,
                                ),
                              ),
                            )
                          else
                            const SizedBox(height: 12),
                          const SizedBox(height: 4),
                          Container(
                            height: barHeight,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? AppTheme.primaryGreen
                                  : (centavos > 0 ? AppTheme.accentGreen.withValues(alpha: 0.6) : Colors.grey.shade300),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                              border: isCurrent
                                  ? Border.all(color: AppTheme.primaryDark, width: 1.5)
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              dayLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                color: isCurrent ? AppTheme.primaryDark : AppTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _trendAverageLabel(period, averagePesos),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                Text(
                  'Peak: ₱${(maxCentavos / 100.0).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector(SalesTrendPeriod currentPeriod) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // Slate 100
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _buildPeriodTab(label: 'Days', period: SalesTrendPeriod.days, current: currentPeriod),
          _buildPeriodTab(label: 'Week', period: SalesTrendPeriod.week, current: currentPeriod),
          _buildPeriodTab(label: 'Months', period: SalesTrendPeriod.months, current: currentPeriod),
          _buildPeriodTab(label: 'Year', period: SalesTrendPeriod.year, current: currentPeriod),
        ],
      ),
    );
  }

  Widget _buildPeriodTab({
    required String label,
    required SalesTrendPeriod period,
    required SalesTrendPeriod current,
  }) {
    final isSelected = period == current;
    return Expanded(
      child: GestureDetector(
        key: Key('trend_period_$label'),
        onTap: () => context.read<AnalyticsProvider>().setTrendPeriod(period),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? AppTheme.primaryDark : AppTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  String _trendPeriodTitle(SalesTrendPeriod period) {
    switch (period) {
      case SalesTrendPeriod.days:
        return 'Sales Trend (Days)';
      case SalesTrendPeriod.week:
        return 'Sales Trend (Week)';
      case SalesTrendPeriod.months:
        return 'Sales Trend (Months)';
      case SalesTrendPeriod.year:
        return 'Sales Trend (Year)';
    }
  }

  String _trendAverageLabel(SalesTrendPeriod period, double averagePesos) {
    switch (period) {
      case SalesTrendPeriod.days:
        return 'Daily Average: ₱${averagePesos.toStringAsFixed(2)}';
      case SalesTrendPeriod.week:
        return 'Weekly Average: ₱${averagePesos.toStringAsFixed(2)}';
      case SalesTrendPeriod.months:
        return 'Monthly Average: ₱${averagePesos.toStringAsFixed(2)}';
      case SalesTrendPeriod.year:
        return 'Annual Average: ₱${averagePesos.toStringAsFixed(2)}';
    }
  }

  String _formatBucketLabel(String label, SalesTrendPeriod period, bool isCurrent) {
    switch (period) {
      case SalesTrendPeriod.days:
        if (isCurrent) return 'Today';
        final parsedDate = DateTime.tryParse(label);
        return parsedDate != null ? _shortWeekday(parsedDate.weekday) : label.split('-').last;
      case SalesTrendPeriod.week:
        return isCurrent ? 'This Wk' : label;
      case SalesTrendPeriod.months:
        return isCurrent ? 'This Mo' : label;
      case SalesTrendPeriod.year:
        return isCurrent ? 'This Yr' : label;
    }
  }

  Widget _buildPopularItemsCard(List<PopularItem> items) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Text(
                  'Most Popular Items (Top 5)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.insights_outlined, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      const Text(
                        'No sales recorded yet',
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Complete sales in POS to populate top products.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final rank = index + 1;

                  final Color badgeColor;
                  final Color badgeTextColor;
                  if (rank == 1) {
                    badgeColor = Colors.amber.shade100;
                    badgeTextColor = Colors.amber.shade900;
                  } else if (rank == 2) {
                    badgeColor = Colors.blueGrey.shade100;
                    badgeTextColor = Colors.blueGrey.shade800;
                  } else if (rank == 3) {
                    badgeColor = Colors.brown.shade100;
                    badgeTextColor = Colors.brown.shade800;
                  } else {
                    badgeColor = Colors.grey.shade100;
                    badgeTextColor = Colors.grey.shade700;
                  }

                  return Row(
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: badgeColor,
                        child: Text(
                          '#$rank',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: badgeTextColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${item.timesSold} ${item.timesSold == 1 ? 'unit' : 'units'} sold',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.formattedRevenue,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _shortWeekday(int weekday) {
    switch (weekday) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return '';
    }
  }
}
