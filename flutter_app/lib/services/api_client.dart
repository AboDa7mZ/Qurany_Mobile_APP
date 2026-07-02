import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/constants.dart';

class ApiClient {
  final String baseUrl;
  final http.Client _client;

  ApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? AppConstants.recitationApiBaseUrl,
        _client = client ?? http.Client();

  Map<String, String> _headers({String? token, bool json = true}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> get(
    String path, {
    String? token,
    Map<String, String>? query,
  }) {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    return _client.get(uri, headers: _headers(token: token));
  }

  Future<http.Response> postJson(
    String path, {
    required Map<String, dynamic> body,
    String? token,
  }) {
    return _client.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token: token),
      body: json.encode(body),
    );
  }

  Future<http.Response> postForm(
    String path, {
    required Map<String, String> fields,
  }) {
    return _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: fields,
    );
  }

  void dispose() {
    _client.close();
  }
}
