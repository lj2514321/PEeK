import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:embyplayer/src/features/settings/presentation/playback_settings_section.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';

class ServerAccountsPage extends StatelessWidget {
  const ServerAccountsPage({
    super.key,
    required this.state,
    required this.onAddServer,
    required this.onSwitch,
    required this.onLogin,
    required this.onLogout,
    required this.onRemove,
    required this.onGoHome,
    this.playbackSettings = const PlaybackSettings(),
    this.playbackSettingsLoading = false,
    this.playbackSettingsSaving = false,
    this.playbackSettingsError,
    this.onPlaybackBitrateChanged,
    this.busyProfileId,
  });

  final ServerAccountState state;
  final VoidCallback onAddServer;
  final Future<void> Function(ServerAccountEntry account) onSwitch;
  final Future<void> Function(ServerAccountEntry account) onLogin;
  final Future<void> Function(ServerAccountEntry account) onLogout;
  final Future<void> Function(ServerAccountEntry account) onRemove;
  final VoidCallback onGoHome;
  final PlaybackSettings playbackSettings;
  final bool playbackSettingsLoading;
  final bool playbackSettingsSaving;
  final String? playbackSettingsError;
  final ValueChanged<PlaybackBitrate>? onPlaybackBitrateChanged;
  final String? busyProfileId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final padding = compact ? 20.0 : 32.0;
        final activeId = state.activeSession?.profileId;
        final accounts = [...state.accounts]
          ..sort((first, second) {
            if (first.profile.id == activeId) return -1;
            if (second.profile.id == activeId) return 1;
            if (first.signedIn != second.signedIn) {
              return first.signedIn ? -1 : 1;
            }
            return first.profile.name.compareTo(second.profile.name);
          });

        return SingleChildScrollView(
          key: const ValueKey('server-accounts-page'),
          padding: EdgeInsets.fromLTRB(padding, 32, padding, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PageHeader(compact: compact, onAddServer: onAddServer),
                  const SizedBox(height: 24),
                  PlaybackSettingsSection(
                    settings: playbackSettings,
                    loading: playbackSettingsLoading,
                    saving: playbackSettingsSaving,
                    error: playbackSettingsError,
                    onBitrateChanged: onPlaybackBitrateChanged,
                  ),
                  const SizedBox(height: 32),
                  Text('服务器与账户', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  _ActiveSourceStage(
                    state: state,
                    compact: compact,
                    onAddServer: onAddServer,
                    onGoHome: onGoHome,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已保存的放映源',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Text(
                        '${accounts.length} 个账户',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (accounts.isEmpty)
                    _EmptyAccounts(onAddServer: onAddServer)
                  else
                    for (var index = 0; index < accounts.length; index++) ...[
                      _ServerAccountCard(
                        account: accounts[index],
                        active: accounts[index].profile.id == activeId,
                        compact: compact,
                        busy: accounts[index].profile.id == busyProfileId,
                        onSwitch: () => onSwitch(accounts[index]),
                        onLogin: () => onLogin(accounts[index]),
                        onLogout: () =>
                            _confirmLogout(context, accounts[index]),
                        onRemove: () =>
                            _confirmRemove(context, accounts[index]),
                      ),
                      if (index != accounts.length - 1)
                        const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 24),
                  const _SecurityNote(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout(
    BuildContext context,
    ServerAccountEntry account,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出这个账号？'),
        content: Text(
          '将从本机删除 ${account.profile.userName} 的登录令牌，'
          '但会保留 ${account.profile.name} 的服务器资料，之后可以重新登录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出账号'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onLogout(account);
  }

  Future<void> _confirmRemove(
    BuildContext context,
    ServerAccountEntry account,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除服务器资料？'),
        content: Text(
          '将从 PEeK 移除 ${account.profile.name} / '
          '${account.profile.userName}，并删除本机保存的登录令牌。'
          '服务器上的媒体和观看记录不会被删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.canvas,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认移除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onRemove(account);
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.compact, required this.onAddServer});

  final bool compact;
  final VoidCallback onAddServer;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PROJECTION SOURCES',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.spotlight),
        ),
        const SizedBox(height: 8),
        Text('设置', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          '调整播放质量，并管理保存在这台设备上的 Jellyfin 与 Emby 放映源。',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
    final action = FilledButton.icon(
      key: const ValueKey('add-server-from-settings'),
      onPressed: onAddServer,
      icon: const Icon(Icons.add_rounded),
      label: const Text('添加服务器'),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [copy, const SizedBox(height: 20), action],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: copy),
        const SizedBox(width: 24),
        action,
      ],
    );
  }
}

class _ActiveSourceStage extends StatelessWidget {
  const _ActiveSourceStage({
    required this.state,
    required this.compact,
    required this.onAddServer,
    required this.onGoHome,
  });

  final ServerAccountState state;
  final bool compact;
  final VoidCallback onAddServer;
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    final account = state.activeSession;
    final serverCount = state.accounts
        .map((entry) => entry.profile.serverId)
        .toSet()
        .length;
    final glyph = Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: account == null
            ? AppColors.surfaceHigh
            : AppColors.spotlight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        account == null
            ? Icons.settings_input_component_outlined
            : Icons.cell_tower_rounded,
        color: account == null ? AppColors.textTertiary : AppColors.spotlight,
      ),
    );
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          account == null ? 'NO ACTIVE SOURCE' : 'ACTIVE SOURCE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: account == null ? AppColors.textTertiary : AppColors.success,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          account?.server.name ?? '尚未选择放映源',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          account == null
              ? '添加服务器，或重新登录下方已经保存的放映源。'
              : '${account.server.kind.label} ${account.server.version} · '
                    '${account.userName}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
    final metrics = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SourceMetric(label: '$serverCount', detail: '服务器'),
        _SourceMetric(
          label: '${state.accounts.where((e) => e.signedIn).length}',
          detail: '已登录',
        ),
        if (account != null)
          OutlinedButton.icon(
            onPressed: onGoHome,
            icon: const Icon(Icons.home_rounded),
            label: const Text('返回首页'),
          )
        else
          OutlinedButton.icon(
            onPressed: onAddServer,
            icon: const Icon(Icons.add_link_rounded),
            label: const Text('连接服务器'),
          ),
      ],
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 180),
      clipBehavior: Clip.antiAlias,
      decoration: AppGlass.decoration(radius: 20, elevated: true),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              color: account == null
                  ? AppColors.textTertiary.withValues(alpha: 0.28)
                  : AppColors.spotlight,
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 22 : 28),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      glyph,
                      const SizedBox(height: 18),
                      information,
                      const SizedBox(height: 20),
                      metrics,
                    ],
                  )
                : Row(
                    children: [
                      glyph,
                      const SizedBox(width: 20),
                      Expanded(child: information),
                      const SizedBox(width: 24),
                      metrics,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SourceMetric extends StatelessWidget {
  const _SourceMetric({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cascadia Mono',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            detail,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ServerAccountCard extends StatelessWidget {
  const _ServerAccountCard({
    required this.account,
    required this.active,
    required this.compact,
    required this.busy,
    required this.onSwitch,
    required this.onLogin,
    required this.onLogout,
    required this.onRemove,
  });

  final ServerAccountEntry account;
  final bool active;
  final bool compact;
  final bool busy;
  final VoidCallback onSwitch;
  final VoidCallback onLogin;
  final VoidCallback onLogout;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final profile = account.profile;
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _ConnectionBadge(active: active, signedIn: account.signedIn),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '${profile.kind.label} ${profile.version} · ${profile.userName}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          profile.apiBaseUri.toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontFamily: 'Cascadia Mono',
            fontSize: 11,
          ),
        ),
      ],
    );
    final action = account.signedIn
        ? active
              ? OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('当前使用'),
                )
              : OutlinedButton.icon(
                  key: ValueKey('switch-${profile.id}'),
                  onPressed: busy ? null : onSwitch,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('切换'),
                )
        : OutlinedButton.icon(
            key: ValueKey('login-${profile.id}'),
            onPressed: busy ? null : onLogin,
            icon: const Icon(Icons.login_rounded),
            label: const Text('重新登录'),
          );
    final menu = PopupMenuButton<_AccountMenuAction>(
      tooltip: '管理 ${profile.name}',
      enabled: !busy,
      onSelected: (value) {
        switch (value) {
          case _AccountMenuAction.logout:
            onLogout();
          case _AccountMenuAction.remove:
            onRemove();
        }
      },
      itemBuilder: (context) => [
        if (account.signedIn)
          const PopupMenuItem(
            value: _AccountMenuAction.logout,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout_rounded),
              title: Text('退出账号'),
            ),
          ),
        const PopupMenuItem(
          value: _AccountMenuAction.remove,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline_rounded),
            title: Text('移除服务器资料'),
          ),
        ),
      ],
    );

    return Semantics(
      container: true,
      label:
          '${profile.name}，${profile.kind.label}，${active
              ? '当前使用'
              : account.signedIn
              ? '已登录'
              : '需要登录'}',
      child: AnimatedContainer(
        duration: AppMotion.responsive(context, AppMotion.fast),
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(18),
        decoration: AppGlass.decoration(
          radius: 16,
          tint: active ? AppColors.glassSelected : AppColors.glassSurface,
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ServerGlyph(kind: profile.kind, active: active),
                      const SizedBox(width: 14),
                      Expanded(child: information),
                      menu,
                    ],
                  ),
                  const SizedBox(height: 16),
                  action,
                ],
              )
            : Row(
                children: [
                  _ServerGlyph(kind: profile.kind, active: active),
                  const SizedBox(width: 16),
                  Expanded(child: information),
                  if (busy) ...[
                    const SizedBox(width: 18),
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                  const SizedBox(width: 16),
                  action,
                  const SizedBox(width: 4),
                  menu,
                ],
              ),
      ),
    );
  }
}

class _ServerGlyph extends StatelessWidget {
  const _ServerGlyph({required this.kind, required this.active});

  final ServerKind kind;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: active
            ? AppColors.spotlight.withValues(alpha: 0.13)
            : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        kind == ServerKind.jellyfin
            ? Icons.play_circle_outline_rounded
            : Icons.smart_display_outlined,
        color: active ? AppColors.spotlight : AppColors.textSecondary,
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.active, required this.signedIn});

  final bool active;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final label = active
        ? '正在使用'
        : signedIn
        ? '已登录'
        : '需要登录';
    final color = active
        ? AppColors.success
        : signedIn
        ? AppColors.indigo
        : AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts({required this.onAddServer});

  final VoidCallback onAddServer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: AppGlass.decoration(radius: 16),
      child: Column(
        children: [
          const Icon(
            Icons.settings_input_component_outlined,
            size: 40,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 14),
          Text('还没有保存的服务器', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            '添加 Jellyfin 或 Emby，登录后就能在这里快速切换。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onAddServer,
            icon: const Icon(Icons.add_link_rounded),
            label: const Text('添加第一个服务器'),
          ),
        ],
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.shield_outlined,
          size: 18,
          color: AppColors.textTertiary,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '密码不会保存。每个服务器账户的访问令牌分别存放在 Windows 安全存储中，'
            '切换放映源不会把凭据写入媒体缓存或日志。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}

enum _AccountMenuAction { logout, remove }
