import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/cyclos/cyclos_operations_api.dart';
import 'widgets.dart';

/// A piece of a Cyclos rich-text result.
sealed class RichBlock {
  const RichBlock();
}

class RichHeading extends RichBlock {
  const RichHeading(this.text);
  final String text;
}

class RichParagraph extends RichBlock {
  const RichParagraph(this.text);
  final String text;
}

/// A label/value line (from a two-cell table row or "Label: value").
class RichRow extends RichBlock {
  const RichRow(this.label, this.value);
  final String label;
  final String value;
}

/// A real table (3+ columns, or one with a header row).
class RichTable extends RichBlock {
  const RichTable(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;
}

RegExp _ci(String p) => RegExp(p, caseSensitive: false, dotAll: true);
final _rowRe = _ci(r'<tr\b[^>]*>(.*?)</tr\s*>');
final _cellRe = _ci(r'<(t[dh])\b[^>]*>(.*?)</\1\s*>');
final _tableRe = _ci(r'<table\b[^>]*>(.*?)</table\s*>');
// "Label: value", "Label : value" (French spacing) or "Label:value"; the
// label must contain a letter so times like "12:30" stay plain text.
final _labelValueRe = RegExp(r'^([^:]{1,40}?)\s*:\s*(\S.*)$');
final _hasLetter = RegExp(r'[A-Za-zÀ-ÿ]');

// Markers that survive htmlToText (control characters, never in content).
const _hMark = '\u0001'; // heading line
const _bOpen = '\u0002'; // <b>/<strong> start
const _bClose = '\u0003'; // <b>/<strong> end
const _tMark = '\u0004'; // table placeholder
const _sep = '\u001F'; // between side-by-side inline elements

String _cellText(String html) => htmlToText(html).replaceAll('\n', ' ').trim();

List<RichBlock> _parseTable(String inner) {
  final hasHead = RegExp(r'<thead\b', caseSensitive: false).hasMatch(inner);
  final rows = <List<String>>[];
  var headers = <String>[];
  var first = true;
  for (final r in _rowRe.allMatches(inner)) {
    final cells = _cellRe.allMatches(r.group(1) ?? '').toList();
    if (cells.isEmpty) continue;
    final texts = [for (final c in cells) _cellText(c.group(2) ?? '')];
    final allTh = cells.every((c) => c.group(1)!.toLowerCase() == 'th');
    if (first && (allTh || hasHead) && texts.length > 1) {
      headers = texts;
    } else if (texts.any((t) => t.isNotEmpty)) {
      rows.add(texts);
    }
    first = false;
  }
  final cols = [headers.length, ...rows.map((r) => r.length)].fold<int>(0, (a, b) => a > b ? a : b);
  if (cols <= 2 && headers.isEmpty) {
    // Two cells per row: a receipt-style label/value list.
    return [
      for (final r in rows)
        if (r.where((c) => c.isNotEmpty).length >= 2)
          RichRow(r.first, r.skip(1).join(' '))
        else
          RichParagraph(r.firstWhere((c) => c.isNotEmpty)),
    ];
  }
  return [RichTable(headers, rows)];
}

/// Splits Cyclos rich text (HTML) into headings, paragraphs, label/value
/// rows and tables, so script results read like a receipt. Styles,
/// scripts and comments are dropped.
List<RichBlock> parseRichContent(String html) {
  var s = html
      .replaceAll(_ci(r'<!--.*?-->'), '')
      .replaceAll(_ci(r'<(style|script|head|title)\b[^>]*>.*?</\1\s*>'), '');

  final tables = <List<RichBlock>>[];
  s = s.replaceAllMapped(_tableRe, (m) {
    tables.add(_parseTable(m.group(1) ?? ''));
    return '\n$_tMark${tables.length - 1}$_tMark\n';
  });

  // <span>Application ID</span><span>APP-1</span> -> two parts, not "IDAPP-1".
  s = s.replaceAllMapped(
      _ci(r'(</(?:span|b|strong|em|i|label|small|a|dt|dd|code)\s*>)\s*(?=<(?:span|b|strong|em|i|label|small|a|dt|dd|code)\b)'),
      (m) => '${m.group(1)}$_sep');
  s = s.replaceAllMapped(_ci(r'<h[1-6]\b[^>]*>(.*?)</h[1-6]\s*>'),
      (m) => '\n$_hMark${m.group(1)}\n');
  s = s.replaceAllMapped(_ci(r'<(b|strong)\b[^>]*>(.*?)</\1\s*>'),
      (m) => '$_bOpen${m.group(2)}$_bClose');

  final out = <RichBlock>[];
  final wholeBold = RegExp('^$_bOpen([^$_bOpen$_bClose]*)$_bClose\$');
  for (final raw in htmlToText(s).split('\n')) {
    var l = raw.trim();
    if (l.isEmpty) continue;

    final t = RegExp('$_tMark(\\d+)$_tMark').firstMatch(l);
    if (t != null) {
      out.addAll(tables[int.parse(t.group(1)!)]);
      continue;
    }
    if (l.startsWith(_hMark)) {
      final h = l.replaceAll(RegExp('[$_hMark$_bOpen$_bClose$_sep]'), ' ').trim();
      if (h.isNotEmpty) out.add(RichHeading(h.replaceAll(RegExp(r'\s+'), ' ')));
      continue;
    }
    final wb = wholeBold.firstMatch(l);
    if (wb != null && !wb.group(1)!.trim().endsWith(':')) {
      out.add(RichHeading(wb.group(1)!.trim()));
      continue;
    }
    l = l.replaceAll(RegExp('[$_bOpen$_bClose]'), '');

    if (l.contains(_sep)) {
      final parts = l.split(_sep).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      if (parts.length == 2 && parts.first.length <= 40) {
        out.add(RichRow(parts.first.replaceAll(RegExp(r'\s*:$'), ''), parts.last));
        continue;
      }
      l = parts.join(parts.length > 2 ? ' · ' : ' ');
      if (l.isEmpty) continue;
    }

    final lv = _labelValueRe.firstMatch(l);
    if (lv != null &&
        _hasLetter.hasMatch(lv.group(1)!) &&
        !lv.group(2)!.startsWith('//') &&
        // "12:30" is a time, not "label: value".
        !(RegExp(r'\d$').hasMatch(lv.group(1)!) && RegExp(r'^\d').hasMatch(lv.group(2)!))) {
      out.add(RichRow(lv.group(1)!.trim(), lv.group(2)!.trim()));
    } else {
      out.add(RichParagraph(l));
    }
  }
  return out;
}

/// Renders parsed rich content: paragraphs as text, consecutive rows grouped
/// in a card of label/value lines.
class RichContentView extends StatelessWidget {
  const RichContentView({super.key, required this.blocks});
  final List<RichBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var rows = <RichRow>[];

    void flushRows() {
      if (rows.isEmpty) return;
      children.add(Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [for (final r in rows) SummaryRow(r.label, r.value)]),
        ),
      ));
      children.add(const SizedBox(height: 12));
      rows = <RichRow>[];
    }

    for (final b in blocks) {
      switch (b) {
        case RichRow():
          rows.add(b);
        case RichHeading(:final text):
          flushRows();
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ));
        case RichTable():
          flushRows();
          children.add(_TableCard(table: b));
          children.add(const SizedBox(height: 12));
        case RichParagraph(:final text):
          flushRows();
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(text, style: const TextStyle(height: 1.45, color: AppColors.ink)),
          ));
      }
    }
    flushRows();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// Wide tables scroll sideways inside a card instead of squashing columns.
class _TableCard extends StatelessWidget {
  const _TableCard({required this.table});
  final RichTable table;

  @override
  Widget build(BuildContext context) {
    final cols = [table.headers.length, ...table.rows.map((r) => r.length)]
        .fold<int>(0, (a, b) => a > b ? a : b);
    List<String> pad(List<String> r) => [...r, for (var i = r.length; i < cols; i++) ''];
    final headers = table.headers.isEmpty ? List.filled(cols, '') : pad(table.headers);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: table.headers.isEmpty ? 0 : 44,
          dataRowMinHeight: 40,
          dataRowMaxHeight: double.infinity,
          columnSpacing: 20,
          horizontalMargin: 16,
          headingTextStyle: const TextStyle(
              fontWeight: FontWeight.w700, color: AppColors.muted, fontSize: 13),
          columns: [for (final h in headers) DataColumn(label: Text(h))],
          rows: [
            for (final r in table.rows)
              DataRow(cells: [
                for (final c in pad(r))
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(c),
                  )),
              ]),
          ],
        ),
      ),
    );
  }
}
