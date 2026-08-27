import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../theme/loopi_colors.dart';

String defaultRoutineName([DateTime? now]) {
  final date = now ?? DateTime.now();
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d Routine';
}

/// Shows the Save Routine Preset modal. Returns a trimmed name, or null if closed.
Future<String?> showSaveRoutineDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dialogContext) {
      return PointerInterceptor(
        child: SaveRoutineDialog(dialogContext: dialogContext),
      );
    },
  );
}

class SaveRoutineDialog extends StatefulWidget {
  const SaveRoutineDialog({super.key, this.dialogContext});

  final BuildContext? dialogContext;

  @override
  State<SaveRoutineDialog> createState() => _SaveRoutineDialogState();
}

class _SaveRoutineDialogState extends State<SaveRoutineDialog> {
  late final String _suggestedName;
  late final TextEditingController _routineNameController;
  late final FocusNode _focusNode;
  bool _clearedOnFirstFocus = false;

  BuildContext get _dialogContext => widget.dialogContext ?? context;

  @override
  void initState() {
    super.initState();
    _suggestedName = defaultRoutineName();
    _routineNameController = TextEditingController(text: _suggestedName);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && !_clearedOnFirstFocus) {
      _clearedOnFirstFocus = true;
      _routineNameController.clear();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _routineNameController.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(_dialogContext).pop();
  }

  void _save() {
    final typed = _routineNameController.text.trim();
    Navigator.of(_dialogContext).pop(typed.isEmpty ? _suggestedName : typed);
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Save Routine Preset',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: LoopiColors.ink,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Name this loop routine before starting Practice Mode.',
                  style: TextStyle(color: LoopiColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _routineNameController,
                  focusNode: _focusNode,
                  enabled: true,
                  autofocus: false,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [LengthLimitingTextInputFormatter(80)],
                  onChanged: (value) => setDialogState(() {}),
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: 'Routine name',
                    hintText: _suggestedName,
                    filled: true,
                    fillColor: LoopiColors.canvas,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: LoopiColors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: LoopiColors.purple, width: 1.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: _close,
              style: OutlinedButton.styleFrom(
                foregroundColor: LoopiColors.ink,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                side: const BorderSide(color: LoopiColors.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: LoopiColors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}
