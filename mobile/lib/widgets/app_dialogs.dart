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
                        decoration: const InputDecoration(
                          labelText: 'Select Customer',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        items: debtors.map((d) {
                          return DropdownMenuItem<int>(
                            value: d.id,
                            child: Text('${d.name} (${d.formattedBalance})'),
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
                                Text('${item.quantity} x ₱${item.pricePesos.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
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
                              icon: const Icon(Icons.attach_money, size: 18),
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
}
