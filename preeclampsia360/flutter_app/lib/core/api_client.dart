import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();
  static const _storage = FlutterSecureStorage();
  static const _defaultBaseUrl = 'https://preeclampsia360-api.onrender.com';

  String? _token;
  String? _refreshToken;
  String? _activeFacilityId;
  Map<String, dynamic>? currentUser;
  List<dynamic> assignments = [];

  String get baseUrl => _defaultBaseUrl;

  Future<bool> testConnection([String? testUrl]) async {
    final target = baseUrl;
    try {
      final res = await http.get(Uri.parse('$target/health')).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
  bool get isAuthenticated => _token != null;
  bool get isPatient => currentUser?['is_patient'] == true || currentUser?['role'] == 'patient';
  String? get activeFacilityId => _activeFacilityId ?? (assignments.isNotEmpty ? assignments.first['facility_id']?.toString() : currentUser?['facility_id']?.toString());
  String? get activeFacilityName => activeAssignment?['facilities']?['name']?.toString() ?? currentUser?['facility_name']?.toString();

  Map<String, dynamic>? get activeAssignment {
    if (assignments.isEmpty) return null;
    if (_activeFacilityId != null) {
      for (final a in assignments) {
        if (a['facility_id']?.toString() == _activeFacilityId) {
          return Map<String, dynamic>.from(a as Map);
        }
      }
    }
    return Map<String, dynamic>.from(assignments.first as Map);
  }

  void setActiveFacilityId(String facilityId) {
    _activeFacilityId = facilityId;
  }

  Future<void> restore() async {
    _token = await _storage.read(key: 'access_token');
    _refreshToken = await _storage.read(key: 'refresh_token');
    final userRaw = await _storage.read(key: 'current_user');
    if (userRaw != null) {
      try {
        final decoded = jsonDecode(userRaw);
        if (decoded is Map) {
          currentUser = Map<String, dynamic>.from(decoded);
          assignments = List<dynamic>.from(currentUser?['assignments'] ?? []);
        }
      } catch (_) {}
    }
  }

  Future<void> setSession(Map<String, dynamic> data) async {
    _token = data['access_token'] as String?;
    _refreshToken = data['refresh_token'] as String?;
    if (data['user'] is Map) {
      currentUser = Map<String, dynamic>.from(data['user'] as Map);
      assignments = List<dynamic>.from(currentUser?['assignments'] ?? []);
    }
    if (_token != null) await _storage.write(key: 'access_token', value: _token);
    if (_refreshToken != null) await _storage.write(key: 'refresh_token', value: _refreshToken);
    if (currentUser != null) {
      await _storage.write(key: 'current_user', value: jsonEncode(currentUser));
    }
  }

  Future<void> logout() async {
    _token = null;
    _refreshToken = null;
    _activeFacilityId = null;
    currentUser = null;
    assignments = [];
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'current_user');
  }

  Future<bool> refreshToken() async {
    if (_refreshToken == null) return false;
    try {
      final uri = Uri.parse('$baseUrl/api/v1/auth/refresh');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _token = data['access_token'] as String?;
        if (data['refresh_token'] != null) {
          _refreshToken = data['refresh_token'] as String?;
          await _storage.write(key: 'refresh_token', value: _refreshToken);
        }
        if (_token != null) {
          await _storage.write(key: 'access_token', value: _token);
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<dynamic> get(String path) => _request('GET', path);
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _request('POST', path, body: body);
  Future<dynamic> put(String path, [Map<String, dynamic>? body]) => _request('PUT', path, body: body);
  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) => _request('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _request('DELETE', path);

  Future<dynamic> _request(String method, String path, {Map<String, dynamic>? body, bool retryOnAuth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null) headers['Authorization'] = 'Bearer $_token';
    final fid = activeFacilityId;
    if (fid != null) headers['X-Facility-ID'] = fid;

    late http.Response response;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed = await req.send().timeout(const Duration(seconds: 25));
      response = await http.Response.fromStream(streamed);
    } catch (e) {
      throw ApiException(0, 'Cannot reach Preeclampsia 360 server. Check API URL and connection.');
    }

    if (response.statusCode == 401 && retryOnAuth && _refreshToken != null) {
      final refreshed = await refreshToken();
      if (refreshed) {
        return _request(method, path, body: body, retryOnAuth: false);
      }
    }

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      decoded = response.body;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String msg = 'Request failed (${response.statusCode})';
      if (decoded is Map && decoded['detail'] != null) {
        final d = decoded['detail'];
        if (d is String) {
          msg = d;
        } else if (d is List && d.isNotEmpty && d.first is Map) {
          msg = d.first['msg']?.toString() ?? msg;
        } else {
          msg = d.toString();
        }
      }
      throw ApiException(response.statusCode, msg);
    }
    return decoded;
  }
}
