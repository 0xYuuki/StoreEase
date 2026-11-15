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

                          // --- 2. Sales Trend Chart (Last 7 Days) ---
                          _buildSalesTrendCard(data.chartData),

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

  Widget _buildSalesTrendCard(ChartData chart) {
    final maxCentavos = chart.data.isEmpty ? 0 : chart.data.reduce(max);
    final total7DaysCentavos = chart.data.fold<int>(0, (sum, val) => sum + val);
    final total7DaysPesos = total7DaysCentavos / 100.0;
    final average7DaysPesos = total7DaysPesos / 7.0;

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
                const Row(
                  children: [
                    Icon(Icons.show_chart, color: AppTheme.primaryGreen, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Sales Trend (Last 7 Days)',
                      style: TextStyle(
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
                    'Total: ₱${total7DaysPesos.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Bar Chart Area
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(chart.labels.length, (index) {
                  final label = chart.labels[index];
                  final centavos = chart.data[index];
                  final pesos = centavos / 100.0;
                  final isToday = index == chart.labels.length - 1;

                  // Parse label date for short day display (e.g. "Mon" or "15")
                  final parsedDate = DateTime.tryParse(label);
                  final dayLabel = isToday
                      ? 'Today'
                      : (parsedDate != null ? _shortWeekday(parsedDate.weekday) : label.split('-').last);

                  // Calculate ratio: minimum height 6px so 0 is still visible as a notch
                  final ratio = maxCentavos > 0 ? (centavos / maxCentavos) : 0.0;
                  final barHeight = max(6.0, ratio * 105.0);

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
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
                                  color: isToday ? AppTheme.primaryDark : AppTheme.textMuted,
                                ),
                              ),
                            )
                          else
                            const SizedBox(height: 12),
                          const SizedBox(height: 4),
                          Container(
                            height: barHeight,
                            decoration: BoxDecoration(
                              color: isToday
                                  ? AppTheme.primaryGreen
                                  : (centavos > 0 ? AppTheme.accentGreen.withValues(alpha: 0.6) : Colors.grey.shade300),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                              border: isToday
                                  ? Border.all(color: AppTheme.primaryDark, width: 1.5)
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            dayLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                              color: isToday ? AppTheme.primaryDark : AppTheme.textMuted,
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
                  'Daily Average: ₱${average7DaysPesos.toStringAsFixed(2)}',
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
