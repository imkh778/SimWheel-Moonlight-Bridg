import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Small persistent settings store used by the Sunshine sample.
class CacheService {
  static final CacheService _instance = CacheService._();
  factory CacheService() => _instance;
  CacheService._();
  static SharedPreferences? _prefs;

  static Future<void> initialize() async => _prefs = await SharedPreferences.getInstance();

  String _s(String key, [String fallback = '']) => _prefs?.getString(key) ?? fallback;

  bool _b(String key, [bool fallback = false]) => _prefs?.getBool(key) ?? fallback;

  int _i(String key, [int fallback = 0]) => _prefs?.getInt(key) ?? fallback;

  double _d(String key, [double fallback = 1]) => _prefs?.getDouble(key) ?? fallback;

  String getSunshineIp() => _s('sunshine_ip');

  Future<void> setSunshineIp(String v) async { await _prefs?.setString('sunshine_ip', v); }

  bool getSunshinePaired() => _b('sunshine_paired');

  Future<void> setSunshinePaired(bool v) async { await _prefs?.setBool('sunshine_paired', v); }

  Future<void> setSunshineEnabled(bool v) async { await _prefs?.setBool('sunshine_enabled', v); }

  Future<void> clearSunshinePairingData() async { for (final k in ['sunshine_ip','sunshine_paired','sunshine_client_cert','sunshine_client_key']) { await _prefs?.remove(k); } }

  String getIp() => '';

  String getSunshineClientId() => _s('sunshine_client_id', 'SIMWHEEL${Random.secure().nextInt(1 << 32)}');

  Future<String> rotateSunshineClientId() async { final v = 'SIMWHEEL${Random.secure().nextInt(1 << 32)}'; await _prefs?.setString('sunshine_client_id', v); return v; }

  String getSunshineClientCert() => _s('sunshine_client_cert');

  String getSunshineClientKey() => _s('sunshine_client_key');

  Future<void> setSunshineClientCert(String v) async { await _prefs?.setString('sunshine_client_cert', v); }

  Future<void> setSunshineClientKey(String v) async { await _prefs?.setString('sunshine_client_key', v); }

  double getSunshineOpacity() => _d('opacity');

  Future<void> setSunshineOpacity(double v) async { await _prefs?.setDouble('opacity', v); }

  String getSunshineResolution() => _s('resolution', '1080p');

  int getSunshineFps() => _i('fps', 60);

  int getSunshineBitrate() => _i('bitrate', 10000);

  bool getSunshineHevc() => _b('hevc');
}
