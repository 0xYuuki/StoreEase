import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/analytics_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../providers/sales_provider.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialogs.dart';

class PosScreen extends StatefulWidget {
  final bool isActive;
  const PosScreen({super.key, this.isActive = true});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _tenderedController = TextEditingController();
  bool _showScanner = false;

  // Barcode scan throttling & interval control
  DateTime? _lastScanTime;
  bool _isScanCooldown = false;
  String? _lastScannedProductName;
  static const Duration _scanCooldown = Duration(milliseconds: 1500); // 1.5 second interval to ensure 1 count per scan

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().loadProducts();
      context.read<DebtProvider>().loadDebts();
    });
  }

  @override
  void didUpdateWidget(covariant PosScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      // User navigated away from the POS tab - shut down camera immediately
      if (_showScanner) {
        setState(() {
          _showScanner = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App minimized or screen locked - turn off scanner
      if (_showScanner) {
        setState(() {
          _showScanner = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _tenderedController.dispose();
    super.dispose();
  }

  void _handleBarcodeDetect(String rawBarcode) {
    // Strict guard: do not process scans if tab is inactive or scanner is closed
    if (!widget.isActive || !_showScanner) return;

    final clean = rawBarcode.trim();
    if (clean.isEmpty) return;

    final now = DateTime.now();
    // Enforce 1.5s interval to ensure each physical scan counts as exactly 1 item
    if (_lastScanTime != null && now.difference(_lastScanTime!) < _scanCooldown) {
      return;
    }
    _lastScanTime = now;

    _onBarcodeScanned(clean);
  }

  Future<void> _addProductToCart(Product product) async {
    final cart = context.read<CartProvider>();
    if (product.isWeighted) {
      final selectedWeight = await AppDialogs.showWeightEntryDialog(
        context: context,
        product: product,
      );
      if (selectedWeight != null && selectedWeight > 0) {
        cart.addProduct(product, weight: selectedWeight);
        await AudioService.playScanBeep();
        if (mounted) {
          final wStr = selectedWeight % 1 == 0 ? selectedWeight.toInt().toString() : selectedWeight.toStringAsFixed(2);
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Added $wStr ${product.unit} of ${product.name} to cart'),
                  ),
                ],
              ),
              backgroundColor: AppTheme.primaryDark,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } else {
      cart.addProduct(product);
      await AudioService.playScanBeep();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Added: ${product.name} (+1 in cart)')),
              ],
            ),
            backgroundColor: AppTheme.primaryDark,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future<void> _onBarcodeScanned(String clean) async {
    final productProv = context.read<ProductProvider>();
    final product = await productProv.lookupBarcode(clean);

    if (!mounted) return;

    if (product != null) {
      if (mounted) {
        setState(() {
          _isScanCooldown = true;
          _lastScannedProductName = product.name;
        });

        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) {
            setState(() {
              _isScanCooldown = false;
            });
          }
        });
      }

      await _addProductToCart(product);
    } else {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No product found for barcode: $clean'),
          backgroundColor: AppTheme.dangerRed,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleCompleteSale() async {
    final cart = context.read<CartProvider>();
    final debtProv = context.read<DebtProvider>();
    final productProv = context.read<ProductProvider>();

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
          if (_showScanner) {
            setState(() => _showScanner = false);
          }
          _tenderedController.clear();
          debtProv.loadDebts();
          productProv.loadProducts();
          context.read<SalesProvider>().loadSales();
          context.read<AnalyticsProvider>().loadAnalytics();
          await AppDialogs.showReceiptDialog(context, receipt);
          if (mounted) {
            context.read<SalesProvider>().loadSales();
            context.read<AnalyticsProvider>().loadAnalytics();
          }
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
          if (_showScanner) {
            setState(() => _showScanner = false);
          }
          _tenderedController.clear();
          productProv.loadProducts();
          context.read<SalesProvider>().loadSales();
          context.read<AnalyticsProvider>().loadAnalytics();
          await AppDialogs.showReceiptDialog(context, receipt);
          if (mounted) {
            context.read<SalesProvider>().loadSales();
            context.read<AnalyticsProvider>().loadAnalytics();
          }
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
    final productProv = context.watch<ProductProvider>();
    final allProducts = productProv.products;

    final query = _searchController.text.trim().toLowerCase();
    final filteredProducts = query.isEmpty
        ? <Product>[]
        : allProducts.where((p) {
            final name = p.name.trim().toLowerCase();
            final barcode = p.barcodeString.trim().toLowerCase();
            return name.startsWith(query) || barcode.startsWith(query);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logo.png',
              height: 32,
              errorBuilder: (_, _, _) => const Icon(Icons.store, color: AppTheme.primaryGreen),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                "Helen's Store",
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Products',
            onPressed: () => context.read<ProductProvider>().loadProducts(),
          ),
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
          if (_showScanner && widget.isActive)
            Container(
              height: 170,
              color: Colors.black,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    onDetect: (capture) {
                      final barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                        _handleBarcodeDetect(barcodes.first.rawValue!);
                      }
                    },
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 220,
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _isScanCooldown ? Colors.greenAccent : AppTheme.accentGreen,
                        width: _isScanCooldown ? 4 : 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      color: _isScanCooldown ? Colors.green.withValues(alpha: 0.15) : Colors.transparent,
                    ),
                    child: _isScanCooldown
                        ? const Center(
                            child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 40),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _isScanCooldown ? AppTheme.primaryDark : Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _isScanCooldown && _lastScannedProductName != null
                            ? '✓ Scanned: $_lastScannedProductName (+1)'
                            : 'Point camera at product barcode',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Vertical Search Preview List (Up/Down)
          if (_searchController.text.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Material(
                color: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.accentGreen, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: filteredProducts.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off, size: 20, color: Colors.grey.shade400),
                            const SizedBox(width: 8),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No products starting with "${_searchController.text}"'
                                  : 'No products in this filter',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: filteredProducts.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final p = filteredProducts[index];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: p.isWeighted
                                  ? Colors.indigo.shade50
                                  : (p.isBarcodeless ? Colors.amber.shade50 : AppTheme.primaryLight),
                              child: Icon(
                                p.isWeighted
                                    ? Icons.scale_outlined
                                    : (p.isBarcodeless ? Icons.label_outline : Icons.inventory_2_outlined),
                                size: 16,
                                color: p.isWeighted
                                    ? Colors.indigo
                                    : (p.isBarcodeless ? Colors.brown : AppTheme.primaryGreen),
                              ),
                            ),
                            title: Text(
                              p.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: Text(
                              '${p.isBarcodeless ? 'PLU: ' : 'Barcode: '}${p.barcodeString}${p.stock != null ? ' • Stock: ${p.formattedStock}' : ''}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(p.formattedPrice, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryDark)),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: Icon(p.isWeighted ? Icons.scale_outlined : Icons.add_circle, color: AppTheme.primaryGreen, size: 24),
                                  tooltip: p.isWeighted ? 'Weigh Item' : 'Add to Cart',
                                  onPressed: () => _addProductToCart(p),
                                ),
                              ],
                            ),
                            onTap: () => _addProductToCart(p),
                          );
                        },
                      ),
              ),
            ),

          // Cart Items List
          Expanded(
            child: cart.items.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.point_of_sale_outlined, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          const Text(
                            'Your cart is empty',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Scan barcode or search products above to start sale',
                            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.product.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.isWeighted
                                          ? '${item.product.formattedPrice} • ${item.formattedQuantityOrWeight}'
                                          : '${item.product.formattedPrice} each',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 22),
                                    color: AppTheme.textMuted,
                                    tooltip: item.isWeighted ? 'Less 1/4 kg' : 'Decrease',
                                    onPressed: () => cart.decrementQuantity(item.product.id),
                                  ),
                                  if (item.isWeighted)
                                    InkWell(
                                      onTap: () async {
                                        final newWeight = await AppDialogs.showWeightEntryDialog(
                                          context: context,
                                          product: item.product,
                                          initialWeight: item.weight,
                                        );
                                        if (newWeight != null && newWeight > 0) {
                                          cart.updateWeight(item.product.id, newWeight);
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryLight,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppTheme.accentGreen),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              item.formattedQuantityOrWeight,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryDark),
                                            ),
                                            const SizedBox(width: 2),
                                            const Icon(Icons.edit, size: 12, color: AppTheme.primaryDark),
                                          ],
                                        ),
                                      ),
                                    )
                                  else
                                    Text(
                                      '${item.quantity}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 22),
                                    color: AppTheme.primaryGreen,
                                    tooltip: item.isWeighted ? 'Add 1/4 kg' : 'Increase',
                                    onPressed: () => cart.incrementQuantity(item.product.id),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  item.formattedLineTotal,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Checkout Bottom Dock
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  offset: const Offset(0, -3),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL (${cart.itemCount} items)',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                    ),
                    Text(
                      cart.formattedTotal,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _tenderedController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Cash Tendered (₱)',
                          hintText: '0.00',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: cart.totalCentavos > 0
                            ? () {
                                _tenderedController.text = (cart.totalCentavos / 100.0).toStringAsFixed(2);
                              }
                            : null,
                        child: const Text('Exact'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: cart.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline, color: Colors.white),
                    label: Text(
                      cart.isLoading ? 'Processing...' : 'Complete Sale',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: (cart.items.isEmpty || cart.isLoading)
                        ? null
                        : _handleCompleteSale,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
