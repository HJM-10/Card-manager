import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.unauthorized = false});
  final String message;
  final bool unauthorized;
  @override
  String toString() => message;
}

/// Session tokens live only in memory. Restarting requires another sign-in.
class SpendTrailApi {
  SpendTrailApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://localhost:8000',
          );

  final http.Client _client;
  final String baseUrl;
  String? _token;

  Future<dynamic> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    try {
      final request = http.Request(method, Uri.parse('$baseUrl$path'));
      request.headers['Content-Type'] = 'application/json';
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
      if (body != null) request.body = jsonEncode(body);
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
      final data = response.body.isEmpty ? null : jsonDecode(response.body);
      if (response.statusCode >= 400) {
        if (response.statusCode == 401) _token = null;
        final detail = data is Map ? data['detail'] : null;
        throw ApiException(
          detail is String ? detail : 'Check the details and try again.',
          unauthorized: response.statusCode == 401,
        );
      }
      return data;
    } on TimeoutException {
      throw const ApiException('The server took too long. Please try again.');
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach SpendTrail. Check your connection and try again.',
      );
    } on FormatException {
      throw const ApiException('The server returned an unexpected response.');
    }
  }

  Future<Map<String, dynamic>> authenticate({
    required String email,
    required String password,
    String? name,
  }) async {
    final data =
        await _request(
              'POST',
              name == null ? '/auth/login' : '/auth/register',
              {
                'email': email.trim(),
                'password': password,
                if (name != null) 'name': name.trim(),
              },
            )
            as Map<String, dynamic>;
    _token = data['access_token'] as String;
    return data['user'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> cards() async =>
      (await _request('GET', '/cards') as List).cast<Map<String, dynamic>>();

  Future<void> saveCard(Map<String, dynamic> card, {String? id}) async {
    await _request(
      id == null ? 'POST' : 'PATCH',
      id == null ? '/cards' : '/cards/$id',
      card,
    );
  }

  Future<void> archiveCard(String id) async {
    await _request('DELETE', '/cards/$id');
  }

  Future<void> logout() async {
    await _request('DELETE', '/auth/session');
    _token = null;
  }

  void close() => _client.close();
}
