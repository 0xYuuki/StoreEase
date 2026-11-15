import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/analytics_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/debt_provider.dart';
import 'providers/product_provider.dart';
import 'providers/sales_provider.dart';
import 'screens/analytics_screen.dart';
import 'screens/debts_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/settings_screen.dart';
import 'services/api_service.dart';
import 'services/database_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = DatabaseService();
  await database.init();
  final storage = StorageService();
  final api = ApiService(database: database, storage: storage);

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseService>.value(value: database),
        Provider<StorageService>.value(value: storage),
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider(create: (_) => ProductProvider(api: api)..loadProducts()),
        ChangeNotifierProvider(create: (_) => CartProvider(api: api)),
        ChangeNotifierProvider(create: (_) => DebtProvider(api: api)),
        ChangeNotifierProvider(create: (_) => SalesProvider(api: api)..loadSales()),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider(api: api)..loadAnalytics()),
      ],
      child: const HelensStoreApp(),
    ),
  );
}

class HelensStoreApp extends StatelessWidget {
  const HelensStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Helen's Store",
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final lowStockCount = context.watch<ProductProvider>().lowStockCount;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          PosScreen(isActive: _currentIndex == 0),
          const DebtsScreen(),
          const InventoryScreen(),
          const SalesScreen(),
          const AnalyticsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 0 || index == 2) {
            context.read<ProductProvider>().loadProducts();
          } else if (index == 1) {
            context.read<DebtProvider>().loadDebts();
          } else if (index == 3) {
            context.read<SalesProvider>().loadSales();
          } else if (index == 4) {
            context.read<AnalyticsProvider>().loadAnalytics();
          }
        },
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart_outlined),
            activeIcon: Icon(Icons.shopping_cart),
            label: 'Cart',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Debts',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: lowStockCount > 0,
              label: Text('$lowStockCount'),
              child: const Icon(Icons.inventory_2_outlined),
            ),
            activeIcon: Badge(
              isLabelVisible: lowStockCount > 0,
              label: Text('$lowStockCount'),
              child: const Icon(Icons.inventory_2),
            ),
            label: 'Inventory',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Sales',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            activeIcon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
