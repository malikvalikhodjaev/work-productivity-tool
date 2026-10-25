import 'package:flutter/material.dart';

/// Full label above an independently scrollable, readable problem text.
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
    final lineHeight = MediaQuery.textScalerOf(context).scale(14) * 1.4;
    return Semantics(
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Tooltip(
            message: '$title · записать / уточнить',
            child: TextButton(
              onPressed: edit,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xffd0dad5),
                disabledForegroundColor: const Color(0xffd0dad5),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                minimumSize: const Size(48, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: Theme.of(context).textTheme.labelMedium!
                    .copyWith(fontSize: 13),
              ),
              child: Text(label, softWrap: true),
            ),
          ),
          const SizedBox(height: 2),
          ConstrainedBox(
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
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
