// ignore_for_file: overridden_fields
import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'tokens.dart';

/// Markdown 集中式主题（源项目同款结构，配色映射到本项目 #3D9AFF 色系）。
/// 纪要/顿悟类 Markdown 一律传此 config，保证样式统一。
class MarkdownThemeConfigOwn {
  MarkdownThemeConfigOwn._();

  static MarkdownConfig get ownStyle => MarkdownConfig(
        configs: [
          // 普通段落文本
          const PConfig(
            textStyle: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: AppColors.ink,
            ),
          ),
          const CustomH1Config(),
          const CustomH2Config(),
          const CustomH3Config(),
          // > 引用
          const BlockquoteConfig(
            padding: EdgeInsets.fromLTRB(14, 10, 12, 10),
          ),
          // 无序/有序列表
          const ListConfig(marginLeft: 20),
          // 行内代码
          const CodeConfig(
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: AppColors.primaryDark,
              backgroundColor: AppColors.fill,
            ),
          ),
          // 多行代码块
          PreConfig(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              height: 1.6,
              fontFamily: 'monospace',
              color: AppColors.ink,
            ),
          ),
          // 水平分割线
          HrConfig(height: 1, color: AppColors.borderStrong),
          // 表格：所有列均分宽度，不做横向滚动
          const TableConfig(
            defaultColumnWidth: FlexColumnWidth(1),
            headerStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
            bodyStyle: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      );
}

class CustomH1Config extends H1Config {
  const CustomH1Config({
    this.style = const TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1,
      color: AppColors.ink,
    ),
  });

  @override
  final TextStyle style;

  @override
  HeadingDivider? get divider =>
      HeadingDivider(height: 1, color: AppColors.border);
}

class CustomH2Config extends H2Config {
  const CustomH2Config({
    this.style = const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1,
      color: AppColors.ink,
    ),
  });

  @override
  final TextStyle style;

  @override
  HeadingDivider? get divider =>
      HeadingDivider(height: 1, color: AppColors.border);
}

class CustomH3Config extends H3Config {
  const CustomH3Config({
    this.style = const TextStyle(
      fontSize: 15.5,
      fontWeight: FontWeight.w600,
      height: 1,
      color: AppColors.inkSoft,
    ),
  });

  @override
  final TextStyle style;

  @override
  HeadingDivider? get divider =>
      HeadingDivider(height: 1, color: AppColors.border);
}
