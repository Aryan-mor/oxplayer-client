// Async artifact fetcher for official TDLib binaries (no Git LFS).
// Fail-fast: missing config, HTTP errors, SHA mismatch, or missing outputs → exit(1).
//
// Usage (from oxplayer-client root):
//   dart run tool/tdlib/fetch_artifacts.dart
//   dart run tool/tdlib/fetch_artifacts.dart --config=tool/tdlib/artifact_config.yaml
//   dart run tool/tdlib/fetch_artifacts.dart --flatten-tdweb-only
//     (no network: merge web/tdweb/dist/* -> web/tdweb/ for index.html flat layout)
//
// Expects tool/tdlib/TD_VERSION.json (committed) for commit_sha default.
// Requires tool/tdlib/artifact_config.yaml (gitignored) with base_url + headers.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

Never _fail(String message) {
  stderr.writeln('[fetch_artifacts] $message');
  exit(1);
}

Future<void> main(List<String> args) async {
  final clientRoot = Directory.current.path;
  if (args.contains('--flatten-tdweb-only')) {
    final webOut = p.join(clientRoot, 'web', 'tdweb');
    _flattenTdwebDistIntoRoot(webOut);
    _verifyTdwebFlatLayout(webOut);
    _markWebTdwebFromFetchArtifacts(webOut);
    stdout.writeln('[fetch_artifacts] OK — tdweb flattened to web/tdweb/ (flat layout).');
    return;
  }

  final tdlibTool = p.join(clientRoot, 'tool', 'tdlib');
  final versionFile = File(p.join(tdlibTool, 'TD_VERSION.json'));
  if (!versionFile.existsSync()) {
    _fail('Missing ${versionFile.path}');
  }
  final versionJson =
      jsonDecode(versionFile.readAsStringSync()) as Map<String, dynamic>;
  final commitSha = versionJson['commit_sha'] as String? ?? '';
  if (commitSha.length < 7) {
    _fail('Invalid commit_sha in TD_VERSION.json');
  }

  String? configPath;
  for (final a in args) {
    if (a.startsWith('--config=')) {
      configPath = a.substring('--config='.length);
    }
  }
  configPath ??= p.join(tdlibTool, 'artifact_config.yaml');
  final configFile = File(configPath);
  if (!configFile.existsSync()) {
    _fail(
      'No config at ${configFile.path}\n'
      'Copy tool/tdlib/artifact_config.example.yaml → artifact_config.yaml, set base_url, '
      'then re-run. Builds must not proceed without native + web artifacts.\n'
      'Layout (url_layout: nested_commit): {baseUrl}{commit}/android/{abi}/libtdjson.so\n'
      '        {baseUrl}{commit}/web/dist.tar.gz\n'
      'Layout (url_layout: github_release): base_url = .../releases/download/<tag>/\n'
      '        {baseUrl}libtdjson-<abi>.so, {baseUrl}dist.tar.gz\n',
    );
  }

  final yamlMap = loadYaml(configFile.readAsStringSync());
  if (yamlMap is! YamlMap) {
    _fail('Invalid YAML root in $configPath');
  }
  final baseUrl = yamlMap['base_url']?.toString() ?? '';
  final yamlCommit = yamlMap['commit_sha']?.toString();
  final effectiveCommit =
      (yamlCommit != null && yamlCommit.isNotEmpty) ? yamlCommit : commitSha;
  final urlLayout = yamlMap['url_layout']?.toString() ?? 'nested_commit';
  if (urlLayout != 'nested_commit' && urlLayout != 'github_release') {
    _fail(
        'url_layout must be nested_commit or github_release (got $urlLayout)');
  }
  final githubRelease = urlLayout == 'github_release';
  if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
    _fail('base_url must be http(s)');
  }
  final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  final headers = <String, String>{};
  final h = yamlMap['headers'];
  if (h is YamlMap) {
    for (final e in h.entries) {
      headers[e.key.toString()] = e.value.toString();
    }
  }

  final manifestPath =
      githubRelease ? 'manifest.json' : '$effectiveCommit/manifest.json';
  final manifestUrl = Uri.parse('$base$manifestPath');
  Map<String, dynamic>? manifest;
  try {
    final m = await _httpGetString(manifestUrl, headers);
    if (m != null) {
      manifest = jsonDecode(m) as Map<String, dynamic>?;
    }
  } catch (_) {
    // optional manifest
  }

  final androidOut =
      p.join(clientRoot, 'android', 'app', 'src', 'main', 'jniLibs');
  final webOut = p.join(clientRoot, 'web', 'tdweb');

  final tasks = <Future<void>>[];

  const abis = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'];
  for (final abi in abis) {
    final rel =
        githubRelease ? 'libtdjson-$abi.so' : 'android/$abi/libtdjson.so';
    final url = githubRelease
        ? Uri.parse('$base$rel')
        : Uri.parse('$base$effectiveCommit/$rel');
    final dest = File(p.join(androidOut, abi, 'libtdjson.so'));
    tasks.add(_downloadAndVerify(
      url: url,
      dest: dest,
      headers: headers,
      expectedSha256: _shaFromManifest(manifest, rel),
    ));
  }

  final webRel = githubRelease ? 'dist.tar.gz' : 'web/dist.tar.gz';
  final webArchive = githubRelease
      ? Uri.parse('$base$webRel')
      : Uri.parse('$base$effectiveCommit/$webRel');
  tasks.add(_downloadWebArchive(
    url: webArchive,
    destDir: webOut,
    headers: headers,
    expectedSha256: _shaFromManifest(manifest, webRel),
  ));

  try {
    await Future.wait(tasks);
  } catch (e, st) {
    _fail('Download failed: $e\n$st');
  }

  _verifyArtifacts(androidOut, webOut);
  stdout.writeln('[fetch_artifacts] OK — Android .so + web bundle present.');
}

/// Producer [dist.tar.gz] is built with `tar -C tdweb dist`, so extraction yields
/// only [web/tdweb/dist/...]. [web/index.html] loads [tdweb/tdweb.js] (flat). Merge
/// nested dist into the flat layout and remove stale root siblings (old *.wasm /
/// workers) so the runtime cannot load a mismatched webpack + WASM pair.
void _flattenTdwebDistIntoRoot(String webOut) {
  final distDir = Directory(p.join(webOut, 'dist'));
  if (!distDir.existsSync()) {
    stdout.writeln(
      '[fetch_artifacts] web/tdweb/dist/ absent — skipping flatten (tarball already flat or sync-tdweb layout).',
    );
    return;
  }

  final nestedFiles = distDir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .toList();
  if (nestedFiles.isEmpty) {
    _fail('web/tdweb/dist exists but contains no files');
  }

  for (final entity in Directory(webOut).listSync(followLinks: false)) {
    if (entity is Directory && p.basename(entity.path) == 'dist') {
      continue;
    }
    entity.deleteSync(recursive: true);
  }

  for (final src in nestedFiles) {
    final rel = p.relative(src.path, from: distDir.path);
    final dst = File(p.join(webOut, rel));
    dst.parent.createSync(recursive: true);
    src.copySync(dst.path);
  }

  distDir.deleteSync(recursive: true);
  stdout.writeln(
    '[fetch_artifacts] flattened ${nestedFiles.length} file(s) from web/tdweb/dist/ into web/tdweb/',
  );
}

/// Prevents [scripts/sync-tdweb.mjs] from copying npm `tdweb` over registry artifacts.
void _markWebTdwebFromFetchArtifacts(String webOut) {
  File(p.join(webOut, '.from_fetch_artifacts')).writeAsStringSync(
    'Managed by dart run tool/tdlib/fetch_artifacts.dart. '
    'Delete this file to allow scripts/sync-tdweb.mjs to copy npm tdweb.\n',
  );
}

void _verifyTdwebFlatLayout(String webOut) {
  final tdwebJs = File(p.join(webOut, 'tdweb.js'));
  if (!tdwebJs.existsSync()) {
    _fail(
      'Web bundle missing flat web/tdweb/tdweb.js after merge. '
      'Re-run fetch or sync-tdweb; see web/index.html script order.',
    );
  }
}

void _verifyArtifacts(String androidOut, String webOut) {
  const abis = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'];
  for (final abi in abis) {
    final f = File(p.join(androidOut, abi, 'libtdjson.so'));
    if (!f.existsSync() || f.lengthSync() < 4096) {
      _fail('Missing or too small: ${f.path}');
    }
  }
  _verifyTdwebFlatLayout(webOut);
}

String? _shaFromManifest(Map<String, dynamic>? manifest, String relPath) {
  if (manifest == null) return null;
  final files = manifest['files'];
  if (files is! List) return null;
  for (final f in files) {
    if (f is Map && f['path'] == relPath) {
      return f['sha256'] as String?;
    }
  }
  return null;
}

Future<String?> _httpGetString(Uri url, Map<String, String> headers) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    headers.forEach(req.headers.set);
    final res = await req.close();
    if (res.statusCode != HttpStatus.ok) return null;
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

/// GitHub Releases (and similar CDNs) occasionally return 502/503/504.
bool _isTransientHttpFailure(int statusCode) =>
    statusCode == 429 ||
    statusCode == 502 ||
    statusCode == 503 ||
    statusCode == 504;

/// GET [url] and return body bytes. Retries transient HTTP + socket errors.
Future<Uint8List> _httpGetBytesWithRetry(
  Uri url,
  Map<String, String> headers, {
  int maxAttempts = 5,
}) async {
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final client = HttpClient();
    try {
      final req = await client.getUrl(url);
      headers.forEach(req.headers.set);
      final res = await req.close();
      final code = res.statusCode;
      if (code == HttpStatus.ok) {
        final chunks = <int>[];
        await for (final chunk in res) {
          chunks.addAll(chunk);
        }
        return Uint8List.fromList(chunks);
      }
      await res.drain<void>();
      if (_isTransientHttpFailure(code) && attempt < maxAttempts) {
        final ms = 500 * (1 << (attempt - 1));
        stderr.writeln(
          '[fetch_artifacts] GET $url → $code (attempt $attempt/$maxAttempts), '
          'retrying in ${ms}ms…',
        );
        await Future<void>.delayed(Duration(milliseconds: ms));
        continue;
      }
      throw HttpException('GET $url → $code');
    } on SocketException catch (e) {
      if (attempt < maxAttempts) {
        final ms = 500 * (1 << (attempt - 1));
        stderr.writeln(
          '[fetch_artifacts] GET $url failed: $e (attempt $attempt/$maxAttempts), '
          'retrying in ${ms}ms…',
        );
        await Future<void>.delayed(Duration(milliseconds: ms));
        continue;
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
  throw HttpException('GET $url → exceeded retry budget');
}

Future<void> _downloadAndVerify({
  required Uri url,
  required File dest,
  required Map<String, String> headers,
  String? expectedSha256,
}) async {
  final bytes = await _httpGetBytesWithRetry(url, headers);
  final digest = sha256.convert(bytes).toString();
  if (expectedSha256 != null &&
      expectedSha256.toLowerCase() != digest.toLowerCase()) {
    throw StateError(
        'SHA256 mismatch for $url (expected $expectedSha256 got $digest)');
  }
  dest.parent.createSync(recursive: true);
  await dest.writeAsBytes(bytes, flush: true);
  stdout.writeln('[fetch_artifacts] wrote ${dest.path} ($digest)');
}

Future<void> _downloadWebArchive({
  required Uri url,
  required String destDir,
  required Map<String, String> headers,
  String? expectedSha256,
}) async {
  final bytes = await _httpGetBytesWithRetry(url, headers);
  try {
    final digest = sha256.convert(bytes).toString();
    if (expectedSha256 != null &&
        expectedSha256.toLowerCase() != digest.toLowerCase()) {
      throw StateError('SHA256 mismatch for $url');
    }
    final tmp = File(
      p.join(Directory.systemTemp.path,
          'ox_tdweb_${DateTime.now().microsecondsSinceEpoch}.tar.gz'),
    );
    await tmp.writeAsBytes(bytes, flush: true);
    final dir = Directory(destDir);
    if (dir.existsSync()) {
      await for (final e in dir.list()) {
        await e.delete(recursive: true);
      }
    } else {
      dir.createSync(recursive: true);
    }
    final result = await Process.run('tar', ['-xzf', tmp.path, '-C', destDir]);
    if (result.exitCode != 0) {
      throw StateError(
        'tar extract failed: ${result.stderr}\n'
        'Install GNU tar or extract $url manually into $destDir',
      );
    }
    await tmp.delete();
    stdout.writeln(
        '[fetch_artifacts] extracted web bundle to $destDir ($digest)');
    _flattenTdwebDistIntoRoot(destDir);
    _markWebTdwebFromFetchArtifacts(destDir);
  } catch (e) {
    throw HttpException(
      'web dist fetch/extract failed: $e (GET $url must succeed; no silent skip)',
    );
  }
}
