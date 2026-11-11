import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../theme/evolup_theme.dart';

/// A Polomix reply rendered from Markdown (bold, italic, headings, lists,
/// quotes, code) in the current EVOLUP palette, selectable as a whole.
///
/// The reply comes from an AI model, so nothing in it is fetched or opened:
/// images only show their alternative text, links are plain text, and raw
/// HTML is never interpreted. Line breaks are kept as written.
class CoachMarkdown extends StatelessWidget {
  const CoachMarkdown(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: MarkdownBody(
      data: data,
      softLineBreak: true,
      blockSyntaxes: const [_HtmlBlockAsText()],
      styleSheet: coachMarkdownStyle(Theme.of(context)),
      imageBuilder: (uri, title, alt) => Text(
        alt ?? title ?? '',
        style: TextStyle(color: EvolupColors.of(context).textSecondary),
      ),
    ),
  );
}

/// Shows an HTML block of the reply as plain text in its own paragraph,
/// instead of silently dropping it (inline HTML already stays as text).
class _HtmlBlockAsText extends md.HtmlBlockSyntax {
  const _HtmlBlockAsText();

  @override
  md.Node parse(md.BlockParser parser) =>
      md.Element('p', [md.Text(super.parse(parser).textContent.trimRight())]);
}

/// Markdown styles matching the chat bubbles: same body text as before,
/// headings a little larger than the body, discreet code and quotes.
MarkdownStyleSheet coachMarkdownStyle(ThemeData theme) {
  final colors = theme.extension<EvolupColors>() ?? EvolupColors.brand;
  final body = (theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16))
      .copyWith(color: colors.textPrimary);
  final size = body.fontSize ?? 16;
  TextStyle heading(double scale) => body.copyWith(
    fontSize: size * scale,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );
  final panel = BoxDecoration(
    color: colors.fieldFill,
    border: Border.all(color: colors.glassBorder),
    borderRadius: BorderRadius.circular(10),
  );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    // Links are not opened: they look like the surrounding text.
    a: body,
    strong: const TextStyle(fontWeight: FontWeight.w700),
    em: const TextStyle(fontStyle: FontStyle.italic),
    del: const TextStyle(decoration: TextDecoration.lineThrough),
    h1: heading(1.375),
    h2: heading(1.25),
    h3: heading(1.125),
    h4: heading(1),
    h5: heading(1),
    h6: heading(1),
    h1Padding: const EdgeInsets.only(top: 4),
    h2Padding: const EdgeInsets.only(top: 4),
    h3Padding: const EdgeInsets.only(top: 2),
    listBullet: body,
    listIndent: 22,
    blockSpacing: 10,
    code: body.copyWith(
      fontFamily: 'monospace',
      fontSize: size * 0.875,
      backgroundColor: colors.fieldFill,
    ),
    codeblockPadding: const EdgeInsets.all(10),
    codeblockDecoration: panel,
    blockquote: body.copyWith(color: colors.textSecondary),
    blockquotePadding: const EdgeInsets.only(left: 12),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: colors.accent, width: 3)),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.glassBorder)),
    ),
    tableHead: const TextStyle(fontWeight: FontWeight.w700),
    tableBody: body,
    tableBorder: TableBorder.all(color: colors.glassBorder),
  );
}
