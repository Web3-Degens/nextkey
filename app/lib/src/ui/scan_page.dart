import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// One camera screen, returning whatever was in the code. It does not decide
/// what the string means — the caller does, because a pairing code, an ENS name
/// and a NextKey ID all arrive here and each belongs to a different screen.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (value == null) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),
          if (widget.hint != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(widget.hint!,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}
