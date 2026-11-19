import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Apps de banco conhecidos (pacote → nome). Outros aparecem na configuração quando mandam
/// uma notificação com valor em R$, e podem ser marcados também.
const knownBankApps = {
  'com.nu.production': 'Nubank',
  'com.itau': 'Itaú',
  'br.com.intermedium': 'Inter',
  'com.c6bank.app': 'C6 Bank',
  'br.com.bb.android': 'Banco do Brasil',
  'com.bradesco': 'Bradesco',
  'com.santander.app': 'Santander',
  'br.com.gabba.Caixa': 'Caixa',
  'com.picpay': 'PicPay',
  'com.mercadopago.wallet': 'Mercado Pago',
};

/// Notificação lida no celular (registro local, para conferir o que foi enviado).
class CapturedNotification {
  CapturedNotification({required this.appName, required this.text, required this.result, this.title, this.postedAt});
  final String appName;
  final String? title;
  final String text;
  final String result;
  final DateTime? postedAt;
}

/// Leitura das notificações dos bancos (só no app Android). O serviço nativo
/// (BankNotificationService.kt) lê a configuração salva aqui e envia direto para a API.
class NotificationReader {
  NotificationReader._();

  static const _channel = MethodChannel('sewwallet/notifications');
  static const _kEnabled = 'notifications.enabled';
  static const _kApps = 'notifications.apps';

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Chama o lado nativo; sem ele (testes, versão antiga do app), devolve [fallback].
  static Future<T> _call<T>(String method, T fallback) async {
    if (!supported) return fallback;
    try {
      return await _channel.invokeMethod<T>(method) ?? fallback;
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    }
  }

  static Future<bool> isGranted() => _call('isGranted', false);

  static Future<void> openSettings() => _call<void>('openSettings', null);

  /// Informações do app no Android (para "Permitir configurações restritas" e bateria).
  static Future<void> openAppDetails() => _call<void>('openAppDetails', null);

  static Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;

  static Future<void> setEnabled(bool v) async => (await SharedPreferences.getInstance()).setBool(_kEnabled, v);

  /// Apps marcados para leitura. Na primeira vez, os bancos conhecidos.
  static Future<Set<String>> apps() async {
    final s = (await SharedPreferences.getInstance()).getString(_kApps);
    if (s == null) return knownBankApps.keys.toSet();
    return s.split(',').where((e) => e.isNotEmpty).toSet();
  }

  static Future<void> setApps(Set<String> apps) async =>
      (await SharedPreferences.getInstance()).setString(_kApps, apps.join(','));

  /// Apps que já mandaram notificação com valor (pacote → nome).
  static Future<Map<String, String>> seenApps() async {
    final raw = await _call('seenApps', '{}');
    return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as String));
  }

  static Future<int> queueSize() => _call('queueSize', 0);

  /// Envia o que ficou na fila (sem conexão na hora). Retorna quantas foram.
  static Future<int> flush() => _call('flush', 0);

  static Future<List<CapturedNotification>> log() async {
    final raw = await _call('log', '[]');
    return [
      for (final j in (jsonDecode(raw) as List).reversed)
        CapturedNotification(
          appName: j['appName'] as String? ?? '',
          title: j['title'] as String?,
          text: j['text'] as String? ?? '',
          result: j['result'] as String? ?? '',
          postedAt: DateTime.tryParse(j['postedAt'] as String? ?? '')?.toLocal(),
        ),
    ];
  }
}
