import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'sunshine_settings.dart';

/// Client certificate + crypto helpers for Moonlight/Sunshine pairing.
class SunshineCrypto {
  static final SunshineCrypto _instance = SunshineCrypto._();
  factory SunshineCrypto() => _instance;
  SunshineCrypto._();

  String? _certPem;
  String? _privateKeyPem;
  RSAPrivateKey? _privateKey;
  Uint8List? _pemCertBytes;
  Uint8List? _certSignature;

  String get certPem {
    _ensureLoaded();
    return _certPem!;
  }

  Uint8List get pemCertBytes {
    _ensureLoaded();
    return _pemCertBytes!;
  }

  String get privateKeyPem {
    _ensureLoaded();
    return _privateKeyPem!;
  }

  Uint8List get certSignature {
    _ensureLoaded();
    return _certSignature!;
  }

  RSAPrivateKey get privateKey {
    _ensureLoaded();
    return _privateKey!;
  }

  Future<void> ensureReady() async {
    final cache = CacheService();
    var cert = cache.getSunshineClientCert();
    var key = cache.getSunshineClientKey();

    if (cert.isEmpty || key.isEmpty) {
      final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final privateKey = pair.privateKey as RSAPrivateKey;
      final publicKey = pair.publicKey as RSAPublicKey;

      final csr = X509Utils.generateRsaCsrPem(
        {'CN': 'NVIDIA GameStream Client'},
        privateKey,
        publicKey,
      );

      // 20 years, matching Moonlight Android client cert lifetime.
      cert = X509Utils.generateSelfSignedCertificate(
        privateKey,
        csr,
        365 * 20,
      ).replaceAll('\r\n', '\n').replaceAll('\r', '\n');

      key = CryptoUtils.encodeRSAPrivateKeyToPem(
        privateKey,
      ).replaceAll('\r\n', '\n').replaceAll('\r', '\n');

      await cache.setSunshineClientCert(cert);
      await cache.setSunshineClientKey(key);
    }

    _loadFromPem(cert, key);
  }

  void _ensureLoaded() {
    if (_certPem != null && _privateKey != null) return;
    final cache = CacheService();
    final cert = cache.getSunshineClientCert();
    final key = cache.getSunshineClientKey();
    if (cert.isEmpty || key.isEmpty) {
      throw StateError(
        'Sunshine client cert not generated. Call ensureReady().',
      );
    }
    _loadFromPem(cert, key);
  }

  void _loadFromPem(String certPem, String keyPem) {
    _certPem = certPem.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    _privateKeyPem = keyPem.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    _pemCertBytes = Uint8List.fromList(utf8.encode(_certPem!));
    _privateKey = CryptoUtils.rsaPrivateKeyFromPem(_privateKeyPem!);
    _certSignature = extractSignature(_certPem!);
  }

  /// Raw X.509 signature octets (same as OpenSSL ASN1_BIT_STRING->data).
  static Uint8List extractSignature(String pem) {
    final der = CryptoUtils.getBytesFromPEMString(pem);
    final parser = ASN1Parser(der);
    final top = parser.nextObject() as ASN1Sequence;
    final sigBitString = top.elements![2] as ASN1BitString;
    final values = sigBitString.stringValues;
    if (values != null && values.isNotEmpty) {
      return Uint8List.fromList(values);
    }
    final raw = sigBitString.valueBytes;
    if (raw != null && raw.length > 1) {
      return Uint8List.fromList(raw.sublist(1));
    }
    throw StateError('Could not extract certificate signature');
  }

  static Uint8List randomBytes(int length) {
    final rand = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rand.nextInt(256)));
  }

  static String bytesToHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return sb.toString();
  }

  static Uint8List hexToBytes(String hex) {
    final cleaned = hex.replaceAll(RegExp(r'\s'), '');
    if (cleaned.length % 2 != 0) {
      throw FormatException('Odd hex length');
    }
    final out = Uint8List(cleaned.length ~/ 2);
    for (var i = 0; i < cleaned.length; i += 2) {
      out[i ~/ 2] = int.parse(cleaned.substring(i, i + 2), radix: 16);
    }
    return out;
  }

  static Uint8List concat(List<Uint8List> parts) {
    final total = parts.fold<int>(0, (n, p) => n + p.length);
    final out = Uint8List(total);
    var offset = 0;
    for (final p in parts) {
      out.setRange(offset, offset + p.length, p);
      offset += p.length;
    }
    return out;
  }

  static Uint8List sha256(Uint8List data) {
    final digest = SHA256Digest();
    return digest.process(data);
  }

  static Uint8List sha1(Uint8List data) {
    final digest = SHA1Digest();
    return digest.process(data);
  }

  /// AES-128-ECB with zero padding to block size (Moonlight behavior).
  static Uint8List aesEcb(
    Uint8List input,
    Uint8List key, {
    required bool encrypt,
  }) {
    final engine = AESEngine();
    engine.init(encrypt, KeyParameter(key));
    final blockSize = engine.blockSize;
    final rounded = (input.length + (blockSize - 1)) & ~(blockSize - 1);
    final padded = Uint8List(rounded)..setRange(0, input.length, input);
    final out = Uint8List(rounded);
    for (var offset = 0; offset < rounded; offset += blockSize) {
      engine.processBlock(padded, offset, out, offset);
    }
    return out;
  }

  static Uint8List aesEcbDecryptExact(Uint8List input, Uint8List key) {
    if (input.isEmpty || input.length % 16 != 0) {
      throw FormatException(
        'AES-ECB input must be a non-empty multiple of 16 bytes',
      );
    }
    final engine = AESEngine();
    engine.init(false, KeyParameter(key));
    final out = Uint8List(input.length);
    for (var offset = 0; offset < input.length; offset += engine.blockSize) {
      engine.processBlock(input, offset, out, offset);
    }
    return out;
  }

  static Uint8List deriveAesKey(
    Uint8List salt,
    String pin, {
    required bool useSha256,
  }) {
    final pinBytes = Uint8List.fromList(utf8.encode(pin));
    final salted = concat([salt, pinBytes]);
    final hash = useSha256 ? sha256(salted) : sha1(salted);
    return Uint8List.fromList(hash.sublist(0, 16));
  }

  static Uint8List signSha256Rsa(Uint8List data, RSAPrivateKey key) {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(key));
    return signer.generateSignature(data).bytes;
  }

  static bool verifySha256Rsa(
    Uint8List data,
    Uint8List signature,
    RSAPublicKey key,
  ) {
    try {
      final verifier = RSASigner(SHA256Digest(), '0609608648016503040201');
      verifier.init(false, PublicKeyParameter<RSAPublicKey>(key));
      return verifier.verifySignature(data, RSASignature(signature));
    } catch (_) {
      return false;
    }
  }

  static RSAPublicKey publicKeyFromPem(String pem) {
    final data = X509Utils.x509CertificateFromPem(pem);
    final bytesHex = data.tbsCertificate?.subjectPublicKeyInfo.bytes;
    if (bytesHex == null || bytesHex.isEmpty) {
      throw StateError('Could not parse public key from certificate');
    }
    // SubjectPublicKeyInfo bytes are stored as a hex string.
    return CryptoUtils.rsaPublicKeyFromDERBytes(hexToBytes(bytesHex));
  }

  /// Convert hex-encoded plaincert (PEM or DER bytes) to PEM string.
  static String plainCertHexToPem(String hex) {
    final bytes = hexToBytes(hex);
    final asText = utf8.decode(bytes, allowMalformed: true);
    if (asText.contains('BEGIN CERTIFICATE')) {
      return asText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    }
    // DER → PEM
    final b64 = base64.encode(bytes);
    final chunks = <String>[];
    for (var i = 0; i < b64.length; i += 64) {
      chunks.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
    }
    return '-----BEGIN CERTIFICATE-----\n${chunks.join('\n')}\n-----END CERTIFICATE-----\n';
  }
}
