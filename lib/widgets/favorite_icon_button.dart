import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/loopi_colors.dart';

class FavoriteButton extends StatefulWidget {
  const FavoriteButton({
    super.key,
    required this.initialValue,
    required this.onChanged,
    this.tooltip,
  });

  final bool initialValue;
  final FutureOr<void> Function(bool value) onChanged;
  final String? tooltip;

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  late bool _isFavorite = widget.initialValue;

  @override
  void didUpdateWidget(covariant FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _isFavorite = widget.initialValue;
    }
  }

  void _toggle() {
    final next = !_isFavorite;
    setState(() => _isFavorite = next);
    unawaited(Future<void>.sync(() => widget.onChanged(next)));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _toggle,
      tooltip: widget.tooltip ?? (_isFavorite ? '즐겨찾기 해제' : '즐겨찾기'),
      color: _isFavorite ? LoopiColors.purple : null,
      icon: Icon(_isFavorite ? Icons.bookmark : Icons.bookmark_border),
    );
  }
}
