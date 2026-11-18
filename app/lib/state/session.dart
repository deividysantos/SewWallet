import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// Endereço padrão da API, definido na compilação (--dart-define=API_URL=...).
const defaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

/// Sessão do usuário: endereço do servidor, token e dados do usuário logado.
class Session extends ChangeNotifier {
  static const _kServer = 'serverUrl';
  static const _kToken = 'token';
  static const _kUserName = 'userName';

  String serverUrl = defaultApiUrl;
  String? token;
  String? userName;

  bool get isLoggedIn => token != null;

  ApiClient get api => ApiClient(baseUrl: serverUrl, token: token, onUnauthorized: logout);

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    serverUrl = prefs.getString(_kServer) ?? defaultApiUrl;
    token = prefs.getString(_kToken);
    userName = prefs.getString(_kUserName);
  }

  Future<void> login({
    required String server,
    required String username,
    required String password,
  }) async {
    final url = server.trim().isEmpty ? defaultApiUrl : server.trim();
    final data = await ApiClient(baseUrl: url).post('/auth/login', {
      'username': username.trim(),
      'password': password,
    }) as Map<String, dynamic>;

    serverUrl = url;
    token = data['token'] as String;
    userName = (data['user'] as Map<String, dynamic>)['name'] as String?;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServer, serverUrl);
    await prefs.setString(_kToken, token!);
    if (userName != null) await prefs.setString(_kUserName, userName!);
    notifyListeners();
  }

  Future<void> logout() async {
    if (token == null) return;
    token = null;
    userName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserName);
    notifyListeners();
  }
}
