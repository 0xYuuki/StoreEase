import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/product_provider.dart';
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
  String _selectedCategory = 'All';
  bool _filterLowStockOnly = false;

  static const List<String> _standardCategories = [
    'Beverages',
    'Canned Goods',
    'Instant Noodles & Snacks',
    'Condiments & Cooking',
    'Fresh & Grocery',
    'Frozen & Meat',
    'Household & Personal Care',
    'General',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().loadProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _showCustomCategoryDialog(BuildContext context) async {
    final catController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.add_circle_outline, color: AppTheme.primaryGreen),
              SizedBox(width: 8),
              Text('New Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: TextField(
            controller: catController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Category Name',
              hintText: 'e.g. Bakery, Spices, Dairy...',
              prefixIcon: Icon(Icons.category_outlined),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
              onPressed: () {
                final text = catController.text.trim();
                if (text.isNotEmpty) {
                  Navigator.of(ctx).pop(text);
                }
              },
              child: const Text('Add Category', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddProductDialog() async {
    final barcodeController = TextEditingController();
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final stockController = TextEditingController();
    final reorderController = TextEditingController();
    final List<String> availableCategories = List.from(_standardCategories);
    String selectedCategory = 'General';
    String pricingType = 'unit'; // 'unit' or 'weight'
    String unit = 'pc';

    String generateRandomBarcode() {
      final random = Random();
      String code = '';
      for (int i = 0; i < 12; i++) {
        code += random.nextInt(10).toString();
      }
      return code;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.add_shopping_cart, color: AppTheme.primaryGreen),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Add New Product', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: barcodeController,
                        decoration: InputDecoration(
                          labelText: 'Barcode (Optional)',
                          hintText: 'Leave empty for loose / no barcode',
                          prefixIcon: const Icon(Icons.qr_code),
                          helperText: 'Auto-generates PLU code if left blank',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.casino_outlined),
                            tooltip: 'Generate Random Barcode',
                            onPressed: () {
                              setDialogState(() {
                                barcodeController.text = generateRandomBarcode();
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Product Name',
                          hintText: 'e.g. Orange Juice, Potato Chips...',
                          prefixIcon: Icon(Icons.label_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(selectedCategory),
                        initialValue: selectedCategory,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        selectedItemBuilder: (BuildContext context) {
                          return [
                            ...availableCategories.map((c) => Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    c,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                )),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '+ Custom Category...',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ];
                        },
                        items: [
                          ...availableCategories.map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                c,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                          const DropdownMenuItem(
                            value: '__custom__',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add, size: 16, color: AppTheme.primaryGreen),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '+ Custom Category...',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (val) async {
                          if (val == '__custom__') {
                            final customName = await _showCustomCategoryDialog(context);
                            if (customName != null && customName.isNotEmpty) {
                              setDialogState(() {
                                if (!availableCategories.contains(customName)) {
                                  availableCategories.add(customName);
                                }
                                selectedCategory = customName;
                              });
                            } else {
                              setDialogState(() {});
                            }
                          } else if (val != null) {
                            setDialogState(() {
                              selectedCategory = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // Pricing Type Selector (By Piece vs By Weight)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(3),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    pricingType = 'unit';
                                    unit = 'pc';
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: pricingType == 'unit' ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: pricingType == 'unit'
                                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '📦 By Piece (pc)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: pricingType == 'unit' ? AppTheme.primaryDark : AppTheme.textMuted,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    pricingType = 'weight';
                                    unit = 'kg';
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: pricingType == 'weight' ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: pricingType == 'weight'
                                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '⚖️ By Weight (kg)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: pricingType == 'weight' ? AppTheme.primaryDark : AppTheme.textMuted,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: pricingType == 'weight' ? 'Price per kg (₱)' : 'Price per piece (₱)',
                          hintText: '0.00',
                          prefixText: '₱ ',
                          prefixIcon: const Icon(Icons.payments_outlined),
                          suffixText: pricingType == 'weight' ? '/ kg' : '/ pc',
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Initial Stock Field (Full width to avoid text truncation)
                      TextField(
                        controller: stockController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: pricingType == 'weight' ? 'Initial Stock (in kg)' : 'Initial Stock (in pieces)',
                          hintText: 'e.g. 50 (Optional)',
                          prefixIcon: const Icon(Icons.inventory_2_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Low Stock Alert Level Field (Full width to avoid text truncation)
                      TextField(
                        controller: reorderController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: pricingType == 'weight' ? 'Low Stock Alert Level (in kg)' : 'Low Stock Alert Level (in pieces)',
                          hintText: 'e.g. 10 (Optional)',
                          prefixIcon: const Icon(Icons.warning_amber_outlined),
                          helperText: 'Alerts you when stock drops below this number',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
                  onPressed: () async {
                    final barcode = barcodeController.text.trim();
                    final isBarcodeless = barcode.isEmpty;
                    final name = nameController.text.trim();
                    final priceText = priceController.text.trim();

                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a product name'), backgroundColor: AppTheme.dangerRed),
                      );
                      return;
                    }
                    final pricePesos = double.tryParse(priceText);
                    if (pricePesos == null || pricePesos < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid price'), backgroundColor: AppTheme.dangerRed),
                      );
                      return;
                    }

                    final priceCentavos = (pricePesos * 100).round();
                    final initialStock = stockController.text.trim().isNotEmpty
                        ? double.tryParse(stockController.text.trim())
                        : null;
                    final reorderLevel = reorderController.text.trim().isNotEmpty
                        ? double.tryParse(reorderController.text.trim())
                        : null;

                    final finalCategory = selectedCategory.trim().isEmpty ? 'General' : selectedCategory.trim();

                    final productProv = context.read<ProductProvider>();
                    final messenger = ScaffoldMessenger.of(context);
                    final nav = Navigator.of(ctx);

                    try {
                      await productProv.createProduct(
                        barcodeString: isBarcodeless ? null : barcode,
                        name: name,
                        priceCentavos: priceCentavos,
                        initialStock: initialStock,
                        reorderLevel: reorderLevel,
                        category: finalCategory,
                        pricingType: pricingType,
                        unit: unit,
                        isBarcodeless: isBarcodeless,
                      );
                      nav.pop(true);
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Failed to add product: $e'), backgroundColor: AppTheme.dangerRed),
                      );
                    }
                  },
                  child: const Text('Save Product', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Product "${nameController.text.trim()}" added successfully!')),
      );
    }
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
                    'Current Stock: ${product.stock != null ? product.formattedStock : 'Untracked'}',
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
                          label: const Text('Deduct Stock (-)'),
                          selected: !isAddition,
                          selectedColor: AppTheme.dangerLight,
                          onSelected: (val) => setState(() => isAddition = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: deltaController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Quantity to ${isAddition ? 'Add' : 'Deduct'} (${product.isWeighted ? product.unit : 'pcs'})',
                      prefixIcon: Icon(isAddition ? Icons.add_circle_outline : Icons.remove_circle_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Adjustment',
                      hintText: 'e.g. Delivery, Spoiled, Inventory Count...',
                      prefixIcon: Icon(Icons.edit_note),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAddition ? AppTheme.primaryGreen : AppTheme.dangerRed,
                  ),
                  onPressed: () async {
                    final qty = double.tryParse(deltaController.text.trim()) ?? 0;
                    if (qty <= 0) return;

                    final reason = reasonController.text.trim().isNotEmpty
                        ? reasonController.text.trim()
                        : (isAddition ? 'Stock In' : 'Stock Out');

                    final delta = isAddition ? qty : -qty;
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(ctx);
                    try {
                      final productProv = context.read<ProductProvider>();
                      await productProv.adjustStock(product.id, delta, reason);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stock for "${product.name}" updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiService>();
    final productProv = context.watch<ProductProvider>();
    final allProducts = productProv.products;
    final isLoading = productProv.isLoading;

    final query = _searchController.text.trim().toLowerCase();
    final matchingSearch = allProducts.where((p) {
      if (_filterLowStockOnly && !p.isLowStock) return false;
      if (query.isEmpty) return true;
      final name = p.name.trim().toLowerCase();
      final barcode = p.barcodeString.trim().toLowerCase();
      return name.startsWith(query) || barcode.startsWith(query);
    }).toList();

    // Distinct categories present in inventory
    final Set<String> categoriesSet = {};
    for (final p in allProducts) {
      final cat = p.category.trim();
      if (cat.isNotEmpty) {
        categoriesSet.add(cat);
      }
    }
    final sortedCategories = categoriesSet.toList()..sort();

    // Build category sections
    final List<_CategorySection> displayedSections = [];
    if (_selectedCategory == 'All') {
      for (final cat in sortedCategories) {
        final items = matchingSearch
            .where((p) => p.category.trim().toLowerCase() == cat.toLowerCase())
            .toList();
        if (items.isNotEmpty) {
          displayedSections.add(_CategorySection(category: cat, products: items));
        }
      }
    } else {
      final items = matchingSearch
          .where((p) => p.category.trim().toLowerCase() == _selectedCategory.toLowerCase())
          .toList();
      if (items.isNotEmpty) {
        displayedSections.add(_CategorySection(category: _selectedCategory, products: items));
      }
    }

    final hasActiveFilter = query.isNotEmpty || _selectedCategory != 'All' || _filterLowStockOnly;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Management'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: productProv.lowStockCount > 0,
              label: Text('${productProv.lowStockCount}'),
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: 'Stock Alerts & Reorder',
            onPressed: () => AppDialogs.showStockAlertsModal(context),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Product',
            onPressed: _showAddProductDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => context.read<ProductProvider>().loadProducts(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProductDialog,
        backgroundColor: AppTheme.primaryGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Product', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // 2. Category Filter Chips & Low Stock Alert Quick Filter
          if (sortedCategories.isNotEmpty || productProv.lowStockCount > 0)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  FilterChip(
                    selected: _selectedCategory == 'All' && !_filterLowStockOnly,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text('All (${allProducts.length})'),
                    selectedColor: AppTheme.primaryLight,
                    checkmarkColor: AppTheme.primaryDark,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: (_selectedCategory == 'All' && !_filterLowStockOnly) ? FontWeight.bold : FontWeight.normal,
                      color: (_selectedCategory == 'All' && !_filterLowStockOnly) ? AppTheme.primaryDark : AppTheme.textDark,
                    ),
                    onSelected: (_) => setState(() {
                      _selectedCategory = 'All';
                      _filterLowStockOnly = false;
                    }),
                  ),
                  const SizedBox(width: 8),

                  if (productProv.lowStockCount > 0) ...[
                    FilterChip(
                      selected: _filterLowStockOnly,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.dangerRed),
                      label: Text('Low Stock (${productProv.lowStockCount})'),
                      selectedColor: AppTheme.dangerLight,
                      checkmarkColor: AppTheme.dangerRed,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _filterLowStockOnly ? AppTheme.dangerRed : AppTheme.textDark,
                      ),
                      onSelected: (val) => setState(() {
                        _filterLowStockOnly = val;
                        if (val) _selectedCategory = 'All';
                      }),
                    ),
                    const SizedBox(width: 8),
                  ],

                  ...sortedCategories.map((cat) {
                    final isSelected = !_filterLowStockOnly && _selectedCategory.toLowerCase() == cat.toLowerCase();
                    final count = allProducts
                        .where((p) => p.category.trim().toLowerCase() == cat.toLowerCase())
                        .length;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: isSelected,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(
                          _categoryIconData(cat),
                          size: 16,
                          color: isSelected ? AppTheme.primaryDark : AppTheme.textMuted,
                        ),
                        label: Text('$cat ($count)'),
                        selectedColor: AppTheme.primaryLight,
                        checkmarkColor: AppTheme.primaryDark,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? AppTheme.primaryDark : AppTheme.textDark,
                        ),
                        onSelected: (_) => setState(() {
                          _selectedCategory = cat;
                          _filterLowStockOnly = false;
                        }),
                      ),
                    );
                  }),
                ],
              ),
            ),

          const SizedBox(height: 6),

          // 3. Sectionized Product List
          Expanded(
            child: isLoading && allProducts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : displayedSections.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                hasActiveFilter
                                    ? 'No products found matching filters'
                                    : 'No products in inventory yet',
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
                              ),
                              if (hasActiveFilter) ...[
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _selectedCategory = 'All');
                                  },
                                  icon: const Icon(Icons.filter_alt_off, size: 16),
                                  label: const Text('Reset Filters'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                        itemCount: displayedSections.length,
                        itemBuilder: (context, sectionIndex) {
                          final section = displayedSections[sectionIndex];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Section Header
                              _buildSectionHeader(section.category, section.products.length),

                              // Products in this section
                              ...section.products.map((product) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _buildProductCard(context, product, api),
                                  )),
                              const SizedBox(height: 8),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String category, int itemCount) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8, left: 4, right: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_categoryIconData(category), size: 16, color: AppTheme.primaryDark),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, Product product, ApiService api) {
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
                      product.isBarcodeless ? 'PLU: ${product.barcodeString}' : 'Barcode: ${product.barcodeString}',
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
                      hasStock ? '${product.formattedStock} in stock' : 'Untracked',
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.dangerRed),
                        tooltip: 'Delete Product',
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: () => _confirmDeleteProduct(product),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.delete_forever, color: AppTheme.dangerRed),
            SizedBox(width: 8),
            Text('Delete Product', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('Are you sure you want to delete "${product.name}"? It will be removed from your catalog and cart.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await context.read<ProductProvider>().deleteProduct(product.id);
        messenger.showSnackBar(
          SnackBar(content: Text('Product "${product.name}" deleted successfully.')),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to delete product: $e'), backgroundColor: AppTheme.dangerRed),
        );
      }
    }
  }

  IconData _categoryIconData(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('bever') ||
        cat.contains('drink') ||
        cat.contains('water') ||
        cat.contains('beer') ||
        cat.contains('juice')) {
      return Icons.local_drink_outlined;
    } else if (cat.contains('can')) {
      return Icons.takeout_dining_outlined;
    } else if (cat.contains('noodle') || cat.contains('snack') || cat.contains('chip')) {
      return Icons.ramen_dining_outlined;
    } else if (cat.contains('condiment') ||
        cat.contains('sauce') ||
        cat.contains('cook') ||
        cat.contains('oil')) {
      return Icons.soup_kitchen_outlined;
    } else if (cat.contains('fresh') ||
        cat.contains('grocer') ||
        cat.contains('egg') ||
        cat.contains('fruit') ||
        cat.contains('veg')) {
      return Icons.eco_outlined;
    } else if (cat.contains('frozen') ||
        cat.contains('meat') ||
        cat.contains('fish') ||
        cat.contains('hotdog')) {
      return Icons.ac_unit_outlined;
    } else if (cat.contains('house') ||
        cat.contains('care') ||
        cat.contains('soap') ||
        cat.contains('clean')) {
      return Icons.clean_hands_outlined;
    }
    return Icons.category_outlined;
  }
}

class _CategorySection {
  final String category;
  final List<Product> products;
  _CategorySection({required this.category, required this.products});
}
