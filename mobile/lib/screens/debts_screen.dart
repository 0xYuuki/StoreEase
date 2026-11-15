import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/debt_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialogs.dart';

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DebtProvider>().loadDebts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showAddCustomerDialog() async {
    final nameController = TextEditingController();
    final debtController = TextEditingController();
    final notesController = TextEditingController();
    final phoneController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.person_add_alt_1, color: AppTheme.primaryGreen),
              SizedBox(width: 8),
              Text('Add New Debtor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Customer Full Name *',
                    hintText: 'e.g. Aling Nena, Juan Dela Cruz',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: debtController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Money Borrowed / Initial Debt (₱)',
                    hintText: '0.00',
                    helperText: 'Enter amount borrowed or leave 0.00',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Reason (Optional)',
                    hintText: 'e.g. Suki, borrowed for groceries',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number (Optional)',
                    hintText: 'e.g. 09123456789',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
              ],
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
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter customer name'), backgroundColor: AppTheme.dangerRed),
                  );
                  return;
                }

                final debtText = debtController.text.trim();
                double debtPesos = 0.0;
                if (debtText.isNotEmpty) {
                  debtPesos = double.tryParse(debtText) ?? -1;
                  if (debtPesos < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Debt amount must be 0 or positive'), backgroundColor: AppTheme.dangerRed),
                    );
                    return;
                  }
                }

                final initialCentavos = (debtPesos * 100).round();
                final notes = notesController.text.trim();
                final phone = phoneController.text.trim();

                final messenger = ScaffoldMessenger.of(context);
                final debtProvider = context.read<DebtProvider>();
                final nav = Navigator.of(ctx);

                try {
                  await debtProvider.createDebtor(
                    name,
                    initialDebtCentavos: initialCentavos,
                    notes: notes.isNotEmpty ? notes : null,
                    phone: phone.isNotEmpty ? phone : null,
                  );
                  nav.pop(true);
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Failed to add debtor: $e'), backgroundColor: AppTheme.dangerRed),
                  );
                }
              },
              child: const Text('Save Debtor', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (saved == true && mounted) {
      final debtText = debtController.text.trim();
      final hasDebt = (double.tryParse(debtText) ?? 0) > 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasDebt
                ? 'Debtor "${nameController.text.trim()}" added with ₱$debtText initial debt!'
                : 'Customer "${nameController.text.trim()}" added successfully!',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final debtProv = context.watch<DebtProvider>();
    final api = context.read<ApiService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Customer Debts"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => debtProv.loadDebts(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCustomerDialog,
        backgroundColor: AppTheme.primaryGreen,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Add Customer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // KPI Banner
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryDark, AppTheme.primaryGreen],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL UNPAID DEBTS',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      debtProv.formattedTotalUnpaid,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${debtProv.activeDebtorsCount}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'Active Debtors',
                        style: TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Segmented Filter Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _buildFilterTab(
                  label: 'Active Debt',
                  count: debtProv.activeDebtorsCount,
                  filterKey: 'active',
                  activeFilter: debtProv.filter,
                  onTap: () => debtProv.setFilter('active'),
                ),
                const SizedBox(width: 6),
                _buildFilterTab(
                  label: 'Fully Paid',
                  count: debtProv.fullyPaidCount,
                  filterKey: 'paid',
                  activeFilter: debtProv.filter,
                  onTap: () => debtProv.setFilter('paid'),
                ),
                const SizedBox(width: 6),
                _buildFilterTab(
                  label: 'All',
                  count: debtProv.allDebtors.length,
                  filterKey: 'all',
                  activeFilter: debtProv.filter,
                  onTap: () => debtProv.setFilter('all'),
                ),
              ],
            ),
          ),

          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search customer name...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          debtProv.setSearchQuery('');
                        },
                      )
                    : null,
              ),
              onChanged: (val) => debtProv.setSearchQuery(val),
            ),
          ),

          // Customer List
          Expanded(
            child: debtProv.isLoading
                ? const Center(child: CircularProgressIndicator())
                : debtProv.filteredDebtors.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            Text(
                              debtProv.searchQuery.isNotEmpty
                                  ? 'No customers matching "${debtProv.searchQuery}"'
                                  : 'No customers found for this tab',
                              style: const TextStyle(color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                        itemCount: debtProv.filteredDebtors.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final debtor = debtProv.filteredDebtors[index];
                          final hasDebt = debtor.currentBalance > 0;

                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                AppDialogs.showCustomerLedgerDialog(
                                  context,
                                  debtor,
                                  api,
                                  () => debtProv.loadDebts(),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: hasDebt ? AppTheme.dangerLight : AppTheme.primaryLight,
                                      child: Icon(
                                        hasDebt ? Icons.account_balance_wallet_outlined : Icons.check_circle_outline,
                                        color: hasDebt ? AppTheme.dangerRed : AppTheme.primaryDark,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            debtor.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            hasDebt ? 'Active Debt' : 'Fully Paid',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: hasDebt ? AppTheme.dangerRed : AppTheme.primaryGreen,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          debtor.formattedBalance,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: hasDebt ? AppTheme.dangerRed : AppTheme.primaryGreen,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'Tap for ledger',
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

  Widget _buildFilterTab({
    required String label,
    required int count,
    required String filterKey,
    required String activeFilter,
    required VoidCallback onTap,
  }) {
    final isActive = filterKey == activeFilter;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primaryGreen : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? AppTheme.primaryGreen : AppTheme.cardBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : AppTheme.textDark,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white.withValues(alpha: 0.2) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.white : AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
