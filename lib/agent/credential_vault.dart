import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CredentialVault {
  Future<String?> read(String id);
  Future<void> write(String id, String value);
  Future<void> delete(String id);
}

/// Testing a draft configuration must not overwrite a previously saved key.
class TransientCredentialVault implements CredentialVault {
  final CredentialVault parent;
  final String id;
  final String value;
  const TransientCredentialVault(this.parent, this.id, this.value);
  @override
  Future<String?> read(String key) =>
      key == id ? Future.value(value) : parent.read(key);
  @override
  Future<void> write(String id, String value) =>
      throw UnsupportedError('Read-only draft credentials');
  @override
  Future<void> delete(String id) =>
      throw UnsupportedError('Read-only draft credentials');
}

class SystemCredentialVault implements CredentialVault {
  final FlutterSecureStorage storage;
  const SystemCredentialVault({
    this.storage = const FlutterSecureStorage(
      // A transient keystore error must not erase API keys or the task DB key.
      aOptions: AndroidOptions(resetOnError: false),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
      mOptions: MacOsOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    ),
  });
  @override
  Future<String?> read(String id) => storage.read(key: id);
  @override
  Future<void> write(String id, String value) =>
      storage.write(key: id, value: value);
  @override
  Future<void> delete(String id) => storage.delete(key: id);
}
