import 'package:flutter/material.dart';

import 'package:fladder/models/items/media_streams_model.dart';

/// Matches API `media-source-stub.ts` `OX_MEDIA_SOURCE_CAPTION_SEP` in `MediaSourceInfo.Name`.
const kOxMediaSourceCaptionSeparator = '\u241f';

({String qualityLabel, String? telegramCaption}) parseOxMediaSourceNameParts(String? rawName) {
  final raw = rawName ?? '';
  final i = raw.indexOf(kOxMediaSourceCaptionSeparator);
  if (i < 0) {
    return (qualityLabel: raw, telegramCaption: null);
  }
  final q = raw.substring(0, i).trim();
  final cap = raw.substring(i + kOxMediaSourceCaptionSeparator.length).trim();
  return (qualityLabel: q, telegramCaption: cap.isEmpty ? null : cap);
}

/// Quality / version name + optional Telegram caption (caption below, left-aligned).
Widget oxVersionQualityAndCaptionLabel(
  BuildContext context,
  VersionStreamModel v, {
  TextStyle? titleStyle,
}) {
  final cap = v.oxTelegramCaption;
  final title = Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold);
  if (cap == null || cap.isEmpty) {
    return Text(v.name, style: titleStyle ?? title);
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(v.name, style: titleStyle ?? title),
      Text(
        cap,
        textAlign: TextAlign.left,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    ],
  );
}

/// Compact chip for the **closed** version control (selected state): quality only.
/// Telegram caption appears in the dropdown via [oxVersionQualityAndCaptionLabel].
Widget oxVersionStreamChipContent(BuildContext context, VersionStreamModel? v) {
  if (v == null) return const SizedBox.shrink();
  final top = v.name.trim().isNotEmpty ? v.name : v.detailedResolutionLabel;
  return Text(top, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false);
}
