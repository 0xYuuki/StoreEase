import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ShortageDialogResult {
  final int? debtorId;
  final String? newDebtorName;

  ShortageDialogResult({this.debtorId, this.newDebtorName});
}

class AppDialogs {
  // 1. Cash Shortage / Debt Selection Dialog
  static Future<ShortageDialogResult?> showShortageDialog({
    required BuildContext context,
    required int totalCentavos,
    required int tenderedCentavos,
    required List<Debtor> debtors,
  }) async {
    final shortageCentavos = totalCentavos - tenderedCentavos;
    final shortagePesos = shortageCentavos / 100.0;
    final totalPesos = totalCentavos / 100.0;
    final tenderedPesos = tenderedCentavos / 100.0;

    int? selectedDebtorId = debtors.isNotEmpty ? debtors.first.id : null;
    final nameController = TextEditingController();
    bool isNewCustomer = debtors.isEmpty;

    return showDialog<ShortageDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                  SizedBox(width: 8),
                  Text('Cash Shortage Detected', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Bill:'),
                              Text('₱${totalPesos.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Cash Tendered:'),
                              Text('₱${tenderedPesos.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Shortage / Debt:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                              Text('₱${shortagePesos.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Who is this debt charged to?', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    SegmentedButton<bool>(
                      segments: [
                        if (debtors.isNotEmpty)
                          const ButtonSegment<bool>(
                            value: false,
                            label: Text('Existing Customer'),
                            icon: Icon(Icons.person_outline, size: 16),
                          ),
                        const ButtonSegment<bool>(
                          value: true,
                          label: Text('New Customer'),
                          icon: Icon(Icons.person_add_alt, size: 16),
                        ),
                      ],
                      selected: {isNewCustomer},
                      onSelectionChanged: (val) => setState(() => isNewCustomer = val.first),
                    ),
                    const SizedBox(height: 12),
                    if (!isNewCustomer && debtors.isNotEmpty)
                      DropdownButtonFormField<int>(
                        initialValue: selectedDebtorId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Select Customer',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        items: debtors.map((d) {
                          return DropdownMenuItem<int>(
                            value: d.id,
                            child: Text(
                              '${d.name} (${d.formattedBalance})',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => selectedDebtorId = val),
                      ),
                    if (isNewCustomer)
                      TextField(
                        controller: nameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Customer Full Name',
                          hintText: 'e.g. Maria Santos',
                          prefixIcon: Icon(Icons.person_add_alt),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (isNewCustomer) {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter customer name')),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop(ShortageDialogResult(newDebtorName: name));
                    } else {
                      if (selectedDebtorId == null) return;
                      Navigator.of(ctx).pop(ShortageDialogResult(debtorId: selectedDebtorId));
                    }
                  },
                  child: const Text('Confirm & Record Debt'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 2. Receipt Dialog
  static Future<void> showReceiptDialog(BuildContext context, SaleReceipt receipt) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/logo.png',
                    height: 52,
                    errorBuilder: (_, _, _) => const Icon(Icons.store, size: 48, color: AppTheme.primaryGreen),
                  ),
                  const SizedBox(height: 6),
                  const Text("Helen's Store", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text('Official Sale Receipt', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  Text('Receipt #${receipt.saleId}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  const Divider(height: 24, thickness: 1),
                  ...receipt.items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text(
                                  item.isWeighted
                                      ? '${item.formattedQuantityOrWeight} @ ₱${item.pricePesos.toStringAsFixed(2)}/${item.unit ?? 'kg'}'
                                      : '${item.quantity} x ₱${item.pricePesos.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                          Text('₱${item.lineTotalPesos.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 20, thickness: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(receipt.formattedTotal, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryGreen)),
                    ],
                  ),
                  if (receipt.tenderedAmount != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Amount Tendered:', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                        Text('₱${(receipt.tenderedAmount! / 100.0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                  if (receipt.changeAmount != null && receipt.changeAmount! > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Change:', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                        Text('₱${(receipt.changeAmount! / 100.0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                  if (receipt.debtorName != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Customer Debt:', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)),
                              Text(receipt.debtorName!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          if (receipt.debtCharged != null)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Charged to Debt:', style: TextStyle(fontSize: 11, color: Colors.red)),
                                Text('₱${(receipt.debtCharged! / 100.0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red)),
                              ],
                            ),
                          if (receipt.debtBalance != null)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Updated Balance:', style: TextStyle(fontSize: 11, color: Colors.red)),
                                Text('₱${(receipt.debtBalance! / 100.0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('New Transaction'),
              ),
            ),
          ],
        );
      },
    );
  }

  // 3. Customer Ledger Pop-up Dialog
  static Future<void> showCustomerLedgerDialog(
    BuildContext context,
    Debtor debtor,
    ApiService api,
    VoidCallback onPaymentRecorded,
  ) async {
    return showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: FutureBuilder<List<DebtTransaction>>(
              future: api.getCustomerTransactions(debtor.id),
              builder: (context, snapshot) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(debtor.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('Customer Debt Ledger', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: debtor.currentBalance > 0 ? AppTheme.dangerLight : AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            debtor.formattedBalance,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: debtor.currentBalance > 0 ? AppTheme.dangerRed : AppTheme.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Expanded(
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const Center(child: CircularProgressIndicator())
                          : (snapshot.data == null || snapshot.data!.isEmpty)
                              ? const Center(child: Text('No transaction history.'))
                              : ListView.separated(
                                  itemCount: snapshot.data!.length,
                                  separatorBuilder: (_, _) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final tx = snapshot.data![index];
                                    final isPayment = tx.isPayment;
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: isPayment ? AppTheme.primaryLight : AppTheme.dangerLight,
                                        child: Icon(
                                          isPayment ? Icons.payment : Icons.shopping_bag_outlined,
                                          size: 16,
                                          color: isPayment ? AppTheme.primaryDark : AppTheme.dangerRed,
                                        ),
                                      ),
                                      title: Text(
                                        isPayment ? 'Payment' : 'Debt Charge (Sale #${tx.saleId ?? ''})',
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        tx.createdAt.split('T').first,
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${isPayment ? '-' : '+'}${tx.formattedAmount}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: isPayment ? AppTheme.primaryGreen : AppTheme.dangerRed,
                                            ),
                                          ),
                                          Text('Bal: ${tx.formattedResultingBalance}', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Close'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (debtor.currentBalance > 0)
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.payments_outlined, size: 18),
                              label: const Text('Record Payment'),
                              onPressed: () async {
                                final paid = await showRecordPaymentDialog(context, debtor, api);
                                if (ctx.mounted && paid == true) {
                                  Navigator.of(ctx).pop();
                                  onPaymentRecorded();
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // 4. Record Payment Dialog
  static Future<bool?> showRecordPaymentDialog(
    BuildContext context,
    Debtor debtor,
    ApiService api,
  ) {
    final amountController = TextEditingController(text: debtor.balancePesos.toStringAsFixed(2));
    final notesController = TextEditingController();

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Record Payment · ${debtor.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Outstanding Debt: ${debtor.formattedBalance}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Payment Amount (₱)',
                  prefixText: '₱ ',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes / Reference (Optional)',
                  hintText: 'e.g. Cash / Gcash',
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
                final text = amountController.text.trim();
                final pesos = double.tryParse(text);
                if (pesos == null || pesos <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid payment amount')),
                  );
                  return;
                }
                final centavos = (pesos * 100).round();
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(ctx);
                try {
                  await api.recordPayment(debtor.id, centavos, notes: notesController.text);
                  navigator.pop(true);
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              },
              child: const Text('Submit Payment'),
            ),
          ],
        );
      },
    );
  }

  // 5. Product Stock History Pop-up Dialog
  static Future<void> showStockHistoryDialog(
    BuildContext context,
    Product product,
    ApiService api,
  ) {
    return showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: FutureBuilder<Map<String, dynamic>>(
              future: api.getStockHistory(product.id),
              builder: (context, snapshot) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(product.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('Barcode: ${product.barcodeString}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: product.stock != null ? AppTheme.primaryLight : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            product.stock != null ? '${product.stock} in stock' : 'Untracked',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: product.stock != null ? AppTheme.primaryDark : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Expanded(
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const Center(child: CircularProgressIndicator())
                          : (snapshot.data == null || (snapshot.data!['entries'] as List<StockMovement>).isEmpty)
                              ? const Center(child: Text('No recorded stock movements.'))
                              : ListView.separated(
                                  itemCount: (snapshot.data!['entries'] as List<StockMovement>).length,
                                  separatorBuilder: (_, _) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final move = (snapshot.data!['entries'] as List<StockMovement>)[index];
                                    final isPositive = move.delta > 0;
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: isPositive ? AppTheme.primaryLight : AppTheme.dangerLight,
                                        child: Icon(
                                          isPositive ? Icons.add : Icons.remove,
                                          size: 16,
                                          color: isPositive ? AppTheme.primaryDark : AppTheme.dangerRed,
                                        ),
                                      ),
                                      title: Text(move.reason, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                      subtitle: Text(
                                        move.timestamp.split('T').first,
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${isPositive ? '+' : ''}${move.delta}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: isPositive ? AppTheme.primaryGreen : AppTheme.dangerRed,
                                            ),
                                          ),
                                          Text('left: ${move.resultingStock}', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // 6. Weight Entry Modal (Timbang) for POS
  static Future<double?> showWeightEntryDialog({
    required BuildContext context,
    required Product product,
    double? initialWeight,
  }) async {
    return await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WeightEntrySheet(
        product: product,
        initialWeight: initialWeight,
      ),
    );
  }
}

class _WeightEntrySheet extends StatefulWidget {
  final Product product;
  final double? initialWeight;

  const _WeightEntrySheet({
    required this.product,
    this.initialWeight,
  });

  @override
  State<_WeightEntrySheet> createState() => _WeightEntrySheetState();
}

class _WeightEntrySheetState extends State<_WeightEntrySheet> {
  late double _currentWeight;
  int _activeTab = 0; // 0 = By Weight, 1 = By Amount
  late final TextEditingController _weightCtrl;
  late final TextEditingController _amountCtrl;

  static const List<Map<String, dynamic>> _weightPresets = [
    {'label': '1/4 kg', 'weight': 0.25, 'sub': '250g'},
    {'label': '1/2 kg', 'weight': 0.50, 'sub': '500g'},
    {'label': '3/4 kg', 'weight': 0.75, 'sub': '750g'},
    {'label': '1 kg', 'weight': 1.0, 'sub': '1000g'},
    {'label': '2 kg', 'weight': 2.0, 'sub': '2000g'},
    {'label': '5 kg', 'weight': 5.0, 'sub': '5000g'},
  ];

  static const List<double> _amountPresets = [10.0, 20.0, 50.0, 100.0, 200.0];

  @override
  void initState() {
    super.initState();
    _currentWeight = widget.initialWeight ?? 0.50;
    _weightCtrl = TextEditingController(
      text: _currentWeight % 1 == 0 ? _currentWeight.toInt().toString() : _currentWeight.toStringAsFixed(2),
    );
    _amountCtrl = TextEditingController(
      text: (_currentWeight * widget.product.pricePesos).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lineTotalPesos = (_currentWeight * widget.product.pricePesos);
    final grams = (_currentWeight * 1000).round();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Product Title & Rate
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.scale_outlined, color: AppTheme.primaryGreen, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Price Rate: ₱${widget.product.pricePesos.toStringAsFixed(2)} / ${widget.product.unit}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(null),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Tab selector (By Weight vs By Amount)
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
                        setState(() {
                          _activeTab = 0;
                          _weightCtrl.text = _currentWeight % 1 == 0
                              ? _currentWeight.toInt().toString()
                              : _currentWeight.toStringAsFixed(2);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _activeTab == 0 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _activeTab == 0
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '⚖️ By Weight (${widget.product.unit})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _activeTab == 0 ? AppTheme.primaryDark : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _activeTab = 1;
                          _amountCtrl.text = lineTotalPesos.toStringAsFixed(2);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _activeTab == 1 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _activeTab == 1
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '₱ By Amount (Halaga)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _activeTab == 1 ? AppTheme.primaryDark : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // TAB 0: By Weight Content
            if (_activeTab == 0) ...[
              const Text(
                'QUICK SARI-SARI PRESETS:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.8,
                children: _weightPresets.map((preset) {
                  final pWeight = preset['weight'] as double;
                  final isSelected = (_currentWeight - pWeight).abs() < 0.001;
                  final cost = pWeight * widget.product.pricePesos;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _currentWeight = pWeight;
                        _weightCtrl.text = pWeight % 1 == 0
                            ? pWeight.toInt().toString()
                            : pWeight.toStringAsFixed(2);
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primaryLight : Colors.grey.shade50,
                        border: Border.all(
                          color: isSelected ? AppTheme.primaryGreen : Colors.grey.shade300,
                          width: isSelected ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            preset['label'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? AppTheme.primaryDark : AppTheme.textDark,
                            ),
                          ),
                          Text(
                            '${preset['sub']} • ₱${cost.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Custom Weight (${widget.product.unit})',
                  hintText: 'e.g. 0.65',
                  prefixIcon: const Icon(Icons.edit_outlined),
                  suffixText: '= $grams grams',
                  suffixStyle: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val.trim());
                  if (parsed != null && parsed > 0) {
                    setState(() {
                      _currentWeight = parsed;
                    });
                  }
                },
              ),
            ] else ...[
              // TAB 1: By Amount Content
              const Text(
                'QUICK PESO AMOUNT PRESETS (HALAGA):',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _amountPresets.map((amt) {
                  final equivWeight = widget.product.pricePesos > 0 ? (amt / widget.product.pricePesos) : 0.0;
                  final isSelected = (lineTotalPesos - amt).abs() < 0.1;

                  return ActionChip(
                    label: Text('₱${amt.toStringAsFixed(0)} (${equivWeight.toStringAsFixed(2)} kg)'),
                    backgroundColor: isSelected ? AppTheme.primaryLight : Colors.grey.shade100,
                    side: BorderSide(
                      color: isSelected ? AppTheme.primaryGreen : Colors.grey.shade300,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? AppTheme.primaryDark : AppTheme.textDark,
                    ),
                    onPressed: () {
                      setState(() {
                        _currentWeight = equivWeight;
                        _amountCtrl.text = amt.toStringAsFixed(2);
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Target Peso Amount (₱)',
                  hintText: 'e.g. 25.00',
                  prefixText: '₱ ',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  suffixText: '= ${_currentWeight.toStringAsFixed(3)} ${widget.product.unit}',
                  suffixStyle: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val.trim());
                  if (parsed != null && parsed > 0 && widget.product.pricePesos > 0) {
                    setState(() {
                      _currentWeight = parsed / widget.product.pricePesos;
                    });
                  }
                },
              ),
            ],

            const SizedBox(height: 16),

            // Calculation Summary Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withValues(alpha: 0.5),
                border: Border.all(color: AppTheme.accentGreen),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Weight: ${_currentWeight % 1 == 0 ? _currentWeight.toInt() : _currentWeight.toStringAsFixed(2)} ${widget.product.unit} ($grams g)',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
                      ),
                      Text(
                        '@ ₱${widget.product.pricePesos.toStringAsFixed(2)}/${widget.product.unit}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Calculated Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(
                        '₱${lineTotalPesos.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      if (_currentWeight <= 0) return;
                      Navigator.of(context).pop(_currentWeight);
                    },
                    child: Text(
                      'Add ₱${lineTotalPesos.toStringAsFixed(2)} to Cart',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
