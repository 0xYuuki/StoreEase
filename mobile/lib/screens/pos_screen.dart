import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/cart_provider.dart';
import '../providers/debt_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialogs.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _tenderedController = TextEditingController();
  bool _showScanner = false;
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DebtProvider>().loadDebts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tenderedController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final api = context.read<ApiService>();
      final products = await api.getProducts();
      if (mounted) {
        setState(() {
          _allProducts = products;
          _filteredProducts = products;
        });
      }
    } catch (_) {}
  }

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() => _filteredProducts = _allProducts);
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        return p.name.toLowerCase().contains(q) ||
            p.barcodeString.toLowerCase().contains(q);
      }).toList();
    });
  }

  void _onBarcodeScanned(String barcode) {
    final clean = barcode.trim();
    if (clean.isEmpty) return;

    final product = _allProducts.firstWhere(
      (p) => p.barcodeString == clean,
      orElse: () => Product(id: 0, barcodeString: '', name: '', priceCentavos: 0),
    );

    if (product.id != 0) {
      context.read<CartProvider>().addProduct(product);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${product.name} to cart'),
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No product found for barcode: $clean'),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
    }
  }

  Future<void> _handleCompleteSale() async {
    final cart = context.read<CartProvider>();
    final debtProv = context.read<DebtProvider>();

    if (cart.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty. Add items first.')),
      );
      return;
    }

    final tenderedText = _tenderedController.text.trim();
    final tenderedPesos = double.tryParse(tenderedText) ?? 0.0;
    final tenderedCentavos = (tenderedPesos * 100).round();

    // Shortage check:
    if (tenderedCentavos < cart.totalCentavos) {
      final result = await AppDialogs.showShortageDialog(
        context: context,
        totalCentavos: cart.totalCentavos,
        tenderedCentavos: tenderedCentavos,
        debtors: debtProv.allDebtors,
      );

      if (result == null) return; // User cancelled

      try {
        final receipt = await cart.checkout(
          tenderedAmountCentavos: tenderedCentavos,
          debtorId: result.debtorId,
          newDebtorName: result.newDebtorName,
        );
        if (receipt != null && mounted) {
          _tenderedController.clear();
          debtProv.loadDebts();
          await AppDialogs.showReceiptDialog(context, receipt);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Checkout failed: $e'), backgroundColor: AppTheme.dangerRed),
          );
        }
      }
    } else {
      // Full cash payment
      try {
        final receipt = await cart.checkout(
          tenderedAmountCentavos: tenderedCentavos,
        );
        if (receipt != null && mounted) {
          _tenderedController.clear();
          await AppDialogs.showReceiptDialog(context, receipt);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Checkout failed: $e'), backgroundColor: AppTheme.dangerRed),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              height: 32,
              errorBuilder: (_, _, _) => const Icon(Icons.store, color: AppTheme.primaryGreen),
            ),
            const SizedBox(width: 8),
            const Text("Helen's Store POS"),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showScanner ? Icons.camera_alt : Icons.camera_alt_outlined),
            color: _showScanner ? AppTheme.primaryGreen : AppTheme.textDark,
            tooltip: 'Barcode Scanner',
            onPressed: () => setState(() => _showScanner = !_showScanner),
          ),
          if (cart.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear Cart',
              onPressed: () => cart.clear(),
            ),
        ],
      ),
      body: Column(
        children: [
          // Camera Barcode Scanner View (collapsible)
          if (_showScanner)
            Container(
              height: 200,
              color: Colors.black,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    onDetect: (capture) {
                      final barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                        _onBarcodeScanned(barcodes.first.rawValue!);
                      }
                    },
                  ),
                  Container(
                    width: 220,
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.accentGreen, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Point camera at product barcode',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search product or barcode...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // Instant Product Add Chips (if searching)
          if (_searchController.text.isNotEmpty && _filteredProducts.isNotEmpty)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filteredProducts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final p = _filteredProducts[index];
                  return ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text('${p.name} (${p.formattedPrice})'),
                    onPressed: () => cart.addProduct(p),
                  );
                },
              ),
            ),

          // Cart Items List
          Expanded(
            child: cart.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'Cart is empty',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Scan a barcode or search products to begin',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.product.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.product.formattedPrice} each',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 22),
                                    color: AppTheme.dangerRed,
                                    onPressed: () => cart.decrementQuantity(item.product.id),
                                  ),
                                  Text(
                                    '${item.quantity}',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 22),
                                    color: AppTheme.primaryGreen,
                                    onPressed: () => cart.incrementQuantity(item.product.id),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                item.formattedLineTotal,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Checkout Bottom Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppTheme.cardBorder)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  offset: const Offset(0, -2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total (${cart.itemCount} items):',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        cart.formattedTotal,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tenderedController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Cash Tendered',
                            prefixText: '₱ ',
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Quick exact cash button
                      OutlinedButton(
                        onPressed: cart.items.isEmpty
                            ? null
                            : () {
                                _tenderedController.text = cart.totalPesos.toStringAsFixed(2);
                              },
                        child: const Text('Exact'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: cart.items.isEmpty || cart.isLoading
                          ? null
                          : _handleCompleteSale,
                      child: cart.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Complete Sale', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
