import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode; final String message;
  ApiException(this.statusCode, this.message);
  @override String toString() => message;
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();
  static const _storage = FlutterSecureStorage();
  static const _baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8000');
  String? _token;
  Map<String, dynamic>? currentUser;
  List<dynamic> assignments = [];
  String get baseUrl => _baseUrl;
  bool get isAuthenticated => _token != null;

  Future<void> restore() async { _token = await _storage.read(key: 'access_token'); }
  Future<void> setSession(Map<String, dynamic> data) async {
    _token = data['access_token'] as String?;
    currentUser = Map<String, dynamic>.from(data['user'] as Map);
    assignments = List<dynamic>.from(currentUser?['assignments'] ?? []);
    if (_token != null) await _storage.write(key: 'access_token', value: _token);
  }
  Future<void> logout() async { _token = null; currentUser = null; assignments = []; await _storage.delete(key: 'access_token'); }

  Future<dynamic> get(String path) => _request('GET', path);
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _request('POST', path, body: body);
  Future<dynamic> _request(String method, String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (_token != null) headers['Authorization'] = 'Bearer $_token';
    late http.Response response;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed = await req.send().timeout(const Duration(seconds: 25));
      response = await http.Response.fromStream(streamed);
    } catch (e) { throw ApiException(0, 'Cannot reach Preeclampsia 360 server. Check API URL and connection.'); }
    dynamic decoded;
    try { decoded = response.body.isEmpty ? null : jsonDecode(response.body); } catch (_) { decoded = response.body; }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail'] : null;
      throw ApiException(response.statusCode, detail?.toString() ?? 'Request failed (${response.statusCode})');
    }
    return decoded;
  }
}
