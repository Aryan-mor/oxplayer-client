import 'package:flutter/material.dart';

bool isEditableTextFocused() {
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null) return false;
  final ctx = focus.context;
  // Primary focus can briefly reference a defunct element during focus churn;
  // reading ctx.widget then throws (Element._widget is cleared on unmount).
  if (ctx == null || !ctx.mounted) return false;

  if (ctx.widget is EditableText) return true;
  return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}
