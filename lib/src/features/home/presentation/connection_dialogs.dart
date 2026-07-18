import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/servers/data/server_authentication_service.dart';
import 'package:embyplayer/src/features/servers/data/server_discovery_service.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AddServerDialog extends ConsumerStatefulWidget {
  const AddServerDialog({super.key});

  @override
  ConsumerState<AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends ConsumerState<AddServerDialog> {
  final _addressController = TextEditingController(
    text: 'http://127.0.0.1:8096',
  );
  final _addressFocus = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _addressController.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final server = await ref
          .read(serverDiscoveryProvider)
          .discover(_addressController.text);
      if (mounted) Navigator.of(context).pop(server);
    } on ServerDiscoveryException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
        _addressFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      titlePadding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
      contentPadding: const EdgeInsets.fromLTRB(28, 22, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      title: const _DialogTitle(
        step: '步骤 1 / 2',
        icon: Icons.add_link_rounded,
        title: '添加媒体服务器',
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入 Jellyfin 或 Emby 的访问地址。我们会自动识别服务类型与 API 路径。',
              style: TextStyle(color: AppColors.textSecondary, height: 1.55),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _addressController,
              focusNode: _addressFocus,
              autofocus: true,
              enabled: !_loading,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_loading) _discover();
              },
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'http://192.168.1.20:8096',
                helperText: '支持域名、IP、端口和反向代理路径',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              InlineFormError(message: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : _discover,
          icon: _loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_forward_rounded),
          label: Text(_loading ? '正在检测' : '检测并继续'),
        ),
      ],
    );
  }
}

class LoginDialog extends ConsumerStatefulWidget {
  const LoginDialog({super.key, required this.server});

  final DiscoveredServer server;

  @override
  ConsumerState<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends ConsumerState<LoginDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  bool _loading = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final account = await ref
          .read(serverAuthenticationProvider)
          .login(
            server: widget.server,
            username: _usernameController.text,
            password: _passwordController.text,
          );
      if (mounted) Navigator.of(context).pop(account);
    } on ServerAuthenticationException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
        _usernameFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      titlePadding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
      contentPadding: const EdgeInsets.fromLTRB(28, 22, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      title: _DialogTitle(
        step: '步骤 2 / 2',
        icon: Icons.lock_open_rounded,
        title: '登录 ${widget.server.name}',
      ),
      content: SizedBox(
        width: 480,
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServerBadge(server: widget.server),
              const SizedBox(height: 24),
              TextField(
                controller: _usernameController,
                focusNode: _usernameFocus,
                autofocus: true,
                enabled: !_loading,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                enabled: !_loading,
                obscureText: !_showPassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_loading) _login();
                },
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? '隐藏密码' : '显示密码',
                    onPressed: _loading
                        ? null
                        : () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                InlineFormError(message: _error!),
              ],
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 17,
                    color: AppColors.textTertiary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '密码不会保存；登录令牌由 Windows 安全存储保管，下次启动会自动恢复会话。',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('返回'),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : _login,
          icon: _loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login_rounded),
          label: Text(_loading ? '正在登录' : '安全登录'),
        ),
      ],
    );
  }
}

class _DialogTitle extends StatelessWidget {
  const _DialogTitle({
    required this.step,
    required this.icon,
    required this.title,
  });

  final String step;
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.spotlight, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 4),
              Text(title),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServerBadge extends StatelessWidget {
  const _ServerBadge({required this.server});

  final DiscoveredServer server;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${server.kind.label} ${server.version}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  server.apiBaseUri.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InlineFormError extends StatelessWidget {
  const InlineFormError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.error.withValues(alpha: 0.14),
              blurRadius: 18,
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 19,
              color: AppColors.error,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppColors.error, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
