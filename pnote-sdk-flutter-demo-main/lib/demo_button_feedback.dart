import 'dart:async';

import 'package:flutter/material.dart';

Widget demoButtonFeedback(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => _ButtonFeedback(
  enabled: !states.contains(WidgetState.disabled),
  child: child ?? const SizedBox.shrink(),
);

class _ButtonFeedback extends StatefulWidget {
  const _ButtonFeedback({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_ButtonFeedback> createState() => _ButtonFeedbackState();
}

class _ButtonFeedbackState extends State<_ButtonFeedback> {
  bool _pressed = false;
  Timer? _timer;

  void _highlight(PointerDownEvent event) {
    if (!widget.enabled) return;
    _timer?.cancel();
    setState(() => _pressed = true);
    _timer = Timer(const Duration(milliseconds: 200), () {
      setState(() => _pressed = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _highlight,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_pressed)
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  key: ValueKey('demo-button-feedback'),
                  color: Color(0x33000000),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
