import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'sunshine_settings.dart';
import 'sunshine_service.dart';
import 'utils.dart';

/// Full-screen Moonlight-style PC discovery & pairing screen.
class SunshineDiscoveryScreen extends StatefulWidget {
  const SunshineDiscoveryScreen({super.key});

  @override
  State<SunshineDiscoveryScreen> createState() =>
      _SunshineDiscoveryScreenState();
}

class _SunshineDiscoveryScreenState extends State<SunshineDiscoveryScreen>
    with TickerProviderStateMixin {
  final List<DiscoveredSunshineHost> _hosts = [];
  bool _isScanning = false;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _startScan();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _hosts.clear();
    });

    await SunshineService().scanLocalNetwork(
      onHostFound: (host) {
        if (mounted) {
          setState(() {
            final idx = _hosts.indexWhere((h) => h.ip == host.ip);
            if (idx >= 0) {
              _hosts[idx] = host;
            } else {
              _hosts.add(host);
            }
          });
        }
      },
    );

    if (mounted) setState(() => _isScanning = false);
  }

  void _onHostTap(DiscoveredSunshineHost host) {
    if (host.isPaired) {
      // Already paired — save and close
      _selectHost(host);
    } else {
      // Need to pair — show pairing flow
      _showPairingFlow(host);
    }
  }

  void _selectHost(DiscoveredSunshineHost host) async {
    await CacheService().setSunshineIp(host.ip);
    await CacheService().setSunshinePaired(host.isPaired);
    await CacheService().setSunshineEnabled(true);
    if (mounted) {
      Navigator.of(context).pop(host);
    }
  }

  void _showPairingFlow(DiscoveredSunshineHost host) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PairingDialog(
        host: host,
        onPaired: () {
          _selectHost(
            DiscoveredSunshineHost(
              ip: host.ip,
              info: SunshineServerInfo(
                hostname: host.info.hostname,
                appVersion: host.info.appVersion,
                isPaired: true,
                state: host.info.state,
                currentGame: host.info.currentGame,
                httpsPort: host.info.httpsPort,
                httpPort: host.info.httpPort,
                isOnline: true,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _clearSunshinePairing() async {
    final shouldClear = await showConfirmBox(
      context,
      botton: "Clear",
      title: 'Clear Sunshine pairing?',
      s: """This will Clear this phone’s Sunshine pairing. You’ll need to
        pair it with your PC again. Your other app settings and connection
        preferences will stay saved.""",
      color: Colors.redAccent,
      n: 2,
    );
    debugPrint("$shouldClear");
    if (shouldClear != 1 || !mounted) return;

    await CacheService().clearSunshinePairingData();
    if (!mounted) return;
    showSnack(context, 'Cleared Sunshine Pairings', true);
    if (!mounted) return;
    await _startScan();
  }

  void _showAddManualDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Add PC Manually',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your PC\'s IP address to connect directly.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '192.168.1.xxx',
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon: const Icon(
                  Icons.router_outlined,
                  color: Colors.blueAccent,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.07),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blueAccent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final ip = ctrl.text.trim();
              if (ip.isEmpty) return;
              Navigator.pop(ctx);
              // Probe the manually entered IP
              final info = await SunshineService().fetchServerInfo(ip: ip);
              if (!mounted) return;
              if (info.isOnline) {
                final host = DiscoveredSunshineHost(ip: ip, info: info);
                if (!_hosts.any((h) => h.ip == ip)) {
                  setState(() => _hosts.insert(0, host));
                }
                _onHostTap(host);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Cannot reach Sunshine at $ip — is it running?',
                      ),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Connect',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'PC Screen Streaming (BETA)',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.key_off_outlined, color: Colors.redAccent),
            tooltip: 'Clear Sunshine pairing data',
            onPressed: _clearSunshinePairing,
          ),
          // Manual add button
          IconButton(
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: Colors.blueAccent,
            ),
            tooltip: 'Add PC Manually',
            onPressed: _showAddManualDialog,
          ),
          // Refresh / re-scan button
          IconButton(
            icon: _isScanning
                ? _ScanningIcon(controller: _pulseCtrl)
                : const Icon(Icons.refresh_rounded, color: Colors.blueAccent),
            tooltip: _isScanning ? 'Scanning...' : 'Scan Again',
            onPressed: _isScanning ? null : _startScan,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.black, Colors.black87],
          ),
        ),
        child: Column(
          children: [
            // Status bar
            _buildStatusBar(),
            // PC grid / list
            Expanded(
              child: _hosts.isEmpty ? _buildEmptyState() : _buildHostGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: _isScanning
            ? Colors.blueAccent.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.03),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          if (_isScanning) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(
                  Colors.blueAccent.withValues(alpha: 0.8),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _hosts.isEmpty
                  ? 'Scanning network for Sunshine PCs...'
                  : 'Found ${_hosts.length} PC${_hosts.length == 1 ? '' : 's'} — still scanning...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ] else ...[
            Icon(
              _hosts.isEmpty
                  ? Icons.search_off_rounded
                  : Icons.check_circle_outline,
              size: 16,
              color: _hosts.isEmpty ? Colors.white38 : Colors.greenAccent,
            ),
            const SizedBox(width: 10),
            Text(
              _hosts.isEmpty
                  ? 'No Sunshine PCs found on this network'
                  : '${_hosts.length} PC${_hosts.length == 1 ? '' : 's'} found — tap to connect',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, child) {
              final scale = _isScanning ? 0.9 + (_pulseCtrl.value * 0.2) : 1.0;
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withValues(alpha: 0.08),
                border: Border.all(
                  color: Colors.blueAccent.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.desktop_windows_outlined,
                size: 64,
                color: Colors.blueAccent,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            _isScanning ? 'Searching for\nSunshine hosts...' : 'No PCs Found',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              _isScanning
                  ? 'Make sure Sunshine is running on your PC and both devices are on the same Wi-Fi network.'
                  : 'Make sure Sunshine is installed and running on your PC. Both devices must be on the same Wi-Fi network.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 32),
          if (!_isScanning)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Scan Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _showAddManualDialog,
                  icon: const Icon(
                    Icons.add,
                    size: 18,
                    color: Colors.blueAccent,
                  ),
                  label: const Text(
                    'Add Manually',
                    style: TextStyle(color: Colors.blueAccent),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blueAccent),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHostGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: _hosts.length,
      itemBuilder: (context, i) =>
          _HostCard(host: _hosts[i], onTap: () => _onHostTap(_hosts[i])),
    );
  }
}

// ------------------------------------------------------------------
// Host Card Widget
// ------------------------------------------------------------------
class _HostCard extends StatelessWidget {
  final DiscoveredSunshineHost host;
  final VoidCallback onTap;

  const _HostCard({required this.host, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPaired = host.isPaired;
    final isStreaming = host.stateLabel == 'Streaming';

    final cardColor = isPaired
        ? Colors.blueAccent.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.05);
    final borderColor = isPaired
        ? Colors.blueAccent.withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.12);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: isPaired
              ? [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Monitor icon
            Stack(
              alignment: Alignment.topRight,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isPaired
                        ? Colors.blueAccent.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.desktop_windows_rounded,
                    size: 36,
                    color: isPaired ? Colors.blueAccent : Colors.white38,
                  ),
                ),
                if (isStreaming)
                  Container(
                    margin: const EdgeInsets.only(top: 2, right: 2),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0D1117),
                        width: 2,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // PC Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                host.displayName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isPaired ? Colors.white : Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: isPaired
                    ? (isStreaming
                          ? Colors.greenAccent.withValues(alpha: 0.15)
                          : Colors.blueAccent.withValues(alpha: 0.15))
                    : Colors.orangeAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPaired
                        ? (isStreaming
                              ? Icons.cast_connected
                              : Icons.check_circle_rounded)
                        : Icons.link_off_rounded,
                    size: 10,
                    color: isPaired
                        ? (isStreaming ? Colors.greenAccent : Colors.blueAccent)
                        : Colors.orangeAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isPaired
                        ? (isStreaming ? 'Streaming' : 'Paired')
                        : 'Tap to Pair',
                    style: TextStyle(
                      color: isPaired
                          ? (isStreaming
                                ? Colors.greenAccent
                                : Colors.blueAccent)
                          : Colors.orangeAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Scanning animated icon
// ------------------------------------------------------------------
class _ScanningIcon extends StatelessWidget {
  final AnimationController controller;
  const _ScanningIcon({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Transform.rotate(
        angle: controller.value * 2 * 3.14159,
        child: const Icon(Icons.radar_rounded, color: Colors.blueAccent),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Pairing Dialog — shows PIN & polls until Sunshine confirms paired
// ------------------------------------------------------------------
class _PairingDialog extends StatefulWidget {
  final DiscoveredSunshineHost host;
  final VoidCallback onPaired;

  const _PairingDialog({required this.host, required this.onPaired});

  @override
  State<_PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<_PairingDialog> {
  late String _pin;
  bool _isPairing = true;
  bool _isSuccess = false;
  bool _isFailed = false;
  bool _isCancelling = false;
  String _statusText = 'Preparing secure pairing...';

  @override
  void initState() {
    super.initState();
    _pin = SunshineService().generatePin();
    _startPairing();
  }

  void _startPairing() async {
    setState(() {
      _isPairing = true;
      _isFailed = false;
      _isSuccess = false;
      _statusText = 'Enter this PIN in Sunshine on your PC now…';
    });

    final sunshine = SunshineService();
    final result = await sunshine.pair(
      ip: widget.host.ip,
      pin: _pin,
      deviceName: 'SimWheel',
    );

    if (!mounted) return;

    switch (result) {
      case SunshinePairResult.success:
        setState(() {
          _isPairing = false;
          _isSuccess = true;
          _statusText = 'Successfully paired with ${widget.host.displayName}!';
        });
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pop();
            widget.onPaired();
          }
        });
      case SunshinePairResult.pinWrong:
        setState(() {
          _isPairing = false;
          _isFailed = true;
          _statusText = 'Wrong PIN. Generate a new PIN and try again.';
        });
      case SunshinePairResult.alreadyInProgress:
        setState(() {
          _isPairing = false;
          _isFailed = true;
          _statusText = 'Another device is pairing. Wait and try again.';
        });
      case SunshinePairResult.timedOut:
        setState(() {
          _isPairing = false;
          _isFailed = true;
          _statusText = 'Timed out waiting for PIN on PC. Try again.';
        });
      case SunshinePairResult.clientChallengeFailed:
        setState(() {
          _isPairing = false;
          _isFailed = true;
          _statusText =
              'PIN was not accepted by Sunshine. Generate a new PIN and retry.';
        });
      case SunshinePairResult.serverChallengeResponseTransportFailed:
        setState(() {
          _isPairing = false;
          _isFailed = true;
          final detail = sunshine.lastPairDiagnostic;
          _statusText = detail == null
              ? 'Connection to Sunshine dropped during pairing. Wait a few seconds, then retry with a new PIN.'
              : 'Connection dropped during server challenge ($detail). Check the Sunshine log, then retry with a new PIN.';
        });
      case SunshinePairResult.serverChallengeResponseFailed:
        setState(() {
          _isPairing = false;
          _isFailed = true;
          _statusText =
              'Sunshine rejected a pairing response. Check its log for a protocol error.';
        });
      case SunshinePairResult.clientPairingSecretFailed:
        setState(() {
          _isPairing = false;
          _isFailed = true;
          _statusText =
              'Sunshine accepted the PIN but rejected the phone certificate. Try again.';
        });
      case SunshinePairResult.finalChallengeFailed:
        setState(() {
          _isPairing = false;
          _isFailed = true;
          final detail = sunshine.lastPairDiagnostic;
          _statusText = detail == null
              ? 'Pairing was nearly complete, but Sunshine did not confirm the final HTTPS check.'
              : 'Final HTTPS check failed ($detail). Check Sunshine’s log before retrying.';
        });
      case SunshinePairResult.failed:
        setState(() {
          _isPairing = false;
          _isFailed = true;
          _statusText =
              'Pairing failed before PIN verification. Check the app log and Sunshine.';
        });
    }
  }

  void _retry() {
    setState(() => _pin = SunshineService().generatePin());
    _startPairing();
  }

  Future<void> _cancelPairing() async {
    if (_isCancelling) return;
    setState(() => _isCancelling = true);
    await SunshineService().cancelPairing();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final compactLayout = screenHeight < 700;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: compactLayout ? 12 : 32,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: screenHeight - (compactLayout ? 24 : 64),
        ),
        padding: EdgeInsets.all(compactLayout ? 16 : 28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1a1a2e), Color(0xFF0D1117)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _isSuccess
                ? Colors.greenAccent.withValues(alpha: 0.5)
                : Colors.blueAccent.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: (_isSuccess ? Colors.greenAccent : Colors.blueAccent)
                  .withValues(alpha: 0.12),
              blurRadius: 40,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (_isSuccess ? Colors.greenAccent : Colors.blueAccent)
                      .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isSuccess
                      ? Icons.check_circle_rounded
                      : Icons.desktop_windows_rounded,
                  color: _isSuccess ? Colors.greenAccent : Colors.blueAccent,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),

              // PC name
              Text(
                _isSuccess ? 'Paired!' : widget.host.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.host.ip,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 24),

              if (!_isSuccess && !_isFailed) ...[
                // PIN display
                Text(
                  'Enter this PIN in Sunshine on your PC',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _pin
                      .split('')
                      .map((d) => _PinDigit(digit: d))
                      .toList(),
                ),
                const SizedBox(height: 20),

                // Steps
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StepRow(
                        step: '1',
                        text: 'Open Sunshine on your PC (tray icon)',
                      ),
                      const SizedBox(height: 6),
                      _StepRow(
                        step: '2',
                        text: 'Open PIN page: https://localhost:47990/pin',
                      ),
                      const SizedBox(height: 6),
                      _StepRow(
                        step: '3',
                        text:
                            'Type name "SimWheel" and enter the PIN above. Click Send once; keep this screen open.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Status row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isPairing)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.blueAccent),
                        ),
                      ),
                    if (_isPairing) const SizedBox(width: 8),
                    Text(
                      _statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ] else if (_isSuccess) ...[
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else if (_isFailed) ...[
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                ),
              ],

              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  if (!_isSuccess) ...[
                    if (!_isFailed)
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _pin));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('PIN copied'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.copy,
                          size: 18,
                          color: Colors.white54,
                        ),
                        tooltip: 'Copy PIN',
                      ),
                    const Spacer(),
                    if (_isFailed)
                      TextButton(
                        onPressed: _retry,
                        child: const Text(
                          'Try Again',
                          style: TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    OutlinedButton(
                      onPressed: _isCancelling ? null : _cancelPairing,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      child: Text(_isCancelling ? 'Stopping…' : 'Cancel'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinDigit extends StatelessWidget {
  final String digit;
  const _PinDigit({required this.digit});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5),
      width: 52,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blueAccent.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Text(
        digit,
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String step;
  final String text;
  const _StepRow({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.blueAccent.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Text(
            step,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
