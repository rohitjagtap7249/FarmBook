import 'package:flutter/material.dart';

import 'chemical_picker.dart';
import 'helpers.dart';
import 'stock_data.dart';

/// Asks for a quantity with a compatible unit. Returns the value converted
/// into [stockUnit], or null if cancelled.
Future<double?> _askQuantity(
  BuildContext context, {
  required String title,
  required String stockUnit,
  String hint = 'Quantity',
  double? initial,
  bool allowZero = false,
}) async {
  final options = StockUnits.options(stockUnit);
  final ctrl = TextEditingController(
    text: initial == null ? '' : formatNumber(initial),
  );
  var unit = options.first;
  final result = await showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(title),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: hint),
              ),
            ),
            const SizedBox(width: 10),
            DropdownButton<String>(
              value: unit,
              items: [
                for (final o in options)
                  DropdownMenuItem(value: o, child: Text(o)),
              ],
              onChanged: (v) => setLocal(() => unit = v ?? unit),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v == null || v < 0 || (!allowZero && v == 0)) return;
              Navigator.pop(ctx, StockUnits.convert(v, unit, stockUnit));
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return result;
}

class ChemicalStockPage extends StatefulWidget {
  const ChemicalStockPage({super.key});

  @override
  State<ChemicalStockPage> createState() => _ChemicalStockPageState();
}

class _ChemicalStockPageState extends State<ChemicalStockPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await StockStore.items();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _trackChemical() async {
    final chemicals = await StockStore.untrackedChemicals();
    if (!mounted) return;
    if (chemicals.isEmpty) {
      _msg('All chemicals are already tracked. Add chemicals in the Chemicals tab first.');
      return;
    }
    Map<String, dynamic> selected = chemicals.first;
    final openCtrl = TextEditingController();
    final minCtrl = TextEditingController();
    var openUnit = StockUnits.options(selected['unit'].toString()).first;
    var minUnit = openUnit;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final stockUnit = selected['unit'].toString();
          final options = StockUnits.options(stockUnit);
          if (!options.contains(openUnit)) openUnit = options.first;
          if (!options.contains(minUnit)) minUnit = options.first;
          return AlertDialog(
            title: const Text('Track a chemical'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PickerField(
                    label: 'Chemical',
                    value: selected['name'].toString(),
                    onTap: () async {
                      final name = await pickFromList(
                        ctx,
                        title: 'Choose chemical',
                        items: [for (final c in chemicals) c['name'].toString()],
                        selected: selected['name'].toString(),
                      );
                      if (name == null) return;
                      setLocal(() {
                        selected = chemicals.firstWhere(
                          (c) => c['name'].toString() == name,
                          orElse: () => selected,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: openCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Opening stock',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      DropdownButton<String>(
                        value: openUnit,
                        items: [
                          for (final o in options)
                            DropdownMenuItem(value: o, child: Text(o)),
                        ],
                        onChanged: (v) =>
                            setLocal(() => openUnit = v ?? openUnit),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Low-stock level (optional)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      DropdownButton<String>(
                        value: minUnit,
                        items: [
                          for (final o in options)
                            DropdownMenuItem(value: o, child: Text(o)),
                        ],
                        onChanged: (v) =>
                            setLocal(() => minUnit = v ?? minUnit),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Only sprays and drips you record from now on will use '
                    'this stock. Old records are never deducted.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Start tracking'),
              ),
            ],
          );
        },
      ),
    );

    final stockUnit = selected['unit'].toString();
    final opening = StockUnits.convert(
      double.tryParse(openCtrl.text.trim()) ?? 0,
      openUnit,
      stockUnit,
    );
    final min = StockUnits.convert(
      double.tryParse(minCtrl.text.trim()) ?? 0,
      minUnit,
      stockUnit,
    );
    openCtrl.dispose();
    minCtrl.dispose();

    if (ok != true) return;
    await StockStore.startTracking(
      name: selected['name'].toString(),
      unit: stockUnit,
      openingQty: opening,
      minQty: min,
    );
    await _load();
  }

  Future<void> _showDetail(Map<String, dynamic> item) async {
    final name = item['chemical_name'].toString();
    final unit = item['unit'].toString();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'In stock: ${StockUnits.format((item['balance'] as num).toDouble(), unit)}',
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.add_shopping_cart),
                title: const Text('Add purchase'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final q = await _askQuantity(
                    context,
                    title: 'Purchase — $name',
                    stockUnit: unit,
                  );
                  if (q == null) return;
                  await StockStore.addPurchase(
                    name: name,
                    qty: q,
                    date: DateTime.now(),
                  );
                  await _load();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Correct stock'),
                subtitle: const Text('Set the actual quantity you have now.'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final q = await _askQuantity(
                    context,
                    title: 'Actual stock — $name',
                    stockUnit: unit,
                    hint: 'Quantity now',
                    allowZero: true,
                  );
                  if (q == null) return;
                  await StockStore.correctBalance(name: name, actualQty: q);
                  await _load();
                },
              ),
              ListTile(
                leading: const Icon(Icons.notification_important_outlined),
                title: const Text('Low-stock level'),
                subtitle: Text(
                  (item['min_qty'] as num) > 0
                      ? StockUnits.format(
                          (item['min_qty'] as num).toDouble(),
                          unit,
                        )
                      : 'Not set',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final q = await _askQuantity(
                    context,
                    title: 'Low-stock level — $name',
                    stockUnit: unit,
                    hint: 'Minimum quantity',
                    allowZero: true,
                  );
                  if (q == null) return;
                  await StockStore.setMinQty(name, q);
                  await _load();
                },
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('History'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _showHistory(name, unit);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Stop tracking'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final sure = await showDialog<bool>(
                    context: context,
                    builder: (dctx) => AlertDialog(
                      title: Text('Stop tracking $name?'),
                      content: const Text(
                        'Its stock history will be removed. Your spray and '
                        'drip records are not affected.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dctx, true),
                          child: const Text('Stop'),
                        ),
                      ],
                    ),
                  );
                  if (sure != true) return;
                  await StockStore.stopTracking(name);
                  await _load();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHistory(String name, String unit) async {
    final rows = await StockStore.movements(name);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No stock movements yet.'),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final r in rows)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${_kindLabel(r['kind'].toString())}: '
                          '${(r['qty'] as num) >= 0 ? '+' : '−'}'
                          '${StockUnits.format((r['qty'] as num).abs().toDouble(), unit)}',
                        ),
                        subtitle: Text(
                          formatDate(
                            DateTime.tryParse(r['moved_at'].toString()) ??
                                DateTime.now(),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'opening':
        return 'Opening stock';
      case 'purchase':
        return 'Purchase';
      case 'use':
        return 'Used in record';
      case 'adjust':
        return 'Correction';
      default:
        return kind;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chemical Stock')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _trackChemical,
        icon: const Icon(Icons.add),
        label: const Text('Track chemical'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: Text(
                      'Stock tracking is optional. Tap “Track chemical” to '
                      'start with an opening stock. Only new sprays and drips '
                      'will be deducted.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  children: [for (final item in _items) _tile(item)],
                ),
    );
  }

  Widget _tile(Map<String, dynamic> item) {
    final unit = item['unit'].toString();
    final balance = (item['balance'] as num).toDouble();
    final min = (item['min_qty'] as num).toDouble();
    final price = (item['price'] as num).toDouble();
    final low = min > 0 && balance <= min;
    return Card(
      child: ListTile(
        title: Text(item['chemical_name'].toString()),
        subtitle: Text(
          '${StockUnits.format(balance, unit)}'
          '${price > 0 ? '  •  ≈ ${fbMoney(balance * price)}' : ''}'
          '${low ? '  •  Low stock' : ''}',
          style: TextStyle(color: low ? Colors.red.shade700 : null),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showDetail(item),
      ),
    );
  }
}
