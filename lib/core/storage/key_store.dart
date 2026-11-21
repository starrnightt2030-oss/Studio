import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// مفتاح Gemini بيتحفظ مشفّر على جهاز المستخدم بس، ومش بيتبعت لأي مكان غير Google.
class KeyStore {
  KeyStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _k = 'gemini_api_key';
  final FlutterSecureStorage _storage;

  Future<String?> read() async {
    final v = await _storage.read(key: _k);
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  Future<void> save(String key) => _storage.write(key: _k, value: key.trim());
  Future<void> clear() => _storage.delete(key: _k);
}

final keyStoreProvider = Provider<KeyStore>((ref) => KeyStore());

/// المفتاح الحالي في الذاكرة (null = مفيش مفتاح).
class ApiKeyNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  Future<void> load() async => state = await ref.read(keyStoreProvider).read();

  Future<void> set(String key) async {
    await ref.read(keyStoreProvider).save(key);
    state = key.trim();
  }

  Future<void> clear() async {
    await ref.read(keyStoreProvider).clear();
    state = null;
  }
}

final apiKeyProvider = NotifierProvider<ApiKeyNotifier, String?>(ApiKeyNotifier.new);
