class Product {
  final int id;
  final String barcodeString;
  final String name;
  final int priceCentavos;
  final int? stock;
  final int? reorderLevel;
  final int active;

  Product({
    required this.id,
    required this.barcodeString,
    required this.name,
    required this.priceCentavos,
    this.stock,
    this.reorderLevel,
    this.active = 1,
  });

  double get pricePesos => priceCentavos / 100.0;
  String get formattedPrice => '₱${pricePesos.toStringAsFixed(2)}';

  bool get isLowStock =>
      stock != null && reorderLevel != null && stock! <= reorderLevel!;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      barcodeString: json['barcode_string'] as String,
      name: json['name'] as String,
      priceCentavos: json['price'] as int,
      stock: json['stock'] as int?,
      reorderLevel: json['reorder_level'] as int?,
      active: (json['active'] as int?) ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'barcode_string': barcodeString,
      'name': name,
      'price': priceCentavos,
      'stock': stock,
      'reorder_level': reorderLevel,
      'active': active,
    };
  }
}

class CartItem {
  final Product product;
  int quantity;

  CartItem({
    required this.product,
    this.quantity = 1,
  });

  int get lineTotalCentavos => product.priceCentavos * quantity;
  double get lineTotalPesos => lineTotalCentavos / 100.0;
  String get formattedLineTotal => '₱${lineTotalPesos.toStringAsFixed(2)}';
}

class Debtor {
  final int id;
  final String name;
  final int currentBalance;
  final bool activeDebt;
  final String? createdAt;
  final String? updatedAt;

  Debtor({
    required this.id,
    required this.name,
    required this.currentBalance,
    required this.activeDebt,
    this.createdAt,
    this.updatedAt,
  });

  double get balancePesos => currentBalance / 100.0;
  String get formattedBalance => '₱${balancePesos.toStringAsFixed(2)}';

  factory Debtor.fromJson(Map<String, dynamic> json) {
    final balance = json['current_balance'] as int? ?? 0;
    return Debtor(
      id: json['id'] as int,
      name: json['name'] as String,
      currentBalance: balance,
      activeDebt: (json['active_debt'] as bool?) ?? (balance > 0),
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }
}

class DebtTransaction {
  final int id;
  final int customerId;
  final String type; // 'debt' or 'payment'
  final int amount; // in centavos
  final int resultingBalance; // in centavos
  final String? notes;
  final int? saleId;
  final String createdAt;

  DebtTransaction({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amount,
    required this.resultingBalance,
    this.notes,
    this.saleId,
    required this.createdAt,
  });

  double get amountPesos => amount / 100.0;
  double get resultingBalancePesos => resultingBalance / 100.0;
  String get formattedAmount => '₱${amountPesos.toStringAsFixed(2)}';
  String get formattedResultingBalance =>
      '₱${resultingBalancePesos.toStringAsFixed(2)}';

  bool get isPayment => type == 'payment';

  factory DebtTransaction.fromJson(Map<String, dynamic> json) {
    return DebtTransaction(
      id: json['id'] as int,
      customerId: (json['customer_id'] as int?) ?? 0,
      type: json['type'] as String,
      amount: json['amount'] as int,
      resultingBalance: json['resulting_balance'] as int,
      notes: json['notes'] as String?,
      saleId: json['sale_id'] as int?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class StockMovement {
  final int id;
  final int delta;
  final int resultingStock;
  final String reason;
  final int? saleId;
  final String timestamp;

  StockMovement({
    required this.id,
    required this.delta,
    required this.resultingStock,
    required this.reason,
    this.saleId,
    required this.timestamp,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      id: json['id'] as int,
      delta: json['delta'] as int,
      resultingStock: json['resulting_stock'] as int,
      reason: json['reason'] as String? ?? '',
      saleId: json['sale_id'] as int?,
      timestamp: json['timestamp'] as String? ?? '',
    );
  }
}

class SaleItem {
  final int productId;
  final String productName;
  final String barcodeString;
  final int quantity;
  final int price; // centavos
  final int lineTotal; // centavos

  SaleItem({
    required this.productId,
    required this.productName,
    required this.barcodeString,
    required this.quantity,
    required this.price,
    required this.lineTotal,
  });

  double get pricePesos => price / 100.0;
  double get lineTotalPesos => lineTotal / 100.0;

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      productId: json['product_id'] as int,
      productName: json['product_name'] as String,
      barcodeString: json['barcode_string'] as String,
      quantity: json['quantity'] as int,
      price: json['price'] as int,
      lineTotal: json['line_total'] as int,
    );
  }
}

class SaleReceipt {
  final int saleId;
  final int totalAmount; // centavos
  final List<SaleItem> items;
  final String? paymentMethod;
  final int? tenderedAmount; // centavos
  final int? changeAmount; // centavos
  final String? debtorName;
  final int? debtCharged; // centavos
  final int? debtBalance; // centavos
  final String? timestamp;

  SaleReceipt({
    required this.saleId,
    required this.totalAmount,
    required this.items,
    this.paymentMethod,
    this.tenderedAmount,
    this.changeAmount,
    this.debtorName,
    this.debtCharged,
    this.debtBalance,
    this.timestamp,
  });

  double get totalPesos => totalAmount / 100.0;
  String get formattedTotal => '₱${totalPesos.toStringAsFixed(2)}';

  factory SaleReceipt.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return SaleReceipt(
      saleId: (json['sale_id'] ?? json['id']) as int,
      totalAmount: json['total_amount'] as int,
      items: rawItems
          .map((i) => SaleItem.fromJson(i as Map<String, dynamic>))
          .toList(),
      paymentMethod: json['payment_method'] as String?,
      tenderedAmount: json['tendered_amount'] as int?,
      changeAmount: json['change'] as int?,
      debtorName: json['debtor_name'] as String?,
      debtCharged: json['debt_charged'] as int?,
      debtBalance: json['debt_balance'] as int?,
      timestamp: json['timestamp'] as String?,
    );
  }
}

class SalesSummary {
  final int id;
  final String timestamp;
  final int totalAmount; // centavos
  final int itemCount;

  SalesSummary({
    required this.id,
    required this.timestamp,
    required this.totalAmount,
    required this.itemCount,
  });

  double get totalPesos => totalAmount / 100.0;
  String get formattedTotal => '₱${totalPesos.toStringAsFixed(2)}';

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    return SalesSummary(
      id: json['id'] as int,
      timestamp: json['timestamp'] as String? ?? '',
      totalAmount: json['total_amount'] as int,
      itemCount: (json['item_count'] as int?) ?? 0,
    );
  }
}
