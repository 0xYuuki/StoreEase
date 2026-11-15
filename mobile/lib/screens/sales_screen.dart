import 'package:flutter/material.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesProvider>().loadSales();
    });
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

  @override
  Widget build(BuildContext context) {
    final salesProv = context.watch<SalesProvider>();
    final sales = salesProv.sales;
    final isLoading = salesProv.isLoading;
    final hasMore = salesProv.hasMore;
    final page = salesProv.page;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => context.read<SalesProvider>().loadSales(page: 1),
          ),
        ],
      ),
      body: isLoading && sales.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : sales.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 10),
                      const Text('No sales records found', style: TextStyle(color: AppTheme.textMuted)),
                    ],
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
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _viewReceipt(sale.id),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppTheme.primaryLight,
                                child: Text(
                                  '#${sale.id}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryDark,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sale #${sale.id}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      sale.timestamp.split('T').first,
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
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
                                      color: AppTheme.primaryGreen,
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
    );
  }
}
