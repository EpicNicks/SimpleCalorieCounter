import 'package:flutter/material.dart';

import '../dto/CustomSymbolEntry.dart';

class SymbolBoldingTextEditingController extends TextEditingController {
  final List<CustomSymbolEntry> userSymbols;
  int commentIndex; // no longer final: gets refreshed after edits settle
  bool isEditing; // set true on focus gained, false on focus lost

  SymbolBoldingTextEditingController({
    required this.userSymbols,
    required this.commentIndex,
    this.isEditing = false,
  });

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;

    // No comment marker (-1) means the whole string is treated as code.
    final int effectiveCommentIndex = (commentIndex < 0 || commentIndex > text.length) ? text.length : commentIndex;

    RegExp? regex;
    if (userSymbols.isNotEmpty) {
      final sortedSymbols = [...userSymbols]..sort((a, b) => b.name.length.compareTo(a.name.length));
      final pattern = sortedSymbols.map((s) => RegExp.escape(s.name)).join('|');
      regex = RegExp(pattern);
    }

    void addStyledRange(List<TextSpan> spans, int start, int end, bool isBold) {
      if (start >= end) return;

      // Only apply italics if not currently editing.
      final bool applyItalics = !isEditing;
      final splitPoint = effectiveCommentIndex.clamp(start, end);

      void emit(int s, int e, bool italic) {
        if (s >= e) return;
        spans.add(TextSpan(
          text: text.substring(s, e),
          style: (style ?? const TextStyle()).copyWith(
            fontWeight: isBold ? FontWeight.bold : style?.fontWeight,
            fontStyle: (italic && applyItalics) ? FontStyle.italic : style?.fontStyle,
          ),
        ));
      }

      if (start < effectiveCommentIndex) {
        emit(start, splitPoint, false);
      }
      if (end > effectiveCommentIndex) {
        emit(splitPoint, end, true);
      }
    }

    final spans = <TextSpan>[];

    // Only search for symbol matches in the non-comment portion of the text.
    final String codePortion = text.substring(0, effectiveCommentIndex);
    final matches = regex?.allMatches(codePortion) ?? const <RegExpMatch>[];

    int last = 0;
    for (final match in matches) {
      if (match.start > last) {
        addStyledRange(spans, last, match.start, false);
      }
      addStyledRange(spans, match.start, match.end, true);
      last = match.end;
    }

    if (last < text.length) {
      addStyledRange(spans, last, text.length, false);
    }

    return TextSpan(children: spans, style: style);
  }
}
