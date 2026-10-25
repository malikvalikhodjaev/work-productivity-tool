import 'package:flutter/material.dart';

/// The label stays beside the text, outside its scroll viewport. Each problem
/// has room for at least a complete first line, independently of the other one.
class FocusProblemLine extends StatelessWidget {
  final String kind, label, title, text;
  final int visibleLines;
  final VoidCallback? edit;
  const FocusProblemLine({
    super.key,
    required this.kind,
    required this.label,
    required this.title,
    required this.text,
    required this.visibleLines,
    this.edit,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: Colors.white, fontSize: 14, height: 1.4);
    final lineHeight = MediaQuery.textScalerOf(context).scale(14) * 1.4;
    final labelStyle = Theme.of(context).textTheme.labelMedium!
        .copyWith(fontSize: 13);
    final labelPainter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final labelWidth = labelPainter.width + 4 > 66
        ? labelPainter.width + 4
        : 66.0;
    labelPainter.dispose();
    return Semantics(
      label: title,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Tooltip(
              message: '$title · записать / уточнить',
              child: TextButton(
                onPressed: edit,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xffd0dad5),
                  disabledForegroundColor: const Color(0xffd0dad5),
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  minimumSize: Size(
                    48,
                    lineHeight + 2 < 24 ? 24 : lineHeight + 2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: labelStyle,
                ),
                child: Text(label, softWrap: true),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: lineHeight * visibleLines + 2,
              ),
              child: Scrollbar(
                child: SingleChildScrollView(
                  key: ValueKey('focus-problem-$kind-scroll'),
                  primary: false,
                  child: Text(
                    text,
                    key: ValueKey('focus-problem-$kind-text'),
                    style: style,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
