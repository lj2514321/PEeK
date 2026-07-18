import 'dart:math' as math;

import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/home/presentation/connection_dialogs.dart';
import 'package:embyplayer/src/features/library/presentation/media_library_page.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;
  DiscoveredServer? _discoveredServer;
  AuthenticatedServer? _authenticatedServer;
  bool _clearingExpiredSession = false;

  static const _destinations = [
    _AppDestination('首页', Icons.home_outlined, Icons.home_rounded),
    _AppDestination(
      '媒体库',
      Icons.video_library_outlined,
      Icons.video_library_rounded,
    ),
    _AppDestination('搜索', Icons.search_rounded, Icons.search_rounded),
    _AppDestination('设置', Icons.tune_outlined, Icons.tune_rounded),
  ];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_restoreSession);
  }

  Future<void> _restoreSession() async {
    final account = await ref
        .read(serverAuthenticationProvider)
        .restoreSession();
    if (!mounted || account == null) return;
    setState(() {
      _discoveredServer = account.server;
      _authenticatedServer = account;
    });
  }

  Future<void> _showAddServerDialog() async {
    final result = await showDialog<DiscoveredServer>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) => const AddServerDialog(),
    );
    if (result == null || !mounted) return;

    final previousAccount = _authenticatedServer;
    if (previousAccount != null) {
      await ref.read(serverAuthenticationProvider).logout(previousAccount);
      if (!mounted) return;
    }

    setState(() {
      _discoveredServer = result;
      _authenticatedServer = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已找到 ${result.kind.label} 服务器：${result.name}')),
    );
    await _showLoginDialog(result);
  }

  Future<void> _showLoginDialog([DiscoveredServer? discovered]) async {
    final server = discovered ?? _discoveredServer;
    if (server == null) return;

    final result = await showDialog<AuthenticatedServer>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) => LoginDialog(server: server),
    );
    if (result == null || !mounted) return;

    setState(() {
      _discoveredServer = result.server;
      _authenticatedServer = result;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已安全登录：${result.userName}')));
  }

  void _selectDestination(int index) {
    setState(() => _selectedIndex = index);
  }

  Future<void> _handleSessionExpired() async {
    final account = _authenticatedServer;
    if (account == null || _clearingExpiredSession) return;
    _clearingExpiredSession = true;
    try {
      await ref.read(serverAuthenticationProvider).logout(account);
    } on Object {
      // The in-memory session still needs to be cleared if secure storage fails.
    }
    if (!mounted) return;
    setState(() {
      _authenticatedServer = null;
      _selectedIndex = 0;
      _clearingExpiredSession = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('登录已失效，请重新登录服务器。')));
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          _selectDestination(2);
        },
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showRail = constraints.maxWidth >= 720;
            final extendedRail = constraints.maxWidth >= 1040;
            final compactContent = constraints.maxWidth < 900;

            return Scaffold(
              body: AmbientBackdrop(
                child: SafeArea(
                  child: Row(
                    children: [
                      if (showRail)
                        _AppRail(
                          extended: extendedRail,
                          destinations: _destinations,
                          selectedIndex: _selectedIndex,
                          onSelected: _selectDestination,
                        ),
                      Expanded(
                        child: Column(
                          children: [
                            _TopCommandBar(
                              compact: compactContent,
                              destination: _destinations[_selectedIndex],
                              server: _discoveredServer,
                              account: _authenticatedServer,
                              onSearch: () => _selectDestination(2),
                            ),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: AppMotion.responsive(
                                  context,
                                  AppMotion.standard,
                                ),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: switch (_selectedIndex) {
                                  0 => _HomePage(
                                    key: const ValueKey('home'),
                                    server: _discoveredServer,
                                    account: _authenticatedServer,
                                    onAddServer: _showAddServerDialog,
                                    onLogin: _showLoginDialog,
                                    onOpenLibrary: () {
                                      _selectDestination(1);
                                    },
                                  ),
                                  1 => MediaLibraryPage(
                                    key: const ValueKey('library'),
                                    account: _authenticatedServer,
                                    onGoHome: () => _selectDestination(0),
                                    onSessionExpired: _handleSessionExpired,
                                  ),
                                  _ => _UnavailablePage(
                                    key: ValueKey(_selectedIndex),
                                    destination: _destinations[_selectedIndex],
                                    account: _authenticatedServer,
                                    onGoHome: () => _selectDestination(0),
                                  ),
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              bottomNavigationBar: showRail
                  ? null
                  : GlassSurface(
                      radius: 0,
                      blur: 24,
                      tint: AppColors.glassStrong,
                      child: NavigationBar(
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: _selectDestination,
                        destinations: [
                          for (final destination in _destinations)
                            NavigationDestination(
                              icon: Icon(destination.icon),
                              selectedIcon: Icon(destination.selectedIcon),
                              label: destination.label,
                            ),
                        ],
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _AppRail extends StatelessWidget {
  const _AppRail({
    required this.extended,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final bool extended;
  final List<_AppDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 0,
      blur: 24,
      tint: AppColors.glassSurface,
      child: SizedBox(
        width: extended ? 224 : 80,
        child: NavigationRail(
          extended: extended,
          minWidth: 80,
          minExtendedWidth: 224,
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          labelType: extended
              ? NavigationRailLabelType.none
              : NavigationRailLabelType.all,
          groupAlignment: -0.72,
          leading: _RailBrand(extended: extended),
          destinations: [
            for (final destination in destinations)
              NavigationRailDestination(
                padding: const EdgeInsets.symmetric(vertical: 4),
                icon: Icon(destination.icon),
                selectedIcon: _SelectedRailIcon(icon: destination.selectedIcon),
                label: Text(destination.label),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(extended ? 18 : 16, 18, 16, 32),
      child: SizedBox(
        width: extended ? 190 : 48,
        height: 56,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _BrandMark(),
            if (extended) ...[
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PEeK',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'PRIVATE CINEMA',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontFamily: 'Cascadia Mono',
                        fontSize: 9,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'PEeK',
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.spotlight,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.spotlight.withValues(alpha: 0.12),
              blurRadius: 20,
            ),
          ],
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: AppColors.onSpotlight,
          size: 28,
        ),
      ),
    );
  }
}

class _SelectedRailIcon extends StatelessWidget {
  const _SelectedRailIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Icon(icon),
        Positioned(
          left: -18,
          child: Container(
            width: 3,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.spotlight,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ],
    );
  }
}

class _TopCommandBar extends StatelessWidget {
  const _TopCommandBar({
    required this.compact,
    required this.destination,
    required this.server,
    required this.account,
    required this.onSearch,
  });

  final bool compact;
  final _AppDestination destination;
  final DiscoveredServer? server;
  final AuthenticatedServer? account;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 0,
      blur: 22,
      tint: AppColors.glassSurface,
      child: SizedBox(
        height: 76,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 32),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  destination.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (!compact) ...[
                _SearchCommand(onTap: onSearch),
                const SizedBox(width: 16),
              ] else ...[
                IconButton(
                  tooltip: '搜索媒体库（Ctrl+K）',
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded),
                ),
                const SizedBox(width: 4),
              ],
              _AccountStatus(
                server: server,
                account: account,
                compact: compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchCommand extends StatelessWidget {
  const _SearchCommand({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '搜索媒体库，快捷键 Control K',
      child: Material(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 300,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
            child: const Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '搜索电影、剧集与人物',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ),
                _ShortcutBadge(label: 'Ctrl K'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutBadge extends StatelessWidget {
  const _ShortcutBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontFamily: 'Cascadia Mono',
          fontSize: 10,
        ),
      ),
    );
  }
}

class _AccountStatus extends StatelessWidget {
  const _AccountStatus({
    required this.server,
    required this.account,
    required this.compact,
  });

  final DiscoveredServer? server;
  final AuthenticatedServer? account;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final connected = account != null;
    final found = server != null;
    final label = connected
        ? account!.userName
        : found
        ? '${server!.kind.label} 已发现'
        : '未连接';

    return Semantics(
      label: '连接状态：$label',
      child: Container(
        height: 44,
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: connected
                    ? AppColors.success.withValues(alpha: 0.15)
                    : AppColors.surfaceHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                connected ? Icons.person_rounded : Icons.dns_outlined,
                size: 15,
                color: connected ? AppColors.success : AppColors.textTertiary,
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 9),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    super.key,
    required this.server,
    required this.account,
    required this.onAddServer,
    required this.onLogin,
    required this.onOpenLibrary,
  });

  final DiscoveredServer? server;
  final AuthenticatedServer? account;
  final VoidCallback onAddServer;
  final VoidCallback onLogin;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 720 ? 20.0 : 32.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            32,
            horizontalPadding,
            48,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroStage(
                    server: server,
                    account: account,
                    onAddServer: onAddServer,
                    onLogin: onLogin,
                    onOpenLibrary: onOpenLibrary,
                  ),
                  const SizedBox(height: 24),
                  _StatusGrid(server: server, account: account),
                  const SizedBox(height: 28),
                  const _CapabilityStrip(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroStage extends StatelessWidget {
  const _HeroStage({
    required this.server,
    required this.account,
    required this.onAddServer,
    required this.onLogin,
    required this.onOpenLibrary,
  });

  final DiscoveredServer? server;
  final AuthenticatedServer? account;
  final VoidCallback onAddServer;
  final VoidCallback onLogin;
  final VoidCallback onOpenLibrary;

  int get progress => account != null ? 3 : (server != null ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 430),
      decoration: AppGlass.decoration(radius: 24, elevated: true),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _StageBackdropPainter())),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 900;
              final copy = _HeroCopy(
                server: server,
                account: account,
                onAddServer: onAddServer,
                onLogin: onLogin,
                onOpenLibrary: onOpenLibrary,
              );
              final route = _PlaybackRouteVisual(
                progress: progress,
                server: server,
              );

              if (stacked) {
                return Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      copy,
                      const SizedBox(height: 28),
                      SizedBox(height: 330, child: route),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.all(48),
                child: Row(
                  children: [
                    Expanded(flex: 58, child: copy),
                    const SizedBox(width: 44),
                    Expanded(flex: 42, child: route),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.server,
    required this.account,
    required this.onAddServer,
    required this.onLogin,
    required this.onOpenLibrary,
  });

  final DiscoveredServer? server;
  final AuthenticatedServer? account;
  final VoidCallback onAddServer;
  final VoidCallback onLogin;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final found = server != null;
    final authenticated = account != null;

    final eyebrow = authenticated
        ? '${server!.kind.label.toUpperCase()}  ·  SIGNED IN'
        : found
        ? '${server!.kind.label.toUpperCase()}  ·  SERVER FOUND'
        : 'PRIVATE CINEMA  ·  LOCAL FIRST';
    final title = authenticated
        ? '${account!.userName}，\n片单正在等你。'
        : found
        ? '片库已就位，\n只差一次登录。'
        : '让你的片库，\n拥有开场时刻。';
    final description = authenticated
        ? '已安全连接 ${server!.name}。下一步进入媒体库，继续上次未看完的故事。'
        : found
        ? '已识别 ${server!.kind.label} ${server!.version}。登录后即可读取媒体库与播放进度。'
        : '连接 Jellyfin 或 Emby，把分散的影片、字幕、音轨与观看进度，收进一个安静而专注的桌面空间。';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 18,
              height: 2,
              color: authenticated ? AppColors.success : AppColors.spotlight,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: authenticated
                      ? AppColors.success
                      : AppColors.spotlight,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.displayLarge),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Text(
            description,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: 30),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: authenticated
                  ? onOpenLibrary
                  : found
                  ? onLogin
                  : onAddServer,
              icon: Icon(
                authenticated
                    ? Icons.video_library_rounded
                    : found
                    ? Icons.login_rounded
                    : Icons.add_link_rounded,
              ),
              label: Text(
                authenticated
                    ? '打开媒体库'
                    : found
                    ? '登录到服务器'
                    : '添加媒体服务器',
              ),
            ),
            if (found && !authenticated)
              OutlinedButton.icon(
                onPressed: onAddServer,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('更换服务器'),
              ),
          ],
        ),
        const SizedBox(height: 26),
        const Wrap(
          spacing: 18,
          runSpacing: 10,
          children: [
            _QuietFeature(icon: Icons.hd_rounded, label: '原码优先'),
            _QuietFeature(icon: Icons.subtitles_outlined, label: '多音轨字幕'),
            _QuietFeature(icon: Icons.sync_rounded, label: '进度同步'),
          ],
        ),
      ],
    );
  }
}

class _QuietFeature extends StatelessWidget {
  const _QuietFeature({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: AppColors.textTertiary),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
      ],
    );
  }
}

class _PlaybackRouteVisual extends StatelessWidget {
  const _PlaybackRouteVisual({required this.progress, required this.server});

  final int progress;
  final DiscoveredServer? server;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.responsive(context, AppMotion.standard);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: AppGlass.decoration(
        radius: 20,
        tint: AppColors.glassSurface.withValues(alpha: 0.82),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PLAYBACK ROUTE',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      progress == 3 ? '播放链路已建立' : '建立你的播放链路',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              _ProgressCounter(value: '$progress / 3'),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              _RouteNode(
                icon: Icons.dns_rounded,
                code: 'SERVER',
                label: server?.kind.label ?? '媒体服务',
                active: progress >= 1,
                completed: progress > 1,
              ),
              _RouteConnector(active: progress >= 2, duration: duration),
              _RouteNode(
                icon: Icons.shield_rounded,
                code: 'AUTH',
                label: '安全登录',
                active: progress >= 2,
                completed: progress > 2,
              ),
              _RouteConnector(active: progress >= 3, duration: duration),
              _RouteNode(
                icon: Icons.play_circle_rounded,
                code: 'PLAY',
                label: 'libmpv',
                active: progress >= 3,
                completed: false,
              ),
            ],
          ),
          const SizedBox(height: 28),
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  progress == 3
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded,
                  size: 18,
                  color: progress == 3
                      ? AppColors.success
                      : AppColors.textTertiary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    progress == 3
                        ? '凭据已加密保存，播放器可以请求媒体源。'
                        : progress == 1
                        ? '服务器已发现，登录后完成播放链路。'
                        : '从发现服务器开始，约需一分钟。',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
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

class _ProgressCounter extends StatelessWidget {
  const _ProgressCounter({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        value,
        style: const TextStyle(
          fontFamily: 'Cascadia Mono',
          fontSize: 11,
          color: AppColors.spotlight,
        ),
      ),
    );
  }
}

class _RouteNode extends StatelessWidget {
  const _RouteNode({
    required this.icon,
    required this.code,
    required this.label,
    required this.active,
    required this.completed,
  });

  final IconData icon;
  final String code;
  final String label;
  final bool active;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? AppColors.success
        : active
        ? AppColors.spotlight
        : AppColors.textTertiary;
    return Semantics(
      label: '$label：${active ? '已就绪' : '等待'}',
      child: SizedBox(
        width: 70,
        child: Column(
          children: [
            AnimatedContainer(
              duration: AppMotion.responsive(context, AppMotion.standard),
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: active
                    ? color.withValues(alpha: 0.12)
                    : AppColors.surfaceHigh,
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.2),
                          blurRadius: 20,
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon, color: color, size: 23),
            ),
            const SizedBox(height: 10),
            Text(
              code,
              style: TextStyle(
                color: color,
                fontFamily: 'Cascadia Mono',
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteConnector extends StatelessWidget {
  const _RouteConnector({required this.active, required this.duration});

  final bool active;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: duration,
        height: 2,
        margin: const EdgeInsets.only(bottom: 38),
        color: active ? AppColors.spotlight : AppColors.outline,
      ),
    );
  }
}

class _StageBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final indigoGlow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              AppColors.indigo.withValues(alpha: 0.17),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.86, size.height * 0.18),
              radius: math.max(size.width, size.height) * 0.52,
            ),
          );
    canvas.drawRect(Offset.zero & size, indigoGlow);

    final beam = Path()
      ..moveTo(size.width * 0.7, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.63, size.height)
      ..lineTo(size.width * 0.38, size.height)
      ..close();
    canvas.drawPath(
      beam,
      Paint()..color = AppColors.spotlight.withValues(alpha: 0.022),
    );

    final linePaint = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.025)
      ..strokeWidth = 1;
    for (var x = 48.0; x < size.width; x += 72) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StatusGrid extends StatelessWidget {
  const _StatusGrid({required this.server, required this.account});

  final DiscoveredServer? server;
  final AuthenticatedServer? account;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatusData(
        number: '01',
        icon: Icons.dns_rounded,
        title: '媒体服务器',
        value: server?.name ?? '等待添加',
        detail: server == null
            ? '自动识别 Jellyfin 与 Emby'
            : '${server!.kind.label} ${server!.version}',
        active: server != null,
      ),
      _StatusData(
        number: '02',
        icon: Icons.shield_rounded,
        title: '安全凭据',
        value: account?.userName ?? '等待登录',
        detail: account == null ? '密码不会保存在本地' : '安全存储 · 自动登录',
        active: account != null,
      ),
      const _StatusData(
        number: '03',
        icon: Icons.movie_filter_rounded,
        title: '播放内核',
        value: 'media_kit / libmpv',
        detail: '硬件解码与多轨字幕已配置',
        active: true,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 820) {
          return Column(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                _StatusCard(data: cards[index]),
                if (index != cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              Expanded(child: _StatusCard(data: cards[index])),
              if (index != cards.length - 1) const SizedBox(width: 14),
            ],
          ],
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.data});

  final _StatusData data;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${data.title}：${data.value}，${data.detail}',
      child: Container(
        height: 132,
        padding: const EdgeInsets.all(20),
        decoration: AppGlass.decoration(radius: 16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: data.active
                    ? AppColors.spotlight.withValues(alpha: 0.1)
                    : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                data.icon,
                color: data.active
                    ? AppColors.spotlight
                    : AppColors.textTertiary,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Text(
                        data.number,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: data.active
                              ? AppColors.success
                              : AppColors.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        data.active ? '就绪' : '等待',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.detail,
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
      ),
    );
  }
}

class _CapabilityStrip extends StatelessWidget {
  const _CapabilityStrip();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: const [
        _CapabilityChip(icon: Icons.memory_rounded, label: '硬件解码'),
        _CapabilityChip(
          icon: Icons.high_quality_rounded,
          label: '4K / HEVC / AV1',
        ),
        _CapabilityChip(
          icon: Icons.closed_caption_rounded,
          label: 'SRT / ASS / PGS',
        ),
        _CapabilityChip(icon: Icons.security_rounded, label: '本地安全凭据'),
      ],
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: AppColors.surfaceLow.withValues(alpha: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _UnavailablePage extends StatelessWidget {
  const _UnavailablePage({
    super.key,
    required this.destination,
    required this.account,
    required this.onGoHome,
  });

  final _AppDestination destination;
  final AuthenticatedServer? account;
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    final connected = account != null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: AppColors.surfaceLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  destination.selectedIcon,
                  color: AppColors.spotlight,
                  size: 29,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                connected ? '${destination.label}正在接入' : '先连接你的媒体服务器',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                connected
                    ? '服务器已经就绪。下一阶段会在这里读取真实媒体内容。'
                    : '完成服务器检测和登录后，${destination.label}会在这里显示。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onGoHome,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('返回首页'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusData {
  const _StatusData({
    required this.number,
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.active,
  });

  final String number;
  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final bool active;
}

class _AppDestination {
  const _AppDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
