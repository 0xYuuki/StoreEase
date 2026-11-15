import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

class DatabaseService {
  static const String _dbFileName = 'helens_store.db';
  static const int _dbVersion = 1;

  Database? _db;
  final Uuid _uuid = const Uuid();

  DatabaseService({Database? database}) : _db = database;

  Database get db {
    if (_db == null) {
      throw StateError('DatabaseService has not been initialized. Call init() first.');
    }
    return _db!;
  }

  bool get isOpen => _db != null && _db!.isOpen;

  Future<void> init({String? customPath}) async {
    if (_db != null && _db!.isOpen) return;

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
    }

    final dbPath = customPath ?? p.join(await getDatabasesPath(), _dbFileName);

    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createTables(db);
        await _seedDefaultData(db);
      },
    );

    // Auto-migrate schema: ensure new columns exist on Products & SaleItems
    final productCols = await _db!.rawQuery('PRAGMA table_info(Products)');
    if (!productCols.any((c) => c['name'] == 'category')) {
      await _db!.execute("ALTER TABLE Products ADD COLUMN category TEXT NOT NULL DEFAULT 'General'");
    }
    if (!productCols.any((c) => c['name'] == 'pricing_type')) {
      await _db!.execute("ALTER TABLE Products ADD COLUMN pricing_type TEXT NOT NULL DEFAULT 'unit'");
    }
    if (!productCols.any((c) => c['name'] == 'unit')) {
      await _db!.execute("ALTER TABLE Products ADD COLUMN unit TEXT NOT NULL DEFAULT 'pc'");
    }
    if (!productCols.any((c) => c['name'] == 'is_barcodeless')) {
      await _db!.execute("ALTER TABLE Products ADD COLUMN is_barcodeless INTEGER NOT NULL DEFAULT 0");
    }

    final saleItemCols = await _db!.rawQuery('PRAGMA table_info(SaleItems)');
    if (!saleItemCols.any((c) => c['name'] == 'weight')) {
      await _db!.execute("ALTER TABLE SaleItems ADD COLUMN weight REAL");
    }
    if (!saleItemCols.any((c) => c['name'] == 'unit')) {
      await _db!.execute("ALTER TABLE SaleItems ADD COLUMN unit TEXT");
    }
  }

  Future<void> _createTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode_string TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        price INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        stock REAL,
        reorder_level REAL,
        category TEXT NOT NULL DEFAULT 'General',
        pricing_type TEXT NOT NULL DEFAULT 'unit',
        unit TEXT NOT NULL DEFAULT 'pc',
        is_barcodeless INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        total_amount INTEGER NOT NULL,
        idempotency_key TEXT UNIQUE,
        payment_type TEXT DEFAULT 'cash',
        customer_id INTEGER REFERENCES Customers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS SaleItems (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL REFERENCES Sales(id) ON DELETE RESTRICT,
        product_id INTEGER REFERENCES Products(id) ON DELETE RESTRICT,
        quantity INTEGER NOT NULL,
        weight REAL,
        unit TEXT,
        price INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        barcode_string TEXT NOT NULL,
        line_total INTEGER NOT NULL,
        snapshot_source TEXT NOT NULL DEFAULT 'checkout'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS StockAdjustments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL REFERENCES Products(id),
        delta INTEGER NOT NULL,
        resulting_stock INTEGER NOT NULL,
        reason TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        sale_id INTEGER REFERENCES Sales(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        notes TEXT,
        balance INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS CustomerDebts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL REFERENCES Customers(id) ON DELETE RESTRICT,
        type TEXT NOT NULL CHECK(type IN ('debt', 'payment')),
        amount INTEGER NOT NULL,
        balance_after INTEGER NOT NULL,
        notes TEXT,
        sale_id INTEGER REFERENCES Sales(id) ON DELETE SET NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS sales_timestamp ON Sales(timestamp)');
    await db.execute('CREATE INDEX IF NOT EXISTS items_sale ON SaleItems(sale_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS items_product ON SaleItems(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS stock_history_product ON StockAdjustments(product_id, id)');
    await db.execute('CREATE INDEX IF NOT EXISTS customer_debts_customer ON CustomerDebts(customer_id, id)');
    await db.execute('CREATE INDEX IF NOT EXISTS customers_name ON Customers(name)');
  }

  Future<void> _seedDefaultData(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();

    // Starter inventory products
    final products = [
      {'barcode_string': '1', 'name': 'Egg', 'price': 1100, 'stock': 92, 'reorder_level': 10, 'active': 1, 'category': 'Fresh & Grocery'},
      {'barcode_string': '333333333331', 'name': 'Hotdog', 'price': 1200, 'stock': 50, 'reorder_level': 10, 'active': 1, 'category': 'Frozen & Meat'},
      {'barcode_string': '4800016644801', 'name': 'Lucky Me! Pancit Canton (Original)', 'price': 1800, 'stock': 40, 'reorder_level': 15, 'active': 1, 'category': 'Instant Noodles & Snacks'},
      {'barcode_string': '4800016644802', 'name': 'Mega Sardines in Tomato Sauce 155g', 'price': 2500, 'stock': 30, 'reorder_level': 10, 'active': 1, 'category': 'Canned Goods'},
      {'barcode_string': '4800016644803', 'name': 'Nature Spring Bottled Water 500ml', 'price': 1500, 'stock': 60, 'reorder_level': 20, 'active': 1, 'category': 'Beverages'},
      {'barcode_string': '4800016644804', 'name': 'San Miguel Pale Pilsen 330ml', 'price': 6500, 'stock': 24, 'reorder_level': 8, 'active': 1, 'category': 'Beverages'},
      {'barcode_string': '4800016644805', 'name': 'Silver Swan Soy Sauce 385ml', 'price': 2200, 'stock': 20, 'reorder_level': 5, 'active': 1, 'category': 'Condiments & Cooking'},
    ];

    for (final p in products) {
      await db.insert('Products', p);
    }

    // Starter customer with existing suki ledger balance
    final alingNenaId = await db.insert('Customers', {
      'name': 'Aling Nena',
      'phone': '09123456789',
      'address': 'Purok 2',
      'notes': 'Suki',
      'balance': 23600, // 236.00 pesos
      'created_at': now,
      'updated_at': now,
      'active': 1,
    });

    await db.insert('CustomerDebts', {
      'customer_id': alingNenaId,
      'type': 'debt',
      'amount': 23600,
      'balance_after': 23600,
      'notes': 'Initial ledger balance',
      'sale_id': null,
      'timestamp': now,
    });

    await db.insert('Customers', {
      'name': 'Jemuel',
      'phone': '09987654321',
      'address': 'Main Street',
      'notes': 'Regular customer',
      'balance': 0,
      'created_at': now,
      'updated_at': now,
      'active': 1,
    });
  }

  // --- PRODUCTS ---

  Future<String> generateNextPluBarcode() async {
    final rows = await db.rawQuery(
      "SELECT barcode_string FROM Products WHERE barcode_string LIKE 'PLU-%' ORDER BY id DESC LIMIT 1",
    );
    if (rows.isNotEmpty) {
      final lastCode = rows.first['barcode_string'] as String;
      final match = RegExp(r'PLU-(\d+)').firstMatch(lastCode);
      if (match != null) {
        final val = int.tryParse(match.group(1)!) ?? 1000;
        return 'PLU-${val + 1}';
      }
    }
    final countRows = await db.rawQuery("SELECT COUNT(*) as cnt FROM Products");
    final count = (countRows.first['cnt'] as int? ?? 0) + 1001;
    return 'PLU-$count';
  }

  Future<Product> createProduct({
    String? barcodeString,
    required String name,
    required int priceCentavos,
    num? initialStock,
    num? reorderLevel,
    String category = 'General',
    String pricingType = 'unit',
    String unit = 'pc',
    bool isBarcodeless = false,
  }) async {
    final cleanName = name.trim();
    final cleanCategory = category.trim().isEmpty ? 'General' : category.trim();
    final cleanPricingType = pricingType.trim().isEmpty ? 'unit' : pricingType.trim();
    final cleanUnit = unit.trim().isEmpty ? (cleanPricingType == 'weight' ? 'kg' : 'pc') : unit.trim();
    if (cleanName.isEmpty) throw Exception('Product name cannot be empty');
    if (priceCentavos < 0) throw Exception('Price cannot be negative');

    String cleanBarcode = (barcodeString ?? '').trim();
    if (cleanBarcode.isEmpty || isBarcodeless) {
      isBarcodeless = true;
      if (cleanBarcode.isEmpty) {
        cleanBarcode = await generateNextPluBarcode();
      }
    }

    return await db.transaction<Product>((txn) async {
      final existing = await txn.query(
        'Products',
        where: 'barcode_string = ? AND active = ?',
        whereArgs: [cleanBarcode, 1],
      );
      if (existing.isNotEmpty) {
        throw Exception('Barcode "$cleanBarcode" is already used by "${existing.first['name']}"');
      }

      final id = await txn.insert('Products', {
        'barcode_string': cleanBarcode,
        'name': cleanName,
        'price': priceCentavos,
        'stock': initialStock,
        'reorder_level': reorderLevel,
        'active': 1,
        'category': cleanCategory,
        'pricing_type': cleanPricingType,
        'unit': cleanUnit,
        'is_barcodeless': isBarcodeless ? 1 : 0,
      });

      if (initialStock != null && initialStock > 0) {
        final now = DateTime.now().toIso8601String();
        await txn.insert('StockAdjustments', {
          'product_id': id,
          'delta': initialStock,
          'resulting_stock': initialStock,
          'reason': 'Initial Stock',
          'timestamp': now,
        });
      }

      return Product(
        id: id,
        barcodeString: cleanBarcode,
        name: cleanName,
        priceCentavos: priceCentavos,
        stock: initialStock,
        reorderLevel: reorderLevel,
        active: 1,
        category: cleanCategory,
        pricingType: cleanPricingType,
        unit: cleanUnit,
        isBarcodeless: isBarcodeless,
      );
    });
  }

  Future<List<Product>> getProducts() async {
    final rows = await db.query(
      'Products',
      where: 'active = ?',
      whereArgs: [1],
      orderBy: 'name ASC',
    );
    return rows.map((r) => Product.fromJson(r)).toList();
  }

  Future<Product?> lookupBarcode(String barcode) async {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;
    final rows = await db.query(
      'Products',
      where: 'barcode_string = ? AND active = ?',
      whereArgs: [clean, 1],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Product.fromJson(rows.first);
  }

  Future<Product> adjustStock(int productId, num delta, String reason) async {
    return await db.transaction<Product>((txn) async {
      final rows = await txn.query(
        'Products',
        where: 'id = ? AND active = ?',
        whereArgs: [productId, 1],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw Exception('Product not found (ID: $productId)');
      }

      final product = Product.fromJson(rows.first);
      final currentStock = product.stock ?? 0;
      final resultingStock = currentStock + delta;
      if (resultingStock < 0) {
        throw Exception('Resulting stock cannot be negative ($resultingStock)');
      }

      final now = DateTime.now().toIso8601String();

      await txn.update(
        'Products',
        {'stock': resultingStock},
        where: 'id = ?',
        whereArgs: [productId],
      );

      await txn.insert('StockAdjustments', {
        'product_id': productId,
        'delta': delta,
        'resulting_stock': resultingStock,
        'reason': reason.trim(),
        'timestamp': now,
      });

      final updatedRows = await txn.query(
        'Products',
        where: 'id = ?',
        whereArgs: [productId],
      );
      return Product.fromJson(updatedRows.first);
    });
  }

  Future<Map<String, dynamic>> getStockHistory(int productId, {int page = 1}) async {
    const limit = 25;
    final offset = (page - 1) * limit;

    final rows = await db.query(
      'StockAdjustments',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'id DESC',
      limit: limit + 1,
      offset: offset,
    );

    final hasMore = rows.length > limit;
    final entries = rows.take(limit).map((r) => StockMovement.fromJson(r)).toList();

    return {
      'entries': entries,
      'has_more': hasMore,
    };
  }

  // --- CHECKOUT & POS ---

  Future<SaleReceipt> checkout({
    required List<CartItem> items,
    required int tenderedAmount,
    int? debtorId,
    String? newDebtorName,
    String? idempotencyKey,
  }) async {
    if (items.isEmpty) {
      throw Exception('Cart is empty');
    }

    return await db.transaction<SaleReceipt>((txn) async {
      // 1. Calculate total and verify stock availability
      int totalCentavos = 0;
      for (final item in items) {
        final lineTotal = item.lineTotalCentavos;
        totalCentavos += lineTotal;

        if (item.product.stock != null) {
          final pRows = await txn.query(
            'Products',
            where: 'id = ?',
            whereArgs: [item.product.id],
          );
          if (pRows.isNotEmpty) {
            final currentStock = (pRows.first['stock'] as num?)?.toDouble();
            final requiredQty = item.isWeighted ? (item.weight ?? 1.0) : item.quantity.toDouble();
            if (currentStock != null && currentStock < requiredQty) {
              final formattedReq = item.isWeighted
                  ? '${requiredQty.toStringAsFixed(2)} ${item.product.unit}'
                  : '${item.quantity} pcs';
              final formattedAvail = item.isWeighted
                  ? '${currentStock.toStringAsFixed(2)} ${item.product.unit}'
                  : '${currentStock.toInt()} pcs';
              throw Exception('Insufficient stock for ${item.product.name} (Available: $formattedAvail, Required: $formattedReq)');
            }
          }
        }
      }

      // 2. Determine payment type & resolve debtor
      final isShortage = tenderedAmount < totalCentavos;
      final isDebt = debtorId != null || (newDebtorName != null && newDebtorName.trim().isNotEmpty) || isShortage;

      int? resolvedCustomerId;
      String? resolvedCustomerName;
      int debtAmount = 0;
      int cashTendered = tenderedAmount;

      if (isDebt) {
        if (debtorId != null) {
          final custRows = await txn.query('Customers', where: 'id = ?', whereArgs: [debtorId]);
          if (custRows.isEmpty) throw Exception('Customer not found');
          resolvedCustomerId = debtorId;
          resolvedCustomerName = custRows.first['name'] as String;
        } else if (newDebtorName != null && newDebtorName.trim().isNotEmpty) {
          final trimmed = newDebtorName.trim();
          final existing = await txn.query(
            'Customers',
            where: 'LOWER(TRIM(name)) = LOWER(?)',
            whereArgs: [trimmed],
          );
          if (existing.isNotEmpty) {
            resolvedCustomerId = existing.first['id'] as int;
            resolvedCustomerName = existing.first['name'] as String;
          } else {
            final now = DateTime.now().toIso8601String();
            resolvedCustomerId = await txn.insert('Customers', {
              'name': trimmed,
              'balance': 0,
              'active': 1,
              'created_at': now,
              'updated_at': now,
            });
            resolvedCustomerName = trimmed;
          }
        } else if (isShortage) {
          throw Exception('Payment is insufficient (Shortage: ₱${((totalCentavos - tenderedAmount) / 100).toStringAsFixed(2)}). Please select or enter a customer for debt.');
        }

        if (tenderedAmount < totalCentavos) {
          cashTendered = tenderedAmount > 0 ? tenderedAmount : 0;
          debtAmount = totalCentavos - cashTendered;
        }
      }

      final now = DateTime.now().toIso8601String();
      final key = idempotencyKey ?? _uuid.v4();

      // 3. Insert Sale
      final saleId = await txn.insert('Sales', {
        'timestamp': now,
        'total_amount': totalCentavos,
        'idempotency_key': key,
        'payment_type': isDebt ? 'debt' : 'cash',
        'customer_id': resolvedCustomerId,
      });

      // 4. Insert SaleItems & update inventory stock
      final receiptItems = <SaleItem>[];
      for (final item in items) {
        final lineTotal = item.lineTotalCentavos;
        final itemWeight = item.isWeighted ? (item.weight ?? 1.0) : null;
        final itemUnit = item.isWeighted ? item.product.unit : 'pc';

        await txn.insert('SaleItems', {
          'sale_id': saleId,
          'product_id': item.product.id,
          'quantity': item.quantity,
          'weight': itemWeight,
          'unit': itemUnit,
          'price': item.product.priceCentavos,
          'product_name': item.product.name,
          'barcode_string': item.product.barcodeString,
          'line_total': lineTotal,
          'snapshot_source': 'checkout',
        });

        receiptItems.add(SaleItem(
          productId: item.product.id,
          productName: item.product.name,
          barcodeString: item.product.barcodeString,
          quantity: item.quantity,
          weight: itemWeight,
          unit: itemUnit,
          price: item.product.priceCentavos,
          lineTotal: lineTotal,
        ));

        if (item.product.stock != null) {
          final pRows = await txn.query('Products', where: 'id = ?', whereArgs: [item.product.id]);
          final currentStock = (pRows.first['stock'] as num?)?.toDouble() ?? 0.0;
          final deductAmount = item.isWeighted ? (item.weight ?? 1.0) : item.quantity.toDouble();
          final newStock = currentStock - deductAmount;

          await txn.update(
            'Products',
            {'stock': item.isWeighted ? newStock : newStock.round()},
            where: 'id = ?',
            whereArgs: [item.product.id],
          );

          await txn.insert('StockAdjustments', {
            'product_id': item.product.id,
            'delta': item.isWeighted ? -deductAmount : -item.quantity,
            'resulting_stock': item.isWeighted ? newStock : newStock.round(),
            'reason': 'Sale #$saleId',
            'timestamp': now,
            'sale_id': saleId,
          });
        }
      }

      // 5. Update customer debt if applicable
      int? resultingCustomerBalance;
      if (resolvedCustomerId != null && debtAmount > 0) {
        final custRows = await txn.query('Customers', where: 'id = ?', whereArgs: [resolvedCustomerId]);
        final currentBal = (custRows.first['balance'] as int?) ?? 0;
        resultingCustomerBalance = currentBal + debtAmount;

        await txn.update(
          'Customers',
          {
            'balance': resultingCustomerBalance,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [resolvedCustomerId],
        );

        final note = cashTendered > 0
            ? 'POS Sale #$saleId (Short: ₱${(debtAmount / 100).toStringAsFixed(2)}, Paid: ₱${(cashTendered / 100).toStringAsFixed(2)})'
            : 'POS Sale #$saleId';

        await txn.insert('CustomerDebts', {
          'customer_id': resolvedCustomerId,
          'type': 'debt',
          'amount': debtAmount,
          'balance_after': resultingCustomerBalance,
          'notes': note,
          'sale_id': saleId,
          'timestamp': now,
        });
      }

      final change = cashTendered > totalCentavos ? (cashTendered - totalCentavos) : 0;

      return SaleReceipt(
        saleId: saleId,
        totalAmount: totalCentavos,
        items: receiptItems,
        paymentMethod: isDebt ? 'debt' : 'cash',
        tenderedAmount: tenderedAmount,
        changeAmount: change,
        debtorName: resolvedCustomerName,
        debtCharged: debtAmount > 0 ? debtAmount : null,
        debtBalance: resultingCustomerBalance,
        timestamp: now,
      );
    });
  }

  // --- DEBT MANAGEMENT ---

  Future<Map<String, dynamic>> getDebtsSummary() async {
    final rows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(balance), 0) AS total_unpaid_debts,
        COUNT(CASE WHEN balance > 0 THEN 1 END) AS active_debtors_count,
        COUNT(*) AS total_customers
      FROM Customers
      WHERE active = 1
    ''');

    final data = rows.first;
    return {
      'total_unpaid_debts': (data['total_unpaid_debts'] as int?) ?? 0,
      'active_debtors_count': (data['active_debtors_count'] as int?) ?? 0,
      'total_customers': (data['total_customers'] as int?) ?? 0,
    };
  }

  Future<List<Debtor>> getDebtors() async {
    final rows = await db.query(
      'Customers',
      where: 'active = ?',
      whereArgs: [1],
      orderBy: 'balance DESC, name ASC',
    );
    return rows.map((r) {
      final balance = (r['balance'] as int?) ?? 0;
      return Debtor(
        id: r['id'] as int,
        name: r['name'] as String,
        currentBalance: balance,
        activeDebt: balance > 0,
        createdAt: r['created_at'] as String?,
        updatedAt: r['updated_at'] as String?,
      );
    }).toList();
  }

  Future<Debtor> createDebtor(
    String name, {
    int initialDebtCentavos = 0,
    String? phone,
    String? notes,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('Customer name cannot be empty');
    if (initialDebtCentavos < 0) throw Exception('Initial debt cannot be negative');

    final now = DateTime.now().toIso8601String();

    return await db.transaction<Debtor>((txn) async {
      final id = await txn.insert('Customers', {
        'name': trimmed,
        'phone': phone?.trim(),
        'notes': notes?.trim(),
        'balance': initialDebtCentavos,
        'active': 1,
        'created_at': now,
        'updated_at': now,
      });

      if (initialDebtCentavos > 0) {
        final note = (notes != null && notes.trim().isNotEmpty)
            ? 'Initial borrowed balance: ${notes.trim()}'
            : 'Initial borrowed balance';

        await txn.insert('CustomerDebts', {
          'customer_id': id,
          'type': 'debt',
          'amount': initialDebtCentavos,
          'balance_after': initialDebtCentavos,
          'notes': note,
          'sale_id': null,
          'timestamp': now,
        });
      }

      return Debtor(
        id: id,
        name: trimmed,
        currentBalance: initialDebtCentavos,
        activeDebt: initialDebtCentavos > 0,
        createdAt: now,
        updatedAt: now,
      );
    });
  }

  Future<List<DebtTransaction>> getCustomerTransactions(int customerId) async {
    final rows = await db.query(
      'CustomerDebts',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'id DESC',
    );

    return rows.map((r) => DebtTransaction(
      id: r['id'] as int,
      customerId: r['customer_id'] as int,
      type: r['type'] as String,
      amount: r['amount'] as int,
      resultingBalance: r['balance_after'] as int,
      notes: r['notes'] as String?,
      saleId: r['sale_id'] as int?,
      createdAt: r['timestamp'] as String? ?? '',
    )).toList();
  }

  Future<Map<String, dynamic>> recordPayment(int customerId, int amountCentavos, {String? notes}) async {
    if (amountCentavos <= 0) {
      throw Exception('Payment amount must be greater than zero');
    }

    return await db.transaction<Map<String, dynamic>>((txn) async {
      final custRows = await txn.query(
        'Customers',
        where: 'id = ? AND active = ?',
        whereArgs: [customerId, 1],
      );
      if (custRows.isEmpty) throw Exception('Customer not found');

      final currentBalance = (custRows.first['balance'] as int?) ?? 0;
      if (amountCentavos > currentBalance) {
        throw Exception('Payment amount cannot exceed outstanding balance of ₱${(currentBalance / 100).toStringAsFixed(2)}');
      }

      final newBalance = currentBalance - amountCentavos;
      final now = DateTime.now().toIso8601String();

      await txn.update(
        'Customers',
        {
          'balance': newBalance,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );

      final debtId = await txn.insert('CustomerDebts', {
        'customer_id': customerId,
        'type': 'payment',
        'amount': amountCentavos,
        'balance_after': newBalance,
        'notes': (notes != null && notes.trim().isNotEmpty) ? notes.trim() : 'Debt payment',
        'timestamp': now,
      });

      return {
        'success': true,
        'transaction_id': debtId,
        'new_balance': newBalance,
      };
    });
  }

  // --- SALES HISTORY ---

  Future<Map<String, dynamic>> getSales({String? from, String? to, String? search, int page = 1}) async {
    const limit = 25;
    final offset = (page - 1) * limit;

    final List<String> conditions = [];
    final List<dynamic> whereArgs = [];

    if (from != null && from.trim().isNotEmpty) {
      conditions.add('s.timestamp >= ?');
      whereArgs.add(from.trim());
    }
    if (to != null && to.trim().isNotEmpty) {
      conditions.add('s.timestamp <= ?');
      whereArgs.add(to.trim());
    }

    if (search != null && search.trim().isNotEmpty) {
      final clean = search.trim().replaceAll('#', '').trim();
      final saleId = int.tryParse(clean);
      if (saleId != null) {
        // Exact receipt number matching (e.g. searching '1' only returns sale #1)
        conditions.add('(s.id = ? OR c.name LIKE ?)');
        whereArgs.addAll([saleId, '%$clean%']);
      } else {
        // Text search: matches customer name only (items removed as requested)
        conditions.add('c.name LIKE ?');
        whereArgs.add('%$clean%');
      }
    }

    final whereClause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    final query = '''
      SELECT 
        s.id, 
        s.timestamp, 
        s.total_amount, 
        s.payment_type,
        c.name AS customer_name,
        COUNT(si.id) AS item_count
      FROM Sales s
      LEFT JOIN SaleItems si ON si.sale_id = s.id
      LEFT JOIN Customers c ON c.id = s.customer_id
      $whereClause
      GROUP BY s.id
      ORDER BY s.id DESC
      LIMIT ? OFFSET ?
    ''';

    final args = [...whereArgs, limit + 1, offset];
    final rows = await db.rawQuery(query, args);

    final hasMore = rows.length > limit;
    final sales = rows.take(limit).map((r) => SalesSummary(
      id: r['id'] as int,
      timestamp: r['timestamp'] as String? ?? '',
      totalAmount: r['total_amount'] as int,
      itemCount: (r['item_count'] as int?) ?? 0,
      customerName: r['customer_name'] as String?,
      paymentType: r['payment_type'] as String?,
    )).toList();

    return {
      'sales': sales,
      'has_more': hasMore,
    };
  }

  Future<SaleReceipt> getReceipt(int saleId) async {
    final saleRows = await db.query('Sales', where: 'id = ?', whereArgs: [saleId]);
    if (saleRows.isEmpty) throw Exception('Receipt not found for sale #$saleId');

    final sale = saleRows.first;
    final itemRows = await db.query('SaleItems', where: 'sale_id = ?', whereArgs: [saleId], orderBy: 'id ASC');

    final items = itemRows.map((i) => SaleItem(
      productId: i['product_id'] as int,
      productName: i['product_name'] as String,
      barcodeString: i['barcode_string'] as String,
      quantity: i['quantity'] as int,
      weight: (i['weight'] as num?)?.toDouble(),
      unit: i['unit'] as String?,
      price: i['price'] as int,
      lineTotal: i['line_total'] as int,
    )).toList();

    String? customerName;
    int? customerBalance;
    int? debtAmount;
    final customerId = sale['customer_id'] as int?;

    if (customerId != null) {
      final custRows = await db.query('Customers', where: 'id = ?', whereArgs: [customerId]);
      if (custRows.isNotEmpty) {
        customerName = custRows.first['name'] as String?;
        customerBalance = custRows.first['balance'] as int?;
      }

      final debtRows = await db.query(
        'CustomerDebts',
        where: 'sale_id = ? AND type = ?',
        whereArgs: [saleId, 'debt'],
      );
      if (debtRows.isNotEmpty) {
        debtAmount = debtRows.first['amount'] as int?;
      }
    }

    final totalAmount = sale['total_amount'] as int;

    return SaleReceipt(
      saleId: saleId,
      totalAmount: totalAmount,
      items: items,
      paymentMethod: sale['payment_type'] as String?,
      debtorName: customerName,
      debtCharged: debtAmount,
      debtBalance: customerBalance,
      timestamp: sale['timestamp'] as String?,
    );
  }

  // --- HEALTH & STATS ---

  Future<Map<String, dynamic>> checkHealth() async {
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    final checkResult = integrity.isNotEmpty ? (integrity.first.values.first as String) : 'unknown';

    final productCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM Products WHERE active = 1')) ?? 0;
    final salesCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM Sales')) ?? 0;
    final customerCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM Customers WHERE active = 1')) ?? 0;
    final totalDebt = Sqflite.firstIntValue(await db.rawQuery('SELECT COALESCE(SUM(balance), 0) FROM Customers WHERE active = 1')) ?? 0;

    return {
      'status': checkResult == 'ok' ? 'Healthy' : 'Error',
      'integrity': checkResult,
      'product_count': productCount,
      'sales_count': salesCount,
      'customer_count': customerCount,
      'total_debt': totalDebt,
    };
  }

  // --- ANALYTICS DASHBOARD ---

  Future<AnalyticsData> getAnalytics({SalesTrendPeriod period = SalesTrendPeriod.days}) async {
    final now = DateTime.now();

    // Local day calculations
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    // Week start: Sunday (weekday in Dart is 1 = Monday ... 7 = Sunday; Sunday % 7 = 0)
    final daysSinceSunday = todayStart.weekday % 7;
    final weekStart = todayStart.subtract(Duration(days: daysSinceSunday));

    // Month start: 1st day of month
    final monthStart = DateTime(now.year, now.month, 1);

    // Year start: Jan 1
    final yearStart = DateTime(now.year, 1, 1);

    // 1. Calculate KPI Totals
    final todayTotal = await _sumSalesBetween(todayStart.toIso8601String(), tomorrowStart.toIso8601String());
    final weekTotal = await _sumSalesBetween(weekStart.toIso8601String(), tomorrowStart.toIso8601String());
    final monthTotal = await _sumSalesBetween(monthStart.toIso8601String(), tomorrowStart.toIso8601String());
    final yearTotal = await _sumSalesBetween(yearStart.toIso8601String(), tomorrowStart.toIso8601String());

    final kpis = AnalyticsKpis(
      today: todayTotal,
      week: weekTotal,
      month: monthTotal,
      year: yearTotal,
    );

    // 2. Popular Items (Top 5 by quantity sold)
    final popularRows = await db.rawQuery('''
      SELECT 
        product_name AS name,
        SUM(quantity) AS times_sold,
        SUM(line_total) AS revenue
      FROM SaleItems
      GROUP BY product_id, product_name
      ORDER BY times_sold DESC, name ASC
      LIMIT 5
    ''');

    final popularItems = popularRows.map((r) => PopularItem(
      name: r['name'] as String? ?? 'Unknown Item',
      timesSold: (r['times_sold'] as num?)?.toInt() ?? 0,
      revenue: (r['revenue'] as num?)?.toInt() ?? 0,
    )).toList();

    // 3. Sales Trend Chart
    final chartData = await getSalesTrend(period);

    return AnalyticsData(
      kpis: kpis,
      popularItems: popularItems,
      chartData: chartData,
    );
  }

  Future<ChartData> getSalesTrend(SalesTrendPeriod period) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    switch (period) {
      case SalesTrendPeriod.days:
        final dates = List.generate(7, (i) {
          final d = todayStart.subtract(Duration(days: 6 - i));
          return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        });

        final sevenDaysStart = '${dates.first}T00:00:00';
        final chartRows = await db.rawQuery('''
          SELECT 
            substr(timestamp, 1, 10) AS sale_date,
            SUM(total_amount) AS total
          FROM Sales
          WHERE timestamp >= ? AND timestamp < ?
          GROUP BY sale_date
        ''', [sevenDaysStart, tomorrowStart.toIso8601String()]);

        final Map<String, int> dailyTotals = {};
        for (final r in chartRows) {
          final date = r['sale_date'] as String?;
          if (date != null) {
            dailyTotals[date] = (r['total'] as num?)?.toInt() ?? 0;
          }
        }

        return ChartData(
          period: SalesTrendPeriod.days,
          labels: dates,
          data: dates.map((d) => dailyTotals[d] ?? 0).toList(),
        );

      case SalesTrendPeriod.week:
        final daysSinceSunday = todayStart.weekday % 7;
        final currentWeekStart = todayStart.subtract(Duration(days: daysSinceSunday));

        final weekStarts = List.generate(7, (i) {
          return currentWeekStart.subtract(Duration(days: 7 * (6 - i)));
        });
        final rangeStart = weekStarts.first.toIso8601String();

        final chartRows = await db.rawQuery('''
          SELECT 
            timestamp,
            total_amount
          FROM Sales
          WHERE timestamp >= ? AND timestamp < ?
        ''', [rangeStart, tomorrowStart.toIso8601String()]);

        final weekTotals = List.filled(7, 0);
        for (final r in chartRows) {
          final ts = r['timestamp'] as String?;
          final total = (r['total_amount'] as num?)?.toInt() ?? 0;
          if (ts == null) continue;
          final dt = DateTime.tryParse(ts);
          if (dt == null) continue;

          for (int i = 0; i < 7; i++) {
            final start = weekStarts[i];
            final end = i < 6 ? weekStarts[i + 1] : tomorrowStart;
            if (!dt.isBefore(start) && dt.isBefore(end)) {
              weekTotals[i] += total;
              break;
            }
          }
        }

        final labels = weekStarts.map((w) => '${w.month}/${w.day}').toList();

        return ChartData(
          period: SalesTrendPeriod.week,
          labels: labels,
          data: weekTotals,
        );

      case SalesTrendPeriod.months:
        final monthStarts = List.generate(6, (i) {
          final monthOffset = 5 - i;
          return DateTime(now.year, now.month - monthOffset, 1);
        });
        final rangeStart = monthStarts.first.toIso8601String();
        final nextMonthStart = DateTime(now.year, now.month + 1, 1).toIso8601String();

        final chartRows = await db.rawQuery('''
          SELECT 
            substr(timestamp, 1, 7) AS month_key,
            SUM(total_amount) AS total
          FROM Sales
          WHERE timestamp >= ? AND timestamp < ?
          GROUP BY month_key
        ''', [rangeStart, nextMonthStart]);

        final Map<String, int> monthTotals = {};
        for (final r in chartRows) {
          final key = r['month_key'] as String?;
          if (key != null) {
            monthTotals[key] = (r['total'] as num?)?.toInt() ?? 0;
          }
        }

        final monthKeys = monthStarts.map((d) {
          return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
        }).toList();

        const monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final labels = monthStarts.map((d) => monthNames[d.month]).toList();

        return ChartData(
          period: SalesTrendPeriod.months,
          labels: labels,
          data: monthKeys.map((k) => monthTotals[k] ?? 0).toList(),
        );

      case SalesTrendPeriod.year:
        final years = List.generate(5, (i) => now.year - (4 - i));
        final rangeStart = DateTime(years.first, 1, 1).toIso8601String();
        final nextYearStart = DateTime(now.year + 1, 1, 1).toIso8601String();

        final chartRows = await db.rawQuery('''
          SELECT 
            substr(timestamp, 1, 4) AS year_key,
            SUM(total_amount) AS total
          FROM Sales
          WHERE timestamp >= ? AND timestamp < ?
          GROUP BY year_key
        ''', [rangeStart, nextYearStart]);

        final Map<String, int> yearTotals = {};
        for (final r in chartRows) {
          final key = r['year_key'] as String?;
          if (key != null) {
            yearTotals[key] = (r['total'] as num?)?.toInt() ?? 0;
          }
        }

        final labels = years.map((y) => y.toString()).toList();

        return ChartData(
          period: SalesTrendPeriod.year,
          labels: labels,
          data: labels.map((y) => yearTotals[y] ?? 0).toList(),
        );
    }
  }

  Future<int> _sumSalesBetween(String start, String end) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount), 0) AS total FROM Sales WHERE timestamp >= ? AND timestamp < ?',
      [start, end],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<void> resetToSampleData() async {
    await db.transaction((txn) async {
      await txn.delete('CustomerDebts');
      await txn.delete('StockAdjustments');
      await txn.delete('SaleItems');
      await txn.delete('Sales');
      await txn.delete('Customers');
      await txn.delete('Products');
      await _seedDefaultData(txn);
    });
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
