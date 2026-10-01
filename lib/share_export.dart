import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as im;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'database.dart';
import 'helpers.dart';


/// Indian digit grouping like the sample: ₹6,76,200 (paise only if present).
String _money(double v) {
  final neg = v < 0;
  final abs = v.abs();
  final whole = abs.floor();
  var paise = ((abs - whole) * 100).round();
  var w = whole;
  if (paise == 100) {
    w += 1;
    paise = 0;
  }
  final digits = w.toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final tail = digits.substring(digits.length - 3);
    var head = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) parts.insert(0, head);
    grouped = '${parts.join(',')},$tail';
  }
  final frac = paise == 0 ? '' : '.${paise.toString().padLeft(2, '0')}';
  return '${neg ? '-' : ''}₹$grouped$frac';
}

class _Section {
  _Section(this.title, this.total, this.rows);
  final String title;
  final double total;
  final List<List<String>> rows; // [date, description, amount]
}

class _OverviewData {
  _OverviewData({
    required this.plotTitle,
    required this.subtitle,
    required this.totals,
    required this.hasEarnings,
    required this.sections,
  });
  final String plotTitle;
  final String subtitle;
  final Map<String, double> totals;
  final bool hasEarnings;
  final List<_Section> sections;
}

String _d(dynamic v) {
  final dt = DateTime.tryParse(v.toString());
  return dt == null ? v.toString() : formatDate(dt);
}

Future<_OverviewData> _collect({
  required int plotId,
  required String plotTitle,
  required String plotName,
  required String cropVariety,
}) async {
  final db = AppDatabase.instance;
  final totals = await db.plotTotals(plotId);
  final earnings = await db.getEarnings(plotId);

  final sprayRows = <List<String>>[];
  for (final s in await db.getSpraysForPlot(plotId)) {
    final chems = await db.getSprayChemicals(s['id'] as int);
    sprayRows.add([
      _d(s['spray_date']),
      chems.isEmpty
          ? 'Spray'
          : chems.map((c) => c['chemical_name'].toString()).join(', '),
      _money((s['total_cost'] as num).toDouble()),
    ]);
  }

  final dripRows = <List<String>>[];
  for (final r in await db.getDripApplicationsForPlot(plotId)) {
    final chems = await db.getDripChemicals(r['id'] as int);
    dripRows.add([
      _d(r['drip_date']),
      chems.isEmpty
          ? 'Drip'
          : chems.map((c) => c['chemical_name'].toString()).join(', '),
      _money((r['total_cost'] as num).toDouble()),
    ]);
  }

  final labourRows = <List<String>>[
    for (final r in await db.getLabour(plotId))
      [
        _d(r['labour_date']),
        '${r['work_type']} (${formatNumber((r['worker_count'] as num).toDouble())} workers)',
        _money((r['total_cost'] as num).toDouble()),
      ],
  ];

  final otherRows = <List<String>>[
    for (final r in await db.getOtherExpenses(plotId))
      [
        _d(r['expense_date']),
        '${r['category']} - ${r['description']}',
        _money((r['amount'] as num).toDouble()),
      ],
  ];

  final earningRows = <List<String>>[
    for (final r in earnings)
      [
        _d(r['earning_date']),
        r['description'].toString(),
        _money((r['amount'] as num).toDouble()),
      ],
  ];

  return _OverviewData(
    plotTitle: plotTitle,
    subtitle: [
      if (plotName.trim().isNotEmpty) plotName.trim(),
      if (cropVariety.trim().isNotEmpty) cropVariety.trim(),
    ].join(' • '),
    totals: totals,
    hasEarnings: earnings.isNotEmpty,
    sections: [
      _Section('Spray', totals['spray'] ?? 0, sprayRows),
      _Section('Drip / Irrigation', totals['drip'] ?? 0, dripRows),
      _Section('Labour', totals['labour'] ?? 0, labourRows),
      _Section('Other Expenses', totals['other'] ?? 0, otherRows),
      _Section('Earnings', totals['earnings'] ?? 0, earningRows),
    ],
  );
}

/// Palette taken from the approved "expense summary" sample layout.
const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);
const Color _rule = Color(0xFF1F86B8);
const Color _accent = Color(0xFF0E6E9E);
const Color _pageBg = Color(0xFFF8FAFC);
const Color _stripe = Color(0xFFF1F5F9);
const Color _totalBg = Color(0xFFEAF6FD);
const Color _cellText = Color(0xFF1E293B);
const Color _cellSoft = Color(0xFF475569);

/// Draws overview pages with the canvas so any script (Marathi, Hindi…)
/// and the ₹ sign render correctly using the phone's own fonts.
class _Doc {
  _Doc({required this.width, this.pageHeight});

  final double width;
  final double? pageHeight;
  static const double margin = 84;

  final List<ui.Image> images = [];
  late ui.PictureRecorder _rec;
  late Canvas c;
  double y = 90;

  double get left => margin;
  double get right => width - margin;
  double get inner => right - left;

  void begin() {
    _rec = ui.PictureRecorder();
    c = Canvas(_rec);
    y = 90;
    c.drawRect(
      Rect.fromLTWH(0, 0, width, pageHeight ?? 9000),
      Paint()..color = _pageBg,
    );
  }

  Future<void> endPage() async {
    final picture = _rec.endRecording();
    final h = pageHeight ?? (y + 110);
    images.add(await picture.toImage(width.toInt(), h.ceil()));
  }

  TextPainter _tp(
    String s,
    double size,
    FontWeight w,
    Color color,
    double maxWidth, {
    double spacing = 0,
  }) {
    return TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          fontWeight: w,
          color: color,
          letterSpacing: spacing,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
  }

  /// Draws text at (x, top). Returns the painted height.
  double put(
    String s,
    double x,
    double top, {
    double size = 28,
    FontWeight weight = FontWeight.normal,
    Color color = _cellText,
    double maxWidth = 600,
    double spacing = 0,
  }) {
    final tp = _tp(s, size, weight, color, maxWidth, spacing: spacing);
    tp.paint(c, Offset(x, top));
    return tp.height;
  }

  /// Draws text whose right edge sits at [rightX].
  void putRight(
    String s,
    double rightX,
    double top, {
    double size = 28,
    FontWeight weight = FontWeight.normal,
    Color color = _cellText,
    double maxWidth = 400,
  }) {
    final tp = _tp(s, size, weight, color, maxWidth);
    tp.paint(c, Offset(rightX - tp.width, top));
  }

  void rect(double x, double top, double w, double h, Color color,
      {double radius = 0}) {
    final r = Rect.fromLTWH(x, top, w, h);
    if (radius > 0) {
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)),
          Paint()..color = color);
    } else {
      c.drawRect(r, Paint()..color = color);
    }
  }

  bool needsPage(double h) =>
      pageHeight != null && y + h > pageHeight! - 110;
}

// Column layout of the summary table (matches the sample).
const double _colAmountRight = 640;
const double _colDetailX = 690;

void _tableHeader(_Doc d, List<String> titles, {bool threeCols = true}) {
  const h = 72.0;
  d.rect(d.left, d.y, d.inner, h, _ink);
  const sz = 25.0;
  const sp = 1.2;
  final top = d.y + (h - 30) / 2;
  d.put(titles[0], d.left + 28, top,
      size: sz, weight: FontWeight.w800, color: Colors.white, spacing: sp, maxWidth: 380);
  d.putRight(titles[1], _colAmountRight, top,
      size: sz, weight: FontWeight.w800, color: Colors.white);
  if (threeCols) {
    d.put(titles[2], _colDetailX, top,
        size: sz,
        weight: FontWeight.w800,
        color: Colors.white,
        spacing: sp,
        maxWidth: d.right - _colDetailX - 20);
  }
  d.y += h;
}

String _recordsText(int n) => n == 1 ? '1 record' : '$n records';

Future<void> _drawSummary(_Doc d, _OverviewData data, {required bool pdf}) async {
  // Title block
  d.put(data.plotTitle, d.left, d.y,
      size: 58, weight: FontWeight.w800, color: _ink, maxWidth: d.inner);
  d.y += 74;
  d.put(
    data.subtitle.isEmpty
        ? 'Overview & Total Expenditure'
        : '${data.subtitle}  •  Overview',
    d.left,
    d.y,
    size: 29,
    color: _muted,
    maxWidth: d.inner,
  );
  d.y += 52;
  d.rect(d.left, d.y, d.inner, 4, _rule);
  d.y += 44;

  // Total card
  const cardH = 190.0;
  d.rect(d.left, d.y, d.inner, cardH, Colors.white, radius: 22);
  d.c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(d.left, d.y, d.inner, cardH),
      const Radius.circular(22),
    ),
    Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  final profit = data.totals['profit'] ?? 0;
  final profitColor = !data.hasEarnings
      ? _muted
      : (profit >= 0 ? Colors.green.shade700 : Colors.red.shade700);
  final colW = (d.inner - 60) / 3;
  final xs = [d.left + 30, d.left + 30 + colW, d.left + 30 + colW * 2];
  final labels = [
    'TOTAL EXPENSE',
    'TOTAL EARNINGS',
    data.hasEarnings ? (profit >= 0 ? 'PROFIT' : 'LOSS') : 'PROFIT / LOSS',
  ];
  final values = [
    _money(data.totals['expense'] ?? 0),
    data.hasEarnings ? _money(data.totals['earnings'] ?? 0) : '—',
    data.hasEarnings ? _money(profit.abs()) : '—',
  ];
  final colors = [_accent, _ink, profitColor];
  for (var i = 0; i < 3; i++) {
    d.put(labels[i], xs[i], d.y + 36,
        size: 22, weight: FontWeight.w800, color: _muted, spacing: 1.4, maxWidth: colW - 10);
    d.put(values[i], xs[i], d.y + 80,
        size: 44, weight: FontWeight.w800, color: colors[i], maxWidth: colW - 10);
  }
  d.y += cardH + 36;

  // Category table
  _tableHeader(d, ['CATEGORY', 'TOTAL AMOUNT', 'DETAILS / NOTES']);
  var i = 0;
  const rowH = 84.0;
  void row(String cat, double amount, String detail) {
    d.rect(d.left, d.y, d.inner, rowH, i.isEven ? Colors.white : _stripe);
    final top = d.y + (rowH - 34) / 2;
    d.put(cat, d.left + 28, top,
        size: 28, weight: FontWeight.w700, color: _cellText, maxWidth: 380);
    d.putRight(_money(amount), _colAmountRight, top,
        size: 28, color: _cellSoft);
    d.put(detail, _colDetailX, top,
        size: 28, color: _cellSoft, maxWidth: d.right - _colDetailX - 20);
    d.y += rowH;
    i++;
  }

  for (final sec in data.sections.take(4)) {
    row(sec.title, sec.total, _recordsText(sec.rows.length));
  }

  void highlight(String label, String amount, Color color) {
    d.rect(d.left, d.y, d.inner, 3, const Color(0xFFBBE0F2));
    d.rect(d.left, d.y + 3, d.inner, rowH - 3, _totalBg);
    final top = d.y + (rowH - 34) / 2 + 2;
    d.put(label, d.left + 28, top,
        size: 29, weight: FontWeight.w800, color: color, maxWidth: 380);
    d.putRight(amount, _colAmountRight, top,
        size: 29, weight: FontWeight.w800, color: color);
    d.y += rowH;
  }

  highlight('Total Expense', _money(data.totals['expense'] ?? 0), _accent);
  final earn = data.sections.last;
  row(earn.title, earn.total, _recordsText(earn.rows.length));
  highlight(
    data.hasEarnings ? (profit >= 0 ? 'Profit' : 'Loss') : 'Profit / Loss',
    data.hasEarnings ? _money(profit.abs()) : '—',
    data.hasEarnings ? profitColor : _muted,
  );

  d.y += 46;
  d.putRight('', d.right, d.y);
  final foot = 'Generated on ${_monthYear(DateTime.now())} • FarmBook Records';
  final tp = TextPainter(
    text: TextSpan(
      text: foot,
      style: const TextStyle(fontSize: 24, color: Color(0xFF94A3B8)),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: d.inner);
  tp.paint(d.c, Offset((d.width - tp.width) / 2, d.y));
  d.y += tp.height;
}

String _monthYear(DateTime dt) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${months[dt.month - 1]} ${dt.year}';
}

Future<void> _drawDetails(_Doc d, _OverviewData data) async {
  for (final sec in data.sections) {
    if (sec.rows.isEmpty) continue;
    if (d.needsPage(260)) {
      await d.endPage();
      d.begin();
    } else {
      d.y += 56;
    }
    d.put(sec.title, d.left, d.y,
        size: 40, weight: FontWeight.w800, color: _ink, maxWidth: d.inner - 300);
    d.putRight(_money(sec.total), d.right, d.y + 4,
        size: 34, weight: FontWeight.w800, color: _accent);
    d.y += 64;
    d.rect(d.left, d.y, d.inner, 3, _rule);
    d.y += 22;
    _tableHeader(d, ['DATE', 'AMOUNT', 'DETAILS']);
    var i = 0;
    for (final r in sec.rows) {
      const rowH = 76.0;
      if (d.needsPage(rowH)) {
        await d.endPage();
        d.begin();
        _tableHeader(d, ['DATE', 'AMOUNT', 'DETAILS']);
      }
      d.rect(d.left, d.y, d.inner, rowH, i.isEven ? Colors.white : _stripe);
      final top = d.y + (rowH - 32) / 2;
      d.put(r[0], d.left + 28, top,
          size: 26, weight: FontWeight.w700, color: _cellText, maxWidth: 400);
      d.putRight(r[2], _colAmountRight, top, size: 26, color: _cellSoft);
      d.put(r[1], _colDetailX, top,
          size: 26, color: _cellSoft, maxWidth: d.right - _colDetailX - 20);
      d.y += rowH;
      i++;
    }
  }
}

Future<Uint8List> _png(ui.Image img) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Single tall image of the overview, encoded as JPG.
Future<File> buildOverviewJpg({
  required int plotId,
  required String plotTitle,
  required String plotName,
  required String cropVariety,
}) async {
  final data = await _collect(
    plotId: plotId,
    plotTitle: plotTitle,
    plotName: plotName,
    cropVariety: cropVariety,
  );
  final doc = _Doc(width: 1080);
  doc.begin();
  await _drawSummary(doc, data, pdf: false);
  await doc.endPage();
  final png = await _png(doc.images.first);
  final decoded = im.decodePng(png);
  if (decoded == null) throw StateError('Could not create image.');
  final jpg = im.encodeJpg(decoded, quality: 92);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/${_safeName(plotTitle)}_overview.jpg');
  await file.writeAsBytes(jpg, flush: true);
  return file;
}

/// Structured PDF: summary page followed by the detailed records.
Future<File> buildOverviewPdf({
  required int plotId,
  required String plotTitle,
  required String plotName,
  required String cropVariety,
}) async {
  final data = await _collect(
    plotId: plotId,
    plotTitle: plotTitle,
    plotName: plotName,
    cropVariety: cropVariety,
  );
  final doc = _Doc(width: 1080, pageHeight: 1527);
  doc.begin();
  await _drawSummary(doc, data, pdf: true);
  await _drawDetails(doc, data);
  await doc.endPage();

  final pdf = pw.Document();
  for (final img in doc.images) {
    final bytes = await _png(img);
    final mem = pw.MemoryImage(bytes);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(mem, fit: pw.BoxFit.fill),
      ),
    );
  }
  final out = await pdf.save();
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/${_safeName(plotTitle)}_report.pdf');
  await file.writeAsBytes(out, flush: true);
  return file;
}

String _safeName(String s) {
  final cleaned = s.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  return 'FarmBook_${cleaned.isEmpty ? 'plot' : cleaned}';
}

/// Bottom sheet offering Image (JPG), PDF and the existing data export.
Future<void> showPlotShareSheet(
  BuildContext context, {
  required int plotId,
  required String plotTitle,
  required String plotName,
  required String cropVariety,
  required VoidCallback onExportData,
}) async {
  Future<void> run(Future<File> Function() build, String mime) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Preparing…'), duration: Duration(seconds: 2)),
    );
    try {
      final file = await build();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: mime)],
        text: 'FarmBook — $plotTitle',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not share: $e')));
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Share as image (JPG)'),
            subtitle: const Text('Clean snapshot for WhatsApp and more.'),
            onTap: () {
              Navigator.pop(ctx);
              run(
                () => buildOverviewJpg(
                  plotId: plotId,
                  plotTitle: plotTitle,
                  plotName: plotName,
                  cropVariety: cropVariety,
                ),
                'image/jpeg',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Share as PDF report'),
            subtitle: const Text('Overview plus detailed records.'),
            onTap: () {
              Navigator.pop(ctx);
              run(
                () => buildOverviewPdf(
                  plotId: plotId,
                  plotTitle: plotTitle,
                  plotName: plotName,
                  cropVariety: cropVariety,
                ),
                'application/pdf',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.data_object),
            title: const Text('Export plot data (JSON)'),
            subtitle: const Text('Same as before.'),
            onTap: () {
              Navigator.pop(ctx);
              onExportData();
            },
          ),
        ],
      ),
    ),
  );
}
