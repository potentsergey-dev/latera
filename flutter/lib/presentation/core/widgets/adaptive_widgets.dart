import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';

import '../platform_info.dart';

/// Адаптивная кнопка: FilledButton (Material) / fluent.FilledButton (Windows).
class AdaptiveFilledButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;

  const AdaptiveFilledButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isWindows) {
      return fluent.FilledButton(
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 8)],
            child,
          ],
        ),
      );
    }

    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: icon!,
        label: child,
      );
    }
    return FilledButton(onPressed: onPressed, child: child);
  }
}

/// Адаптивная outlined-кнопка.
class AdaptiveOutlinedButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;

  const AdaptiveOutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isWindows) {
      return fluent.Button(
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 8)],
            child,
          ],
        ),
      );
    }

    if (icon != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon!,
        label: child,
      );
    }
    return OutlinedButton(onPressed: onPressed, child: child);
  }
}

/// Адаптивная текстовая кнопка.
class AdaptiveTextButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;

  const AdaptiveTextButton({
    super.key,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isWindows) {
      return fluent.HyperlinkButton(
        onPressed: onPressed,
        child: child,
      );
    }
    return TextButton(onPressed: onPressed, child: child);
  }
}

/// Адаптивное текстовое поле.
class AdaptiveTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int? maxLines;
  final int? minLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  const AdaptiveTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.minLines,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isWindows) {
      return fluent.TextBox(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        prefix: prefixIcon != null
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: prefixIcon,
              )
            : null,
        suffix: suffixIcon,
        maxLines: maxLines,
        minLines: minLines,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        autofocus: autofocus,
      );
    }

    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      minLines: minLines,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      autofocus: autofocus,
      decoration: InputDecoration(
        hintText: placeholder,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
      ),
    );
  }
}

/// Адаптивный переключатель (toggle).
class AdaptiveToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final String? subtitle;
  final Widget? leading;

  const AdaptiveToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
    this.subtitle,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isWindows) {
      return fluent.ListTile.selectable(
        leading: leading,
        title: label != null ? Text(label!) : null,
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: fluent.ToggleSwitch(
          checked: value,
          onChanged: onChanged,
        ),
        selected: false,
      );
    }

    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: label != null ? Text(label!) : null,
      subtitle: subtitle != null ? Text(subtitle!) : null,
      secondary: leading,
    );
  }
}

/// Адаптивный CircularProgressIndicator.
class AdaptiveProgressRing extends StatelessWidget {
  final double? value;
  final double strokeWidth;

  const AdaptiveProgressRing({
    super.key,
    this.value,
    this.strokeWidth = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isWindows) {
      return fluent.ProgressRing(value: value != null ? value! * 100 : null);
    }

    return CircularProgressIndicator(
      value: value,
      strokeWidth: strokeWidth,
    );
  }
}

/// Адаптивный линейный прогресс-бар.
class AdaptiveProgressBar extends StatelessWidget {
  final double? value;

  const AdaptiveProgressBar({super.key, this.value});

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isWindows) {
      return fluent.ProgressBar(value: value != null ? value! * 100 : null);
    }

    return LinearProgressIndicator(value: value);
  }
}

/// Адаптивная карточка.
class AdaptiveCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;

  const AdaptiveCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isWindows) {
      return fluent.Card(
        padding: padding ?? const EdgeInsets.all(16),
        backgroundColor: backgroundColor,
        child: child,
      );
    }

    return Card(
      elevation: 0,
      color: backgroundColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

/// Адаптивный InfoBar / SnackBar.
///
/// Утилитный метод для показа уведомлений.
void showAdaptiveInfoBar(
  BuildContext context, {
  required String message,
  bool isError = false,
}) {
  if (PlatformInfo.isWindows) {
    fluent.displayInfoBar(context, builder: (context, close) {
      return fluent.InfoBar(
        title: Text(message),
        severity: isError ? fluent.InfoBarSeverity.error : fluent.InfoBarSeverity.info,
        onClose: close,
      );
    });
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
    ),
  );
}
