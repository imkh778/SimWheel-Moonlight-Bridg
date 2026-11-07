import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'sunshine_settings.dart';
import 'sunshine_crypto.dart';

/// Result of a Sunshine/Moonlight pairing attempt.
enum SunshinePairResult {
  success,
  failed,
  pinWrong,
  alreadyInProgress,
  timedOut,
  clientChallengeFailed,
  serverChallengeResponseFailed,
  clientPairingSecretFailed,
  finalChallengeFailed,
  serverChallengeResponseTransportFailed,
}

/// Represents a discovered Sunshine host on the local network.
class DiscoveredSunshineHost {
  final String ip;
  final SunshineServerInfo info;

  const DiscoveredSunshineHost({required this.ip, required this.info});

  String get displayName => info.hostname;
  bool get isPaired => info.isPaired;
  String get stateLabel {
    if (info.currentGame != 0) return 'Streaming';
    return info.state == 'SUNSHINE_STATE_PLAYING' ? 'Streaming' : 'Ready';
  }
}

/// Representation of Sunshine / GameStream server details.
class SunshineServerInfo {
  final String hostname;
  final String appVersion;
  final String? gfeVersion;
  final int codecModeSupport;
  final bool isPaired;
  final String state;
  final int currentGame;
  final int httpsPort;
  final int httpPort;
  final bool isOnline;
  final String? errorMessage;

  const SunshineServerInfo({
    required this.hostname,
    required this.appVersion,
    this.gfeVersion,
    this.codecModeSupport = 0,
    required this.isPaired,
    required this.state,
    required this.currentGame,
    required this.httpsPort,
    required this.httpPort,
    required this.isOnline,
    this.errorMessage,
  });

  factory SunshineServerInfo.offline([String? error]) {
    return SunshineServerInfo(
      hostname: 'Offline',
      appVersion: 'Unknown',
      isPaired: false,
      state: 'OFFLINE',
      currentGame: 0,
      httpsPort: 47984,
      httpPort: 47989,
      isOnline: false,
      errorMessage: error,
    );
  }

  factory SunshineServerInfo.fromXml(
    String xml, {
    int defaultHttpsPort = 47984,
    int defaultHttpPort = 47989,
  }) {
    String extract(String tag, [String fallback = '']) {
      final reg = RegExp(
        '<$tag>(.*?)</$tag>',
        dotAll: true,
        caseSensitive: false,
      );
      final match = reg.firstMatch(xml);
      return match != null ? match.group(1)?.trim() ?? fallback : fallback;
    }

    final hostname = extract('hostname', 'Sunshine Host');
    final appVersion = extract('appversion', extract('version', 'Unknown'));
    final gfeVersion = extract('GfeVersion');
    final codecModeSupport =
        int.tryParse(extract('ServerCodecModeSupport', '0')) ?? 0;
    final pairStatus = extract('PairStatus', '0');
    final state = extract('state', 'UNKNOWN');
    final currentGame = int.tryParse(extract('currentgame', '0')) ?? 0;
    final httpsPort =
        int.tryParse(extract('HttpsPort', defaultHttpsPort.toString())) ??
        defaultHttpsPort;
    final httpPort =
        int.tryParse(
          extract(
            'ExternalPort',
            extract('HttpPort', defaultHttpPort.toString()),
          ),
        ) ??
        defaultHttpPort;

    return SunshineServerInfo(
      hostname: hostname,
      appVersion: appVersion,
      gfeVersion: gfeVersion.isEmpty ? null : gfeVersion,
      codecModeSupport: codecModeSupport,
      isPaired: pairStatus == '1',
      state: state,
      currentGame: currentGame,
      httpsPort: httpsPort,
      httpPort: httpPort,
      isOnline: true,
    );
  }

  @override
  String toString() {
    return 'SunshineServerInfo(hostname: $hostname, v: $appVersion, paired: $isPaired, state: $state)';
  }
}

/// App entry returned by Sunshine.
class SunshineApp {
  final String title;
  final String id;

  const SunshineApp({required this.title, required this.id});

  @override
  String toString() => '$title ($id)';
}

/// Authenticated launch details consumed by Moonlight's Android native core.
class SunshineStreamSession {
  final String host;
  final String appVersion;
  final String? gfeVersion;
  final int codecModeSupport;
  final String sessionUrl;
  final int width;
  final int height;
  final int fps;
  final int bitrate;
  final bool preferHevc;
  final Uint8List remoteInputKey;
  final Uint8List remoteInputIv;

  const SunshineStreamSession({
    required this.host,
    required this.appVersion,
    required this.gfeVersion,
    required this.codecModeSupport,
    required this.sessionUrl,
    required this.width,
    required this.height,
    required this.fps,
    required this.bitrate,
    required this.preferHevc,
    required this.remoteInputKey,
    required this.remoteInputIv,
  });

  Map<String, Object?> toPlatformMap() => {
    'host': host,
    'appVersion': appVersion,
    'gfeVersion': gfeVersion,
    'codecMode': codecModeSupport,
    'sessionUrl': sessionUrl,
    'width': width,
    'height': height,
    'fps': fps,
    'bitrate': bitrate,
    'preferHevc': preferHevc,
    'riKey': remoteInputKey,
    'riIv': remoteInputIv,
  };
}

/// Service managing communication, pairing, and session lifecycle with Sunshine host.
class SunshineService {
  static final SunshineService _instance = SunshineService._internal();
  factory SunshineService() => _instance;

  SunshineService._internal();

  /// Last pairing transport/protocol detail, shown when pairing fails.
  String? lastPairDiagnostic;

  HttpClient? _activePairingClient;
  Completer<void>? _activePairingDone;
  bool _pairingCancelRequested = false;

  /// Cancel the current PIN wait and wait for its cleanup before allowing a retry.
  Future<void> cancelPairing() async {
    final done = _activePairingDone;
    if (done == null) return;
    _pairingCancelRequested = true;
    _activePairingClient?.close(force: true);
    await done.future;
  }

  /// Create an HttpClient configured with timeouts and accepting self-signed certs.
  HttpClient _createHttpClient({
    Duration timeout = const Duration(seconds: 3),
    SunshineCrypto? clientIdentity,
  }) {
    SecurityContext? context;
    if (clientIdentity != null) {
      context = SecurityContext(withTrustedRoots: true)
        ..useCertificateChainBytes(clientIdentity.pemCertBytes)
        ..usePrivateKeyBytes(utf8.encode(clientIdentity.privateKeyPem));
    }
    final client = HttpClient(context: context);
    client.connectionTimeout = timeout;
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return client;
  }

  /// Resolve target IP address (from parameters, or stored Sunshine IP, or PC receiver IP).
  String getTargetIp([String? ip]) {
    if (ip != null && ip.trim().isNotEmpty) return ip.trim();
    final sunshineIp = CacheService().getSunshineIp();
    if (sunshineIp.trim().isNotEmpty) return sunshineIp.trim();
    return CacheService().getIp().trim();
  }

  /// Get or generate unique client identifier.
  String getClientId() {
    return CacheService().getSunshineClientId();
  }

  /// Query serverinfo from Sunshine host.
  /// Standard GameStream discovery uses HTTP port 47989, with HTTPS fallback on port 47984.
  Future<SunshineServerInfo> fetchServerInfo({String? ip}) async {
    final target = getTargetIp(ip);
    if (target.isEmpty) {
      return SunshineServerInfo.offline("No IP specified");
    }

    final clientId = getClientId();

    // 1. Primary: HTTP port 47989 (GameStream standard discovery)
    final client1 = _createHttpClient(timeout: const Duration(seconds: 2));
    try {
      final uri = Uri.parse(
        'http://$target:47989/serverinfo?uniqueid=$clientId',
      );
      final request = await client1
          .getUrl(uri)
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        return await _applyCachedPairing(
          info: SunshineServerInfo.fromXml(body),
          ip: target,
        );
      }
    } catch (_) {
    } finally {
      client1.close();
    }

    // 2. Fallback: HTTPS port 47984
    final client2 = _createHttpClient(timeout: const Duration(seconds: 2));
    try {
      final uri = Uri.parse(
        'https://$target:47984/serverinfo?uniqueid=$clientId',
      );
      final request = await client2
          .getUrl(uri)
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        return await _applyCachedPairing(
          info: SunshineServerInfo.fromXml(body),
          ip: target,
        );
      }
    } catch (e) {
      debugPrint("Sunshine fetchServerInfo fallback failed: $e");
    } finally {
      client2.close();
    }

    return SunshineServerInfo.offline(
      "Could not connect to Sunshine at $target",
    );
  }

  /// Sunshine's HTTP serverinfo PairStatus can remain 0 even after it has
  /// stored the client's certificate. Preserve the locally confirmed pairing
  /// for the selected host so discovery does not send the user back to pairing.
  Future<SunshineServerInfo> _applyCachedPairing({
    required SunshineServerInfo info,
    required String ip,
  }) async {
    final cache = CacheService();
    final sameHost = cache.getSunshineIp().trim() == ip.trim();
    final paired = info.isPaired || (sameHost && cache.getSunshinePaired());
    if (info.isPaired) {
      await cache.setSunshinePaired(true);
    }
    if (!paired || info.isPaired) return info;
    return SunshineServerInfo(
      hostname: info.hostname,
      appVersion: info.appVersion,
      isPaired: true,
      state: info.state,
      currentGame: info.currentGame,
      httpsPort: info.httpsPort,
      httpPort: info.httpPort,
      isOnline: info.isOnline,
      errorMessage: info.errorMessage,
    );
  }

  /// Probe a single IP address for Sunshine with high performance.
  /// First checks if TCP port 47989 or 47984 is open, then queries serverinfo.
  Future<DiscoveredSunshineHost?> _probeHost(String ip) async {
    bool has47989 = false;
    bool has47984 = false;

    // Fast TCP SYN check on port 47989 (350ms timeout)
    try {
      final s = await Socket.connect(
        ip,
        47989,
        timeout: const Duration(milliseconds: 350),
      );
      s.destroy();
      has47989 = true;
    } catch (_) {}

    if (!has47989) {
      // Fallback check on port 47984
      try {
        final s = await Socket.connect(
          ip,
          47984,
          timeout: const Duration(milliseconds: 300),
        );
        s.destroy();
        has47984 = true;
      } catch (_) {}
    }

    if (!has47989 && !has47984) {
      return null;
    }

    // Port is open — fetch serverinfo XML
    final clientId = getClientId();
    final client = _createHttpClient(
      timeout: const Duration(milliseconds: 900),
    );

    try {
      final url = has47989
          ? 'http://$ip:47989/serverinfo?uniqueid=$clientId'
          : 'https://$ip:47984/serverinfo?uniqueid=$clientId';
      final uri = Uri.parse(url);
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(milliseconds: 900));
      final response = await request.close().timeout(
        const Duration(milliseconds: 900),
      );
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final info = await _applyCachedPairing(
          info: SunshineServerInfo.fromXml(body),
          ip: ip,
        );
        return DiscoveredSunshineHost(ip: ip, info: info);
      }
    } catch (_) {
    } finally {
      client.close();
    }

    return null;
  }

  /// Scan the local network for Sunshine hosts.
  ///
  /// Probes priority IPs first, then discovers subnets and scans in parallel batches.
  /// Discovered hosts are reported in real-time via [onHostFound].
  Future<List<DiscoveredSunshineHost>> scanLocalNetwork({
    void Function(DiscoveredSunshineHost host)? onHostFound,
  }) async {
    final discovered = <DiscoveredSunshineHost>[];
    final subnets = <String>{};

    void addHost(DiscoveredSunshineHost host) {
      if (!discovered.any((h) => h.ip == host.ip)) {
        discovered.add(host);
        onHostFound?.call(host);
      }
    }

    // 1. Priority probes: Stored Sunshine IP, and PC receiver IP
    final priorityIps = <String>{
      CacheService().getSunshineIp().trim(),
      CacheService().getIp().trim(),
      '127.0.0.1', // Useful when testing locally / in emulator
    }..removeWhere((ip) => ip.isEmpty);

    for (final ip in priorityIps) {
      final result = await _probeHost(ip);
      if (result != null) {
        addHost(result);
      }
      final parts = ip.split('.');
      if (parts.length == 4 && ip != '127.0.0.1') {
        subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    }

    // 2. Enumerate subnets from network interfaces (Wi-Fi, hotspot, tethering)
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error enumerating network interfaces: $e');
    }

    // 3. Fallbacks for mobile devices where interface enumeration is restricted
    if (subnets.isEmpty) {
      subnets.addAll(['192.168.0', '192.168.1', '192.168.42', '192.168.43']);
    }

    // 4. Scan subnets in parallel batches of 40
    for (final subnet in subnets) {
      final allIps = List.generate(254, (i) => '$subnet.${i + 1}');
      final toProbe = allIps
          .where((ip) => !discovered.any((h) => h.ip == ip))
          .toList();

      const batchSize = 40;
      for (int i = 0; i < toProbe.length; i += batchSize) {
        final batch = toProbe.skip(i).take(batchSize).toList();
        final results = await Future.wait(batch.map(_probeHost));
        for (final result in results) {
          if (result != null) {
            addHost(result);
          }
        }
      }
    }

    return discovered;
  }

  /// Generate a random 4-digit PIN for pairing.
  String generatePin() {
    final rand = math.Random.secure();
    return List.generate(4, (_) => rand.nextInt(10)).join();
  }

  String _xmlValue(String xml, String tag) {
    final reg = RegExp(
      '<$tag>(.*?)</$tag>',
      dotAll: true,
      caseSensitive: false,
    );
    return (reg.firstMatch(xml)?.group(1)?.trim() ?? '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  String _xmlAttribute(String xml, String attribute) {
    final match = RegExp(
      '<root\\b[^>]*\\b$attribute="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(xml);
    return match?.group(1) ?? '';
  }

  int _serverMajorVersion(SunshineServerInfo info) {
    final match = RegExp(r'^(\d+)').firstMatch(info.appVersion.trim());
    return int.tryParse(match?.group(1) ?? '') ?? 7;
  }

  Future<String?> _httpGet(
    HttpClient client,
    Uri uri, {
    required Duration timeout,
  }) async {
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      // Sunshine holds getservercert open while it waits for the PIN to be
      // entered in its web UI. Keep that long poll bounded too: otherwise a
      // dropped request can leave the pairing dialog waiting forever.
      // Its response closes the socket, so don't reuse a keep-alive connection
      // across the subsequent pairing phases.
      request.persistentConnection = false;
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode != 200) {
        final statusMessage = _xmlAttribute(body, 'status_message');
        lastPairDiagnostic =
            'HTTP ${response.statusCode}${statusMessage.isEmpty ? '' : ': $statusMessage'}';
        debugPrint(
          'Sunshine pairing HTTP ${response.statusCode} '
          '(${uri.path}?${uri.queryParameters.keys.join('&')})'
          '${statusMessage.isEmpty ? '' : ': $statusMessage'}; '
          'response=${body.length > 400 ? body.substring(0, 400) : body}',
        );
        return null;
      }
      return body;
    } catch (e) {
      lastPairDiagnostic = '${uri.path}: $e';
      debugPrint(
        'Sunshine pairing HTTP failed '
        '(${uri.host}:${uri.port}${uri.path}; '
        'params=${uri.queryParameters.keys.join(',')}): $e',
      );
      rethrow;
    }
  }

  Uri _pairUri(
    String scheme,
    String ip,
    String clientId,
    Map<String, String> parameters,
  ) => Uri(
    scheme: scheme,
    host: ip,
    port: scheme == 'https' ? 47984 : 47989,
    path: '/pair',
    queryParameters: {
      ...parameters,
      'uniqueid': clientId,
      'uuid': SunshineCrypto.bytesToHex(SunshineCrypto.randomBytes(16)),
    },
  );

  Map<String, String> _pairParameters(
    String clientId,
    String deviceName,
    Map<String, String> additional,
  ) => {
    'uniqueid': clientId,
    'devicename': deviceName,
    'updateState': '1',
    ...additional,
  };

  Uri _unpairUri(String ip, String clientId) => Uri(
    scheme: 'http',
    host: ip,
    port: 47989,
    path: '/unpair',
    queryParameters: {
      'uniqueid': clientId,
      'uuid': SunshineCrypto.bytesToHex(SunshineCrypto.randomBytes(16)),
    },
  );

  /// Full Moonlight/Sunshine pairing handshake.
  ///
  /// [getservercert] keeps the HTTP connection open until the user enters the
  /// PIN in Sunshine Web UI — that is when the phone name/client appears on PC.
  Future<SunshinePairResult> pair({
    required String ip,
    required String pin,
    String deviceName = 'SimWheel',
    Duration pinWaitTimeout = const Duration(minutes: 2),
  }) async {
    lastPairDiagnostic = null;
    if (_activePairingDone != null) {
      lastPairDiagnostic = 'A pairing attempt is already running';
      return SunshinePairResult.alreadyInProgress;
    }
    final pairingDone = Completer<void>();
    _activePairingDone = pairingDone;
    _pairingCancelRequested = false;
    try {
      await SunshineCrypto().ensureReady();
    } catch (e) {
      lastPairDiagnostic = 'Could not prepare the pairing certificate: $e';
      _activePairingDone = null;
      _pairingCancelRequested = false;
      if (!pairingDone.isCompleted) pairingDone.complete();
      return SunshinePairResult.failed;
    }
    final crypto = SunshineCrypto();
    // A failed or abandoned PIN wait can poison Sunshine's pending session
    // for this unique ID. Use a new ID on each pairing attempt so retries work
    // even with Sunshine versions that do not discard stale sessions.
    final clientId = await CacheService().rotateSunshineClientId();

    final info = await fetchServerInfo(ip: ip);
    // Sunshine derives the PIN key with SHA-256 for the modern protocol.
    final useSha256 = _serverMajorVersion(info) >= 7;

    final salt = SunshineCrypto.randomBytes(16);
    final aesKey = SunshineCrypto.deriveAesKey(salt, pin, useSha256: useSha256);
    final clientCertHex = SunshineCrypto.bytesToHex(crypto.pemCertBytes);

    // Long timeout: Sunshine holds getservercert until PIN is entered on PC.
    // Sunshine requires the client's paired identity for its final HTTPS
    // pairchallenge. Moonlight presents this cert on HTTPS requests.
    final pairClient = _createHttpClient(
      timeout: pinWaitTimeout,
      clientIdentity: crypto,
    );
    if (_pairingCancelRequested) {
      pairClient.close(force: true);
      _activePairingClient = null;
      _activePairingDone = null;
      if (!pairingDone.isCompleted) pairingDone.complete();
      return SunshinePairResult.failed;
    }
    _activePairingClient = pairClient;
    var pairingSucceeded = false;
    var clientCertificateStored = false;
    try {
      final getCertParameters = _pairParameters(clientId, deviceName, {
        'phrase': 'getservercert',
        'salt': SunshineCrypto.bytesToHex(salt),
        'clientcert': clientCertHex,
      });

      // Sunshine waits on this request until the PIN is entered in its UI.
      String? getCertXml;
      try {
        getCertXml = await _httpGet(
          pairClient,
          _pairUri('http', ip, clientId, getCertParameters),
          timeout: pinWaitTimeout,
        );
      } on TimeoutException {
        debugPrint('Sunshine timed out waiting for the PIN confirmation');
        return SunshinePairResult.timedOut;
      }

      if (getCertXml == null) {
        return SunshinePairResult.timedOut;
      }
      if (_xmlValue(getCertXml, 'paired') != '1') {
        return SunshinePairResult.failed;
      }

      final plainCertHex = _xmlValue(getCertXml, 'plaincert');
      if (plainCertHex.isEmpty) {
        return SunshinePairResult.alreadyInProgress;
      }

      final serverCertPem = SunshineCrypto.plainCertHexToPem(plainCertHex);
      final serverCertSig = SunshineCrypto.extractSignature(serverCertPem);
      final serverPublicKey = SunshineCrypto.publicKeyFromPem(serverCertPem);

      // Phase 2 — clientchallenge
      final randomChallenge = SunshineCrypto.randomBytes(16);
      final encryptedChallenge = SunshineCrypto.aesEcb(
        randomChallenge,
        aesKey,
        encrypt: true,
      );
      final challengeXml = await _httpGet(
        pairClient,
        _pairUri(
          'http',
          ip,
          clientId,
          _pairParameters(clientId, deviceName, {
            'clientchallenge': SunshineCrypto.bytesToHex(encryptedChallenge),
          }),
        ),
        timeout: const Duration(seconds: 10),
      );
      if (challengeXml == null || _xmlValue(challengeXml, 'paired') != '1') {
        debugPrint('Sunshine pairing failed during clientchallenge');
        return SunshinePairResult.clientChallengeFailed;
      }

      final hashLen = useSha256 ? 32 : 20;
      final encServerChallengeResponse = SunshineCrypto.hexToBytes(
        _xmlValue(challengeXml, 'challengeresponse'),
      );
      final decServerChallengeResponse = SunshineCrypto.aesEcbDecryptExact(
        encServerChallengeResponse,
        aesKey,
      );
      if (decServerChallengeResponse.length < hashLen + 16) {
        return SunshinePairResult.failed;
      }
      final serverResponse = Uint8List.fromList(
        decServerChallengeResponse.sublist(0, hashLen),
      );
      final serverChallenge = Uint8List.fromList(
        decServerChallengeResponse.sublist(hashLen, hashLen + 16),
      );

      // Phase 3 — serverchallengeresp
      final clientSecret = SunshineCrypto.randomBytes(16);
      final challengeRespHashInput = SunshineCrypto.concat([
        serverChallenge,
        crypto.certSignature,
        clientSecret,
      ]);
      final challengeRespHash = useSha256
          ? SunshineCrypto.sha256(challengeRespHashInput)
          : SunshineCrypto.sha1(challengeRespHashInput);
      final challengeRespEncrypted = SunshineCrypto.aesEcb(
        challengeRespHash,
        aesKey,
        encrypt: true,
      );

      String? secretXml;
      try {
        secretXml = await _httpGet(
          pairClient,
          _pairUri(
            'http',
            ip,
            clientId,
            _pairParameters(clientId, deviceName, {
              'serverchallengeresp': SunshineCrypto.bytesToHex(
                challengeRespEncrypted,
              ),
            }),
          ),
          timeout: const Duration(seconds: 30),
        );
      } on HttpException {
        debugPrint('Sunshine serverchallengeresp connection was closed');
        return SunshinePairResult.serverChallengeResponseTransportFailed;
      } on SocketException {
        debugPrint('Sunshine serverchallengeresp socket failed');
        return SunshinePairResult.serverChallengeResponseTransportFailed;
      } on TimeoutException {
        debugPrint('Sunshine serverchallengeresp timed out');
        return SunshinePairResult.serverChallengeResponseTransportFailed;
      }
      if (secretXml == null || _xmlValue(secretXml, 'paired') != '1') {
        debugPrint('Sunshine rejected serverchallengeresp');
        return SunshinePairResult.serverChallengeResponseFailed;
      }

      final serverSecretResp = SunshineCrypto.hexToBytes(
        _xmlValue(secretXml, 'pairingsecret'),
      );
      if (serverSecretResp.length < 16) {
        debugPrint('Sunshine pairing response lacked a valid pairingsecret');
        return SunshinePairResult.serverChallengeResponseFailed;
      }
      final serverSecret = Uint8List.fromList(serverSecretResp.sublist(0, 16));
      final serverSignature = Uint8List.fromList(serverSecretResp.sublist(16));

      if (!SunshineCrypto.verifySha256Rsa(
        serverSecret,
        serverSignature,
        serverPublicKey,
      )) {
        debugPrint('Sunshine pairing server signature verification failed');
        return SunshinePairResult.serverChallengeResponseFailed;
      }

      final expectedHashInput = SunshineCrypto.concat([
        randomChallenge,
        serverCertSig,
        serverSecret,
      ]);
      final expectedHash = useSha256
          ? SunshineCrypto.sha256(expectedHashInput)
          : SunshineCrypto.sha1(expectedHashInput);
      if (!_bytesEqual(expectedHash, serverResponse)) {
        debugPrint('Sunshine pairing PIN verification failed');
        return SunshinePairResult.pinWrong;
      }

      // Phase 4 — clientpairingsecret
      final clientPairingSecret = SunshineCrypto.concat([
        clientSecret,
        SunshineCrypto.signSha256Rsa(clientSecret, crypto.privateKey),
      ]);
      final clientSecretXml = await _httpGet(
        pairClient,
        _pairUri(
          'http',
          ip,
          clientId,
          _pairParameters(clientId, deviceName, {
            'clientpairingsecret': SunshineCrypto.bytesToHex(
              clientPairingSecret,
            ),
          }),
        ),
        timeout: const Duration(seconds: 10),
      );
      if (clientSecretXml == null ||
          _xmlValue(clientSecretXml, 'paired') != '1') {
        debugPrint('Sunshine pairing failed during clientpairingsecret');
        return SunshinePairResult.clientPairingSecretFailed;
      }

      // Sunshine has now accepted and stored this client identity. Remember
      // the pairing before the optional final HTTPS confirmation, since the
      // HTTP PairStatus can incorrectly continue to report 0 for this client.
      clientCertificateStored = true;
      await CacheService().setSunshineIp(ip);
      await CacheService().setSunshinePaired(true);

      // Phase 5 — initial TLS challenge, which confirms the paired certificate.
      final pairChallengeXml = await _httpGet(
        pairClient,
        _pairUri(
          'https',
          ip,
          clientId,
          _pairParameters(clientId, deviceName, {'phrase': 'pairchallenge'}),
        ),
        timeout: const Duration(seconds: 10),
      );
      if (pairChallengeXml == null ||
          _xmlValue(pairChallengeXml, 'paired') != '1') {
        debugPrint('Sunshine pairing failed during pairchallenge');
        return SunshinePairResult.finalChallengeFailed;
      }

      await CacheService().setSunshineIp(ip);
      await CacheService().setSunshinePaired(true);
      pairingSucceeded = true;
      return SunshinePairResult.success;
    } catch (e, st) {
      debugPrint('Sunshine pairing handshake error: $e\n$st');
      return SunshinePairResult.failed;
    } finally {
      // Moonlight clears incomplete server-side pairing sessions so retries
      // don't inherit an out-of-order/stale handshake state.
      if (!pairingSucceeded && !clientCertificateStored) {
        final failureDiagnostic = lastPairDiagnostic;
        final cleanupClient = _createHttpClient(
          timeout: const Duration(seconds: 5),
        );
        try {
          await _httpGet(
            cleanupClient,
            _unpairUri(ip, clientId),
            timeout: const Duration(seconds: 5),
          );
        } catch (e) {
          debugPrint('Sunshine failed-pair cleanup failed: $e');
        } finally {
          cleanupClient.close(force: true);
        }
        lastPairDiagnostic = failureDiagnostic;
      }
      pairClient.close(force: true);
      _activePairingClient = null;
      _pairingCancelRequested = false;
      if (identical(_activePairingDone, pairingDone)) {
        _activePairingDone = null;
      }
      if (!pairingDone.isCompleted) pairingDone.complete();
    }
  }

  /// Backwards-compatible wrapper used by older dialogs.
  Future<bool> initiatePairing({
    required String ip,
    required String pin,
  }) async {
    final result = await pair(ip: ip, pin: pin);
    return result == SunshinePairResult.success;
  }

  /// Launch Desktop using the paired client certificate and return the
  /// negotiated GameStream details for the Android Moonlight core.
  Future<SunshineStreamSession> startStreamSession({String? ip}) async {
    final target = getTargetIp(ip);
    if (target.isEmpty) throw StateError('No Sunshine host is selected.');

    final crypto = SunshineCrypto();
    await crypto.ensureReady();
    final clientId = getClientId();
    final client = _createHttpClient(
      timeout: const Duration(seconds: 8),
      clientIdentity: crypto,
    );
    try {
      final serverInfoXml = await _getHttpsText(
        client,
        Uri.https('$target:47984', '/serverinfo', {'uniqueid': clientId}),
      );
      final info = SunshineServerInfo.fromXml(serverInfoXml);
      if (!info.isOnline ||
          (!info.isPaired &&
              !(CacheService().getSunshineIp().trim() == target &&
                  CacheService().getSunshinePaired()))) {
        throw StateError('This phone is not paired with ${info.hostname}.');
      }

      final appsXml = await _getHttpsText(
        client,
        Uri.https('$target:47984', '/applist', {'uniqueid': clientId}),
      );
      final apps = <SunshineApp>[];
      for (final match in RegExp(
        '<App>(.*?)</App>',
        dotAll: true,
      ).allMatches(appsXml)) {
        final node = match.group(1) ?? '';
        final title = RegExp(
          '<AppTitle>(.*?)</AppTitle>',
          dotAll: true,
        ).firstMatch(node)?.group(1)?.trim();
        final id = RegExp(
          '<ID>(.*?)</ID>',
          dotAll: true,
        ).firstMatch(node)?.group(1)?.trim();
        if (title != null && id != null && id.isNotEmpty) {
          apps.add(SunshineApp(title: title, id: id));
        }
      }
      final desktopApps = apps.where(
        (app) => app.title.toLowerCase() == 'desktop',
      );
      final desktop = desktopApps.isNotEmpty
          ? desktopApps.first
          : (apps.isNotEmpty
                ? apps.first
                : const SunshineApp(title: 'Desktop', id: '1'));

      final width = CacheService().getSunshineResolution() == '720p'
          ? 1280
          : 1920;
      final height = width == 1280 ? 720 : 1080;
      final fps = CacheService().getSunshineFps();
      final bitrate = CacheService().getSunshineBitrate();
      final remoteInputKey = SunshineCrypto.randomBytes(16);
      final keyIdBytes = SunshineCrypto.randomBytes(4);
      // GameStream defines rikeyid as an unsigned 32-bit value. Treating it
      // as signed makes half of generated IDs negative, which Sunshine rejects.
      final keyId = ByteData.sublistView(keyIdBytes).getUint32(0, Endian.big);
      final remoteInputIv = Uint8List(16);
      ByteData.sublistView(remoteInputIv).setUint32(0, keyId, Endian.big);
      final launchParameters = <String, String>{
        'uuid': SunshineCrypto.bytesToHex(SunshineCrypto.randomBytes(16)),
        'appid': desktop.id,
        'mode': '${width}x${height}x$fps',
        'additionalStates': '1',
        'sops': '0',
        'rikey': SunshineCrypto.bytesToHex(remoteInputKey),
        'rikeyid': keyId.toString(),
        'localAudioPlayMode': '1',
        'surroundAudioInfo': ((0x3 << 16) | 2).toString(),
        'remoteControllersBitmap': '0',
        'gcmap': '0',
        'gcpersist': '0',
        'corever': '1',
        'uniqueid': clientId,
      };
      var sessionXml = await _getHttpsText(
        client,
        Uri.https('$target:47984', '/launch', launchParameters),
      );
      var sessionStarted = _xmlValue(sessionXml, 'gamesession');

      if (sessionStarted.isEmpty || sessionStarted == '0') {
        final launchStatusMessage = _xmlAttribute(
          sessionXml,
          'status_message',
        ).toLowerCase();
        // The previous launch may have succeeded while this client failed to
        // finish connecting. Sunshine rejects a second /launch in that state;
        // /resume attaches this client to the already-running Desktop session.
        if (launchStatusMessage.contains('already running')) {
          final resumeParameters = Map<String, String>.from(launchParameters)
            ..remove('appid')
            ..['uuid'] = SunshineCrypto.bytesToHex(
              SunshineCrypto.randomBytes(16),
            );
          sessionXml = await _getHttpsText(
            client,
            Uri.https('$target:47984', '/resume', resumeParameters),
          );
          sessionStarted = _xmlValue(sessionXml, 'resume');
        }
      }

      if (sessionStarted.isEmpty || sessionStarted == '0') {
        final statusCode = _xmlAttribute(sessionXml, 'status_code');
        final statusMessage = _xmlAttribute(sessionXml, 'status_message');
        final details = [
          if (statusCode.isNotEmpty) 'code $statusCode',
          if (statusMessage.isNotEmpty) statusMessage,
        ].join(': ');
        throw StateError(
          details.isEmpty
              ? 'Sunshine did not start or resume the Desktop session.'
              : 'Sunshine could not start or resume the Desktop session ($details).',
        );
      }

      return SunshineStreamSession(
        host: target,
        appVersion: info.appVersion,
        gfeVersion: info.gfeVersion,
        codecModeSupport: info.codecModeSupport,
        sessionUrl: _xmlValue(sessionXml, 'sessionUrl0'),
        width: width,
        height: height,
        fps: fps,
        bitrate: bitrate,
        preferHevc: CacheService().getSunshineHevc(),
        remoteInputKey: remoteInputKey,
        remoteInputIv: remoteInputIv,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _getHttpsText(HttpClient client, Uri uri) async {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 8));
    request.persistentConnection = false;
    final response = await request.close().timeout(const Duration(seconds: 8));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Sunshine returned HTTP ${response.statusCode} for ${uri.path}.',
        uri: uri,
      );
    }
    return body;
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Fetch list of available streaming apps from Sunshine.
  Future<List<SunshineApp>> fetchAppList({String? ip}) async {
    final target = getTargetIp(ip);
    if (target.isEmpty) return const [SunshineApp(title: 'Desktop', id: '1')];

    final clientId = getClientId();
    final client = _createHttpClient(timeout: const Duration(seconds: 3));

    try {
      final uri = Uri.parse('http://$target:47989/applist?uniqueid=$clientId');
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 3));
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      if (response.statusCode == 200) {
        final xml = await response.transform(utf8.decoder).join();
        final apps = <SunshineApp>[];
        final appMatches = RegExp(
          '<App>(.*?)</App>',
          dotAll: true,
        ).allMatches(xml);
        for (final m in appMatches) {
          final content = m.group(1) ?? '';
          final titleMatch = RegExp(
            '<AppTitle>(.*?)</AppTitle>',
          ).firstMatch(content);
          final idMatch = RegExp('<ID>(.*?)</ID>').firstMatch(content);
          if (titleMatch != null && idMatch != null) {
            apps.add(
              SunshineApp(
                title: titleMatch.group(1)?.trim() ?? 'Unknown',
                id: idMatch.group(1)?.trim() ?? '',
              ),
            );
          }
        }
        if (apps.isNotEmpty) return apps;
      }
    } catch (e) {
      debugPrint("Error fetching applist: $e");
    } finally {
      client.close();
    }

    return const [SunshineApp(title: 'Desktop', id: '1')];
  }

  /// Launch a stream session on Sunshine.
  Future<bool> launchApp({
    String appName = 'Desktop',
    String? ip,
    int? width,
    int? height,
    int? fps,
    int? bitrate,
  }) async {
    final target = getTargetIp(ip);
    if (target.isEmpty) return false;

    final clientId = getClientId();
    final client = _createHttpClient(timeout: const Duration(seconds: 4));

    final w =
        width ??
        (CacheService().getSunshineResolution() == '720p' ? 1280 : 1920);
    final h =
        height ??
        (CacheService().getSunshineResolution() == '720p' ? 720 : 1080);
    final frameRate = fps ?? CacheService().getSunshineFps();
    final bitRate = bitrate ?? CacheService().getSunshineBitrate();

    try {
      final encodedApp = Uri.encodeComponent(appName);
      final uri = Uri.parse(
        'http://$target:47989/launch?app=$encodedApp&mode=${w}x${h}x${frameRate}&bitrate=$bitRate&uniqueid=$clientId',
      );
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 4));
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Error launching Sunshine session: $e");
      return false;
    } finally {
      client.close();
    }
  }

  /// Cancel an active streaming session.
  Future<bool> cancelSession({String? ip}) async {
    final target = getTargetIp(ip);
    if (target.isEmpty) return false;

    final clientId = getClientId();
    final client = _createHttpClient(timeout: const Duration(seconds: 3));

    try {
      final uri = Uri.parse('http://$target:47989/cancel?uniqueid=$clientId');
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 3));
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Error canceling Sunshine session: $e");
      return false;
    } finally {
      client.close();
    }
  }
}
