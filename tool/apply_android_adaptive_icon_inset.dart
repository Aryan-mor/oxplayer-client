// icons_launcher regenerates mipmap-anydpi-v26/ic_launcher.xml and points foreground
// at @mipmap/ic_launcher_foreground. Rewire to InsetDrawable wrappers so scaling uses
// the platform-defined safe zone without baking transparent margins into PNGs.
//
// After: dart run icons_launcher:create --path icons_launcher-production.yaml
// Run:   dart run tool/apply_android_adaptive_icon_inset.dart

import 'dart:io';

void main() {
  final path =
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Missing $path — run icons_launcher first.');
    exit(1);
  }
  var s = file.readAsStringSync();
  const fgMip = 'android:drawable="@mipmap/ic_launcher_foreground"';
  const fgInset = 'android:drawable="@drawable/ic_launcher_foreground_inset"';
  const monoMip = 'android:drawable="@mipmap/ic_launcher_monochrome"';
  const monoInset = 'android:drawable="@drawable/ic_launcher_monochrome_inset"';

  if (!s.contains(fgMip) && !s.contains(monoMip)) {
    stderr.writeln('Nothing to patch (already using inset drawables?).');
    exit(0);
  }
  s = s.replaceAll(fgMip, fgInset);
  s = s.replaceAll(monoMip, monoInset);
  file.writeAsStringSync(s);
  stdout.writeln('Patched $path for adaptive icon inset drawables.');
}
