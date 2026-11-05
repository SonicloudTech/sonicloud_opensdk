import 'package:flutter/material.dart';

class DemoLogHeader extends StatelessWidget {
  final int lineCount;
  final bool autoScroll;
  final ValueChanged<bool> onAutoScrollChanged;
  final VoidCallback onClear;
  final VoidCallback onCopy;

  const DemoLogHeader({
    super.key,
    required this.lineCount,
    required this.autoScroll,
    required this.onAutoScrollChanged,
    required this.onClear,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final actionStyle = TextButton.styleFrom(
      backgroundColor: const Color(0xFF3A4057),
      foregroundColor: const Color(0xFFC0D3FF),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A3C),
        border: Border(bottom: BorderSide(color: Color(0xFF3A3A4F))),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 14, color: Color(0xFF8A8AA0)),
          const SizedBox(width: 6),
          const Text(
            '日志',
            style: TextStyle(
              color: Color(0xFFCDCDDA),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 3,
                children: [
                  const Text(
                    '自动滚底',
                    style: TextStyle(color: Color(0xFFB8BDD0), fontSize: 11),
                  ),
                  SizedBox(
                    width: 32,
                    height: 28,
                    child: FittedBox(
                      child: Switch(
                        value: autoScroll,
                        onChanged: onAutoScrollChanged,
                        activeTrackColor: const Color(0xFF3A7AFE),
                        inactiveTrackColor: const Color(0xFF45455A),
                        thumbColor: const WidgetStatePropertyAll(Colors.white),
                        trackOutlineColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  TextButton(
                    style: actionStyle,
                    onPressed: onClear,
                    child: const Text('清屏'),
                  ),
                  TextButton(
                    style: actionStyle,
                    onPressed: onCopy,
                    child: const Text('复制log'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A4F),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$lineCount 行',
              style: const TextStyle(color: Color(0xFF9A9AB0), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
