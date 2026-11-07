import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.unauthorized = false,
    this.statusCode,
  });
  final String message;
  final bool unauthorized;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Access tokens live only in memory. Biometric credentials are handled by
/// the separate platform vault, never by shared preferences.
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
          statusCode: response.statusCode,
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

  Future<List<Map<String, dynamic>>> cards({
    bool includeArchived = false,
  }) async =>
      (await _request(
                'GET',
                includeArchived ? '/cards?include_archived=true' : '/cards',
              )
              as List)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> categories() async =>
      (await _request('GET', '/categories') as List)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> createCategory(String name) async =>
      await _request('POST', '/categories', {'name': name.trim()})
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> categorizePurchase(
    String id,
    String? categoryId,
  ) async =>
      await _request(
            'PATCH',
            '/transactions/${Uri.encodeComponent(id)}/category',
            {'category_id': categoryId},
          )
          as Map<String, dynamic>;

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

  Future<Map<String, dynamic>> recordPurchase(
    Map<String, dynamic> purchase,
  ) async =>
      await _request('POST', '/transactions', purchase) as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> purchases({
    int limit = 25,
    int offset = 0,
    String search = '',
    String? cardId,
    String? categoryId,
    bool uncategorized = false,
    DateTime? occurredFrom,
    DateTime? occurredBefore,
  }) async =>
      (await _request(
                'GET',
                Uri(
                  path: '/transactions',
                  queryParameters: {
                    'limit': '$limit',
                    'offset': '$offset',
                    if (search.trim().isNotEmpty) 'search': search.trim(),
                    if (cardId != null) 'card_id': cardId,
                    if (categoryId != null) 'category_id': categoryId,
                    if (uncategorized) 'uncategorized': 'true',
                    if (occurredFrom != null)
                      'occurred_from': occurredFrom.toUtc().toIso8601String(),
                    if (occurredBefore != null)
                      'occurred_before': occurredBefore
                          .toUtc()
                          .toIso8601String(),
                  },
                ).toString(),
              )
              as List)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> purchase(String id) async =>
      await _request('GET', '/transactions/${Uri.encodeComponent(id)}')
          as Map<String, dynamic>;

  Future<void> logout() async {
    await _request('DELETE', '/auth/session');
    _token = null;
  }

  Future<String> enableBiometric() async =>
      (await _request('POST', '/auth/biometric')
              as Map<String, dynamic>)['refresh_token']
          as String;

  Future<void> disableBiometric() async {
    await _request('DELETE', '/auth/biometric');
  }

  Future<Map<String, dynamic>> biometricLogin(String token) async {
    final data =
        await _request('POST', '/auth/biometric/refresh', {
              'refresh_token': token,
            })
            as Map<String, dynamic>;
    _token = data['access_token'] as String;
    return data['user'] as Map<String, dynamic>;
  }

  Future<void> lock() async {
    try {
      await _request('DELETE', '/auth/access');
    } on ApiException catch (e) {
      if (!e.unauthorized) rethrow;
    } finally {
      _token = null;
    }
  }

  void close() => _client.close();
}
