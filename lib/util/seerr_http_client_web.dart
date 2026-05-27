import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/util/app_http_client.dart';

http.Client createSeerrHttpClient() {
  return createAppHttpClient(inner: BrowserClient()..withCredentials = true);
}
