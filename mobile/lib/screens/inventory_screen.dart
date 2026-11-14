import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialogs.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _products = [];
  List<Product> _filtered = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final api = context.read<ApiService>();
      final products = await api.getProducts();
      setState(() {
        _products = products;
        _filterProducts(_searchController.text);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load products: $e'), backgroundColor: AppTheme.dangerRed),
        );
      }
    }
  }

  void _filterProducts(String query) {
    if (query.trim().isEmpty) {
      setState(() => _filtered = _products);
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _filtered = _products.where((p) {
        return p.name.toLowerCase().contains(q) ||
            p.barcodeString.toLowerCase().contains(q);
      }).toList();
    });
  }

  Future<void> _showAdjustStockDialog(Product product) async {
    final deltaController = TextEditingController();
    final reasonController = TextEditingController();
    bool isAddition = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Adjust Stock · ${product.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Stock: ${product.stock != null ? '${product.stock} units' : 'Untracked'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Add Stock (+)'),
                          selected: isAddition,
                          selectedColor: AppTheme.primaryLight,
                          onSelected: (val) => setState(() => isAddition = true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Remove Stock (-)'),
                          selected: !isAddition,
                          selectedColor: AppTheme.dangerLight,
                          onSelected: (val) => setState(() => isAddition = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: deltaController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Quantity Units',
                      prefixIcon: Icon(isAddition ? Icons.add : Icons.remove),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Adjustment',
                      hintText: 'e.g. Delivery restock, damaged item',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final qty = int.tryParse(deltaController.text.trim());
                    final reason = reasonController.text.trim();
                    if (qty == null || qty <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid positive quantity')),
                      );
                      return;
                    }
                    if (reason.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Reason is required')),
                      );
                      return;
                    }

                    final delta = isAddition ? qty : -qty;
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(ctx);
                    try {
                      final api = context.read<ApiService>();
                      await api.adjustStock(product.id, delta, reason);
                      navigator.pop(true);
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Adjustment failed: $e'), backgroundColor: AppTheme.dangerRed),
                      );
                    }
                  },
                  child: const Text('Save Adjustment'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      _loadProducts();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stock for "${product.name}" updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadProducts,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search products by name or barcode...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _filterProducts('');
                        },
                      )
                    : null,
              ),
              onChanged: _filterProducts,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            const Text('No products found', style: TextStyle(color: AppTheme.textMuted)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final product = _filtered[index];
                          final hasStock = product.stock != null;
                          final isLow = product.isLowStock;

                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                AppDialogs.showStockHistoryDialog(context, product, api);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            product.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Barcode: ${product.barcodeString}',
                                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            product.formattedPrice,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: AppTheme.primaryGreen,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isLow
                                                ? AppTheme.dangerLight
                                                : (hasStock ? AppTheme.primaryLight : Colors.grey.shade100),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            hasStock ? '${product.stock} in stock' : 'Untracked',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isLow
                                                  ? AppTheme.dangerRed
                                                  : (hasStock ? AppTheme.primaryDark : AppTheme.textMuted),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          icon: const Icon(Icons.tune, size: 14),
                                          label: const Text('Adjust', style: TextStyle(fontSize: 12)),
                                          onPressed: () => _showAdjustStockDialog(product),
                                        ),
                                      ],
                                    ),
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
}
