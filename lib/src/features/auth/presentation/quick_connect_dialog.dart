import 'dart:async';

import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QuickConnectDialog extends StatefulWidget {
  const QuickConnectDialog({
    super.key,
    required this.serverUri,
    required this.service,
  });

  final Uri serverUri;
  final MediaLibraryService service;

  @override
  State<QuickConnectDialog> createState() => _QuickConnectDialogState();
}

class _QuickConnectDialogState extends State<QuickConnectDialog> {
  QuickConnectInitResult? _initResult;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startQuickConnect();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startQuickConnect() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await widget.service.initiateQuickConnect(widget.serverUri);
    if (!mounted) return;

    if (res == null || res.code.isEmpty || res.secret.isEmpty) {
      setState(() {
        _loading = false;
        _error = '服务器未开启 Quick Connect 快捷登录支持。';
      });
      return;
    }

    setState(() {
      _initResult = res;
      _loading = false;
    });

    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollState(),
    );
  }

  Future<void> _pollState() async {
    final secret = _initResult?.secret;
    if (secret == null || !mounted) return;

    final state = await widget.service.checkQuickConnectState(
      widget.serverUri,
      secret,
    );
    if (!mounted) return;

    if (state != null && state.authenticated) {
      _pollTimer?.cancel();
      Navigator.of(context).pop(state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _initResult?.code ?? '';
    final qrData = '${widget.serverUri}/web/#/quickconnect?code=$code';

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.qr_code_scanner_rounded, color: AppColors.spotlight),
          SizedBox(width: 10),
          Text('Quick Connect 扫码登录'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading) ...[
              const SizedBox(height: 40),
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('正在初始化 Quick Connect 会话...'),
              const SizedBox(height: 40),
            ] else if (_error != null) ...[
              const SizedBox(height: 20),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
            ] else ...[
              const Text(
                '请使用手机客户端扫码或输入以下验证码',
                style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.spotlight.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.spotlight.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: AppColors.spotlight,
                    fontFamily: 'Cascadia Mono',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 180.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.spotlight,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '等待客户端授权中...',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
