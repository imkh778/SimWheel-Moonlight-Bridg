import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'sunshine_service.dart';

Future<bool?> showSunshinePairingDialog(
  BuildContext context, {
  required String targetIp,
}) async {
  return await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => SunshinePairingDialog(targetIp: targetIp),
  );
}

class SunshinePairingDialog extends StatefulWidget {
  final String targetIp;

  const SunshinePairingDialog({super.key, required this.targetIp});

  @override
  State<SunshinePairingDialog> createState() => _SunshinePairingDialogState();
}

class _SunshinePairingDialogState extends State<SunshinePairingDialog> {
  late String _pin;
  bool _isPairing = false;
  bool _isSuccess = false;
  String _statusMessage = 'Ready to pair';

  @override
  void initState() {
    super.initState();
    _pin = SunshineService().generatePin();
    _startPairingProcess();
  }

  void _startPairingProcess() async {
    setState(() {
      _isPairing = true;
      _isSuccess = false;
      _statusMessage = 'Enter PIN in Sunshine Web UI — keep this screen open…';
    });

    final sunshine = SunshineService();
    final result = await sunshine.pair(
      ip: widget.targetIp,
      pin: _pin,
      deviceName: 'SimWheel',
    );

    if (!mounted) return;

    switch (result) {
      case SunshinePairResult.success:
        setState(() {
          _isPairing = false;
          _isSuccess = true;
          _statusMessage = 'Successfully paired!';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      case SunshinePairResult.pinWrong:
        setState(() {
          _isPairing = false;
          _statusMessage = 'Wrong PIN. Tap New PIN and try again.';
        });
      case SunshinePairResult.alreadyInProgress:
        setState(() {
          _isPairing = false;
          _statusMessage = 'Another device is pairing. Wait and try again.';
        });
      case SunshinePairResult.timedOut:
        setState(() {
          _isPairing = false;
          _statusMessage = 'Timed out waiting for PIN on PC.';
        });
      case SunshinePairResult.clientChallengeFailed:
        setState(() {
          _isPairing = false;
          _statusMessage =
              'Sunshine did not accept the PIN. Generate a new one.';
        });
      case SunshinePairResult.serverChallengeResponseTransportFailed:
        setState(() {
          _isPairing = false;
          final detail = sunshine.lastPairDiagnostic;
          _statusMessage =
              detail == null
                  ? 'Connection dropped during pairing. Wait, then try a new PIN.'
                  : 'Connection dropped during server challenge ($detail). Check the Sunshine log.';
        });
      case SunshinePairResult.serverChallengeResponseFailed:
        setState(() {
          _isPairing = false;
          _statusMessage =
              'Sunshine rejected a pairing response. Check its log.';
        });
      case SunshinePairResult.clientPairingSecretFailed:
        setState(() {
          _isPairing = false;
          _statusMessage = 'Sunshine rejected the phone certificate.';
        });
      case SunshinePairResult.finalChallengeFailed:
        setState(() {
          _isPairing = false;
          final detail = sunshine.lastPairDiagnostic;
          _statusMessage =
              detail == null
                  ? 'The final Sunshine HTTPS check failed.'
                  : 'Final HTTPS check failed ($detail). Check Sunshine’s log.';
        });
      case SunshinePairResult.failed:
        setState(() {
          _isPairing = false;
          _statusMessage = 'Pairing failed. Is Sunshine running?';
        });
    }
  }

  void _regeneratePin() {
    setState(() {
      _pin = SunshineService().generatePin();
      _isSuccess = false;
    });
    _startPairingProcess();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isSmallScreen = screenWidth < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Container(
        width: isSmallScreen ? screenWidth * 0.9 : 480,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                _isSuccess
                    ? Colors.greenAccent.withValues(alpha: 0.6)
                    : Colors.blueAccent.withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: (_isSuccess ? Colors.greenAccent : Colors.blueAccent)
                  .withValues(alpha: 0.15),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (_isSuccess ? Colors.greenAccent : Colors.blueAccent)
                    .withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isSuccess ? Icons.check_circle_rounded : Icons.tv_rounded,
                color: _isSuccess ? Colors.greenAccent : Colors.blueAccent,
                size: 38,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _isSuccess ? 'Pairing Successful!' : 'Pair with Sunshine',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Host IP: ${widget.targetIp}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            if (!_isSuccess) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 24,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.blueAccent.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children:
                      _pin.split('').map((digit) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.blueAccent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            digit,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStepRow("1", "Open Sunshine Web UI on your PC"),
                    const SizedBox(height: 6),
                    _buildStepRow(
                      "2",
                      "Go to PIN tab: https://localhost:47990/pin",
                    ),
                    const SizedBox(height: 6),
                    _buildStepRow(
                      "3",
                      'Name: "SimWheel", enter PIN above, click Send',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
                  Flexible(
                    child: Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                if (!_isSuccess) ...[
                  TextButton.icon(
                    onPressed: _isPairing ? null : _regeneratePin,
                    icon: const Icon(
                      Icons.refresh,
                      size: 16,
                      color: Colors.white70,
                    ),
                    label: const Text(
                      "New PIN",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _pin));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("PIN copied to clipboard"),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueAccent,
                      side: BorderSide(
                        color: Colors.blueAccent.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text("Copy PIN"),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_isSuccess),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isSuccess ? Colors.greenAccent : Colors.blueAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(_isSuccess ? "Done" : "Cancel"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(String stepNumber, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.blueAccent.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Text(
            stepNumber,
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
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}
