import 'package:flutter/material.dart';

import 'tokens.dart';

/// 电量小电池（竖版，AppBar 摘要行内用）：描边外壳 + 顶部正极头，
/// 内部按电量百分比从底部向上连续填充，整体绿色。
class BatteryLevel extends StatelessWidget {
  const BatteryLevel({super.key, required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(10, 18),
      painter: _BatteryPainter(percent / 100),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.ratio);

  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    const body = Rect.fromLTWH(0.75, 2.55, 8.5, 14.7);
    final paint = Paint()..color = AppColors.success;

    // 顶部正极凸头。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.2, 0, 3.6, 1.8),
        const Radius.circular(0.9),
      ),
      paint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(2.2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.success,
    );

    // 内部填充高度随电量变化，贴底向上，四周留出描边内边距。
    const inset = 2.0;
    final fillH = (body.height - inset * 2) * ratio.clamp(0.0, 1.0);
    if (fillH > 0.5) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            body.left + inset,
            body.bottom - inset - fillH,
            body.width - inset * 2,
            fillH,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter oldDelegate) =>
      oldDelegate.ratio != ratio;
}
