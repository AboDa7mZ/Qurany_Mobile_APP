import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/auth_result.dart';
import 'api_client.dart';

class AuthApiService {
  static const _requestTimeout = Duration(seconds: 10);

  final ApiClient _client;

  AuthApiService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<({AuthResult result, String? token})> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    if (!await isBackendAvailable()) {
      return (
        result: const AuthResult.failure(AuthFailure.backendUnavailable),
        token: null,
      );
    }

    try {
      final response = await _client
          .postJson(
            '/api/v1/auth/register',
            body: {
              'email': email,
              'password': password,
              'full_name': fullName,
            },
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final token = body['access_token'] as String?;
        if (token == null || token.isEmpty) {
          return (
            result: const AuthResult.failure(AuthFailure.invalidCredentials),
            token: null,
          );
        }
        return (result: const AuthResult.success(), token: token);
      }

      if (response.statusCode == 400) {
        return (
          result: const AuthResult.failure(AuthFailure.invalidCredentials),
          token: null,
        );
      }

      return (
        result: const AuthResult.failure(AuthFailure.backendUnavailable),
        token: null,
      );
    } on TimeoutException catch (e) {
      debugPrint('Register timeout: $e');
      return (
        result: const AuthResult.failure(AuthFailure.backendUnavailable),
        token: null,
      );
    } on SocketException catch (e) {
      debugPrint('Register network error: $e');
      return (
        result: const AuthResult.failure(AuthFailure.backendUnavailable),
        token: null,
      );
    } catch (e) {
      debugPrint('Register failed: $e');
      return (
        result: const AuthResult.failure(AuthFailure.backendUnavailable),
        token: null,
      );
    }
  }

  Future<({AuthResult result, String? token})> login({
    required String email,
    required String password,
  }) async {
    if (!await isBackendAvailable()) {
      return (
        result: const AuthResult.failure(AuthFailure.backendUnavailable),
        token: null,
      );
    }

    try {
      final response = await _client
          .postForm(
            '/api/v1/auth/login',
            fields: {
              'username': email,
              'password': password,
            },
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final token = body['access_token'] as String?;
        if (token == null || token.isEmpty) {
          return (
            result: const AuthResult.failure(AuthFailure.invalidCredentials),
            token: null,
          );
        }
        return (result: const AuthResult.success(), token: token);
      }

      if (response.statusCode == 401 || response.statusCode == 400) {
        return (
          result: const AuthResult.failure(AuthFailure.invalidCredentials),
          token: null,
        );
      }

      return (
        result: const AuthResult.failure(AuthFailure.backendUnavailable),
        token: null,
      );
    } on TimeoutException catch (e) {
      debugPrint('Login timeout: $e');
      return (
        result: const AuthResult.failure(AuthFailure.backendUnavailable),
        token: null,
      );
    } on SocketException catch (e) {
      debugPrint('Login network error: $e');
      return (
        result: const AuthResult.failure(AuthFailure.backendUnavailable),
        token: null,
      );
    } catch (e) {
      debugPrint('Login failed: $e');
      return (
        result: const AuthResult.failure(AuthFailure.backendUnavailable),
        token: null,
      );
    }
  }

  Future<Map<String, dynamic>?> me({required String token}) async {
    try {
      final response = await _client
          .get('/api/v1/auth/me', token: token)
          .timeout(_requestTimeout);
      if (response.statusCode != 200) return null;
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Fetch profile failed: $e');
      return null;
    }
  }

  Future<bool> isBackendAvailable() async {
    try {
      final response =
          await _client.get('/health').timeout(_requestTimeout);
      if (response.statusCode != 200) return false;
      final body = json.decode(response.body) as Map<String, dynamic>;
      return body['status'] == 'ok';
    } catch (e) {
      debugPrint('Backend unavailable: $e');
      return false;
    }
  }
}
