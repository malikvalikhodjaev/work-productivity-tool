import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class InlineCell extends StatefulWidget {
  final String text, label;
  final String? displayText;
  final int maxLines;
  final Future<void> Function(String) commit;
  final ValueChanged<String>? retain;
  final VoidCallback? begin, cancel;
  final String? draft;
  const InlineCell({
    super.key,
    required this.text,
    required this.label,
    required this.commit,
    this.displayText,
    this.retain,
    this.draft,
    this.begin,
    this.cancel,
    this.maxLines = 1,
  });
  @override
  State<InlineCell> createState() => _InlineCellState();
}

class _InlineCellState extends State<InlineCell> {
  final focus = FocusNode();
  TextEditingController? controller;
  bool editing = false, saving = false;
  String? error;
  void begin() {
    widget.begin?.call();
    controller?.dispose();
    controller = TextEditingController(text: widget.draft ?? widget.text);
    setState(() {
      editing = true;
      error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus.requestFocus();
    });
  }

  Future<void> save({bool next = false, bool previous = false}) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.commit(controller!.text);
      if (!mounted) return;
      setState(() {
        editing = false;
        saving = false;
      });
      if (next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          focus.requestFocus();
          previous ? focus.previousFocus() : focus.nextFocus();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is StateError
              ? e.message.toString()
              : e is FormatException
              ? e.message
              : e.toString().replaceFirst(
                  RegExp(r'^(Exception: |Bad state: |FormatException: )'),
                  '',
                );
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!editing) {
      return TextButton(
        focusNode: focus,
        onPressed: begin,
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        ),
        child: Text(
          widget.displayText ??
              (widget.text.isEmpty ? 'Заполнить' : widget.text),
          softWrap: true,
        ),
      );
    }
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          widget.cancel?.call();
          setState(() => editing = false);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.tab) {
          save(next: true, previous: HardwareKeyboard.instance.isShiftPressed);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            HardwareKeyboard.instance.isControlPressed) {
          save();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            focusNode: focus,
            readOnly: saving,
            minLines: 1,
            maxLines: widget.maxLines,
            decoration: InputDecoration(
              labelText: widget.label,
              error: error == null
                  ? null
                  : Text(
                      error!,
                      key: const ValueKey('inline-cell-error'),
                      softWrap: true,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
              helperText: widget.maxLines == 1
                  ? 'Enter — сохранить · Esc — отменить'
                  : 'Переносы строк сохраняются',
            ),
            onChanged: widget.retain,
            onSubmitted: widget.maxLines == 1 ? (_) => save() : null,
          ),
          Wrap(
            children: [
              TextButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Сохраняю…' : 'Сохранить'),
              ),
              TextButton(
                onPressed: saving
                    ? null
                    : () {
                        widget.cancel?.call();
                        setState(() => editing = false);
                      },
                child: const Text('Отмена'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    focus.dispose();
    super.dispose();
  }
}
