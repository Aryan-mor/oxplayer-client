import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:fladder/td_api_generated/td_api.dart' as tda;

import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';

/// Loads a still from [td.GetMessage].
///
/// **Quality:** Prefers the full [Thumbnail] JPEG (Telegram’s real preview, cached on disk by
/// TDLib). [Minithumbnail] is only a brief low-res placeholder while the file downloads, or
/// a fallback if there is no [Thumbnail] file. Previously we showed minithumbnail only, which
/// is always very small.
class TdlibMessageVideoThumbnail extends StatefulWidget {
  const TdlibMessageVideoThumbnail({
    super.key,
    required this.chatId,
    required this.messageId,
    this.fit = BoxFit.cover,
  });

  final int chatId;
  final int messageId;
  final BoxFit fit;

  @override
  State<TdlibMessageVideoThumbnail> createState() => _TdlibMessageVideoThumbnailState();
}

class _TdlibMessageVideoThumbnailState extends State<TdlibMessageVideoThumbnail> {
  Uint8List? _bytes;
  String? _filePath;
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      _loaded = true;
    }
  }

  @override
  void didUpdateWidget(covariant TdlibMessageVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId || oldWidget.messageId != widget.messageId) {
      setState(() {
        _bytes = null;
        _filePath = null;
        _loaded = false;
      });
      if (!kIsWeb) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _load());
      }
    }
  }

  /// Returns a local path if TDLib already has the file (including from a previous session).
  Future<String?> _pathIfFileReadyOnDisk(TdlibFacade td, {required int fileId}) async {
    if (fileId == 0) return null;
    final o = await td.send(tda.GetFile(fileId: fileId));
    if (o is! tda.File) return null;
    final path = o.local.path.trim();
    if (path.isEmpty) return null;
    if (o.local.isDownloadingCompleted) {
      return File(path).existsSync() ? path : null;
    }
    if (o.size > 0 && o.local.downloadedSize >= o.size) {
      return File(path).existsSync() ? path : null;
    }
    return null; // not ready yet; caller will [DownloadFile] + [GetFile] poll
  }

  Future<String?> _waitForThumbPath(
    TdlibFacade td, {
    required int fileId,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final end = DateTime.now().add(timeout);
    var n = 0;
    while (DateTime.now().isBefore(end)) {
      final o = await td.send(tda.GetFile(fileId: fileId));
      if (o is! tda.File) {
        return null;
      }
      final path = o.local.path.trim();
      if (path.isNotEmpty) {
        if (o.local.isDownloadingCompleted) {
          return path;
        }
        if (o.size > 0 && o.local.downloadedSize >= o.size) {
          return path;
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 100 + n % 5 * 30));
      n++;
    }
    return null;
  }

  Future<void> _load() async {
    if (widget.chatId == 0 || widget.messageId == 0) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    if (!await OxplayerTelegramTdSession.ensureReadyForPlayback()) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    final td = OxplayerTelegramTdSession().td;
    try {
      final o = await td.send(tda.GetMessage(chatId: widget.chatId, messageId: widget.messageId));
      if (o is! tda.Message) {
        if (mounted) setState(() => _loaded = true);
        return;
      }
      tda.Minithumbnail? mini;
      tda.Thumbnail? thumb;
      final c = o.content;
      if (c is tda.MessageVideo) {
        mini = c.video.minithumbnail;
        thumb = c.video.thumbnail;
      } else if (c is tda.MessageDocument) {
        mini = c.document.minithumbnail;
        thumb = c.document.thumbnail;
      } else {
        if (mounted) setState(() => _loaded = true);
        return;
      }

      Uint8List? miniBytes;
      if (mini != null && mini.data.isNotEmpty) {
        try {
          miniBytes = base64Decode(mini.data.replaceAll(RegExp(r'\s'), ''));
        } catch (_) {
          miniBytes = null;
        }
        if (miniBytes != null && miniBytes.isEmpty) {
          miniBytes = null;
        }
      }

      if (thumb != null) {
        final fileId = thumb.file.id;
        if (fileId != 0) {
          if (miniBytes != null && mounted) {
            setState(() {
              _bytes = miniBytes;
              _filePath = null;
              _loaded = true;
            });
          }
          var p = await _pathIfFileReadyOnDisk(td, fileId: fileId);
          if (p == null) {
            try {
              await td.send(
                tda.DownloadFile(
                  fileId: fileId,
                  priority: 32,
                  offset: 0,
                  limit: 0,
                  synchronous: false,
                ),
              );
            } catch (_) {}
            p = await _waitForThumbPath(td, fileId: fileId);
          }
          if (p != null && File(p).existsSync() && mounted) {
            setState(() {
              _filePath = p;
              _bytes = null;
              _loaded = true;
            });
            return;
          }
        }
      }

      if (miniBytes != null && mounted) {
        setState(() {
          _bytes = miniBytes;
          _filePath = null;
          _loaded = true;
        });
        return;
      }
    } catch (_) {
      // leave placeholder
    }
    if (mounted) {
      setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: widget.fit,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    }
    if (_filePath != null) {
      return Image.file(
        File(_filePath!),
        fit: widget.fit,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    }
    return _placeholder(context, showSpinner: !_loaded);
  }

  Widget _placeholder(BuildContext context, {bool showSpinner = false}) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Center(
        child: showSpinner
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                IconsaxPlusLinear.video,
                size: 36,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
      ),
    );
  }
}
