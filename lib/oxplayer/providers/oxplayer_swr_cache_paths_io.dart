import 'package:path_provider/path_provider.dart';

Future<String> applicationSupportPathForSwr() async {
  final d = await getApplicationSupportDirectory();
  return d.path;
}
