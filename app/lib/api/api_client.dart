import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Cliente HTTP da API do SewWallet. Valores em centavos, datas AAAA-MM-DD.
class ApiClient {
  ApiClient({required this.baseUrl, this.token, this.onUnauthorized, http.Client? client})
      : _client = client ?? _defaultClient;

  final String baseUrl;
  final String? token;
  final void Function()? onUnauthorized;
  final http.Client _client;

  static final _defaultClient = http.Client();

  static const _timeout = Duration(seconds: 20);

  Future<dynamic> get(String path, {Map<String, String?>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? {});

  Future<dynamic> put(String path, Object body, {Map<String, String?>? query}) =>
      _send('PUT', path, body: body, query: query);

  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);

  Future<dynamic> delete(String path, {Map<String, String?>? query}) =>
      _send('DELETE', path, query: query);

  Uri _uri(String path, Map<String, String?>? query) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final uri = Uri.parse('$base$path');
    final params = <String, String>{
      for (final e in (query ?? {}).entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    return params.isEmpty ? uri : uri.replace(queryParameters: params);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String?>? query,
    Object? body,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(_timeout));
    } on TimeoutException {
      throw ApiException('O servidor demorou para responder');
    } catch (_) {
      throw ApiException('Não foi possível conectar ao servidor');
    }

    final text = utf8.decode(response.bodyBytes);
    final data = text.isEmpty ? null : jsonDecode(text);

    if (response.statusCode == 401 && token != null) onUnauthorized?.call();
    if (response.statusCode >= 400) {
      final message = data is Map && data['error'] is String
          ? data['error'] as String
          : 'Erro ${response.statusCode}';
      throw ApiException(message, status: response.statusCode);
    }
    return data;
  }
}
