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

final _rowRe = RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
final _cellRe = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', caseSensitive: false, dotAll: true);
final _headingRe =
    RegExp(r'<(h[1-6]|strong|b)[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true);
final _labelValueRe = RegExp(r'^([^:]{2,40}):\s+(.+)$');

/// Splits Cyclos rich text (HTML) into headings, paragraphs and
/// label/value rows, so script results read like a receipt.
List<RichBlock> parseRichContent(String html) {
  final out = <RichBlock>[];

  void addText(String segment) {
    // Headings first (whole-line <h*>, <strong>, <b>).
    var rest = segment;
    for (final m in _headingRe.allMatches(segment)) {
      final before = segment.substring(0, m.start);
      final onlyTagsBefore = htmlToText(before).isEmpty;
      if (onlyTagsBefore) {
        final h = htmlToText(m.group(2) ?? '');
        if (h.isNotEmpty) out.add(RichHeading(h));
        rest = segment.substring(m.end);
      }
      break;
    }
    for (final line in htmlToText(rest).split('\n')) {
      final l = line.trim();
      if (l.isEmpty) continue;
      final lv = _labelValueRe.firstMatch(l);
      if (lv != null) {
        out.add(RichRow(lv.group(1)!.trim(), lv.group(2)!.trim()));
      } else {
        out.add(RichParagraph(l));
      }
    }
  }

  var pos = 0;
  for (final m in _rowRe.allMatches(html)) {
    addText(html.substring(pos, m.start).replaceAll(RegExp(r'</?(table|tbody|thead)[^>]*>', caseSensitive: false), ''));
    final cells = _cellRe
        .allMatches(m.group(1) ?? '')
        .map((c) => htmlToText(c.group(1) ?? '').replaceAll('\n', ' ').trim())
        .where((c) => c.isNotEmpty)
        .toList();
    if (cells.length >= 2) {
      out.add(RichRow(cells.first, cells.skip(1).join(' ')));
    } else if (cells.length == 1) {
      out.add(RichParagraph(cells.first));
    }
    pos = m.end;
  }
  addText(html.substring(pos).replaceAll(RegExp(r'</?(table|tbody|thead)[^>]*>', caseSensitive: false), ''));
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
