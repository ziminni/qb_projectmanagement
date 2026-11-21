import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_motion.dart';
import '../../../shared/widgets/qb_logo.dart';
import '../../auth/widgets/login_dialog.dart';

/// Pre-login landing page for the Queen Builders Construction Project
/// Management System. "Login" anywhere on the page opens the sign-in modal.
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

/// The sections the nav bar and footer can jump to.
enum LandingSection {
  home('Overview'),
  capabilities('Capabilities'),
  roles('Roles'),
  faq('FAQs');

  const LandingSection(this.label);
  final String label;
}

const _navHeight = 72.0;

class _LandingPageState extends State<LandingPage> {
  final _scroll = ScrollController();
  final _keys = {for (final s in LandingSection.values) s: GlobalKey()};
  bool _scrolled = false;
  bool _menuOpen = false;
  LandingSection _active = LandingSection.home;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final scrolled = _scroll.offset > 12;
    var active = LandingSection.home;
    for (final s in LandingSection.values) {
      final box = _keys[s]!.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= _navHeight + 140) active = s;
    }
    if (scrolled != _scrolled || active != _active) {
      setState(() {
        _scrolled = scrolled;
        _active = active;
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goTo(LandingSection section) {
    if (_menuOpen) setState(() => _menuOpen = false);
    final box =
        _keys[section]!.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_scroll.hasClients) return;
    final target = section == LandingSection.home
        ? 0.0
        : (_scroll.offset + box.localToGlobal(Offset.zero).dy - _navHeight)
              .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
    );
  }

  void _login() {
    if (_menuOpen) setState(() => _menuOpen = false);
    showLoginDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    Widget keyed(LandingSection s, Widget child) =>
        KeyedSubtree(key: _keys[s], child: child);

    return Scaffold(
      backgroundColor: AppColors.chrome,
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                keyed(
                  LandingSection.home,
                  HeroSection(
                    onLogin: _login,
                    onExplore: () => _goTo(LandingSection.capabilities),
                  ),
                ),
                keyed(LandingSection.capabilities, const _CapabilitiesSection()),
                keyed(LandingSection.roles, const _RolesSection()),
                keyed(LandingSection.faq, const _FaqSection()),
                _FooterSection(onLogin: _login, onNavigate: _goTo),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: NavBar(
              elevated: _scrolled || _menuOpen,
              active: _active,
              isWide: wide,
              menuOpen: _menuOpen,
              onLogin: _login,
              onNavigate: _goTo,
              onMenuToggle: () => setState(() => _menuOpen = !_menuOpen),
            ),
          ),
          if (!wide)
            Positioned(
              top: _navHeight,
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_menuOpen,
                child: AnimatedSwitcher(
                  duration: AppMotion.medium,
                  switchInCurve: AppMotion.switchIn,
                  switchOutCurve: AppMotion.switchOut,
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, -0.02),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _menuOpen
                      ? _MobileMenu(
                          key: const ValueKey('menu'),
                          onLogin: _login,
                          onNavigate: _goTo,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout & Typography Primitives
// ---------------------------------------------------------------------------

bool _isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;

double _gutter(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  const maxWidth = 1140.0;
  return width > maxWidth + 2 * AppSpacing.xl
      ? (width - maxWidth) / 2
      : (width >= 600 ? AppSpacing.xl : AppSpacing.lg);
}

const _body = AppFonts.body;
const _display = AppFonts.display;

class _Band extends StatelessWidget {
  const _Band({
    required this.color,
    required this.child,
    this.top,
    this.bottom,
  });

  final Color color;
  final Widget child;
  final double? top, bottom;

  @override
  Widget build(BuildContext context) {
    final v = _isWide(context) ? 104.0 : 68.0;
    final side = _gutter(context);
    return ColoredBox(
      color: color,
      child: Padding(
        padding: EdgeInsets.fromLTRB(side, top ?? v, side, bottom ?? v),
        child: child,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    this.onDark = false,
  });

  final String title;
  final String subtitle;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: _display,
              fontSize: wide ? 36 : 26,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: onDark ? const Color(0xFFF6F4EE) : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: _body,
              fontSize: 15.5,
              height: 1.65,
              color: onDark ? const Color(0xFFB5AFA3) : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrassButton extends StatelessWidget {
  const _BrassButton({
    required this.label,
    required this.onPressed,
    this.large = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brandGold,
        foregroundColor: AppColors.brandBlack,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
        padding: EdgeInsets.symmetric(
          horizontal: large ? 26 : 20,
          vertical: large ? 17 : 12,
        ),
        textStyle: TextStyle(
          fontFamily: _body,
          fontSize: large ? 15 : 13.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      child: Text(label),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation Bar
// ---------------------------------------------------------------------------

class NavBar extends StatelessWidget {
  const NavBar({
    super.key,
    required this.elevated,
    required this.active,
    required this.isWide,
    required this.menuOpen,
    required this.onLogin,
    required this.onNavigate,
    required this.onMenuToggle,
  });

  final bool elevated;
  final LandingSection active;
  final bool isWide, menuOpen;
  final VoidCallback onLogin, onMenuToggle;
  final ValueChanged<LandingSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final side = _gutter(context);
    final onDarkHeader = !elevated && !menuOpen;

    final logo = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onNavigate(LandingSection.home),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: QbLogo(
            size: isWide ? 38 : 34,
            onDark: onDarkHeader,
            tagline: 'Construction PMS',
          ),
        ),
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: _navHeight,
      padding: EdgeInsets.symmetric(horizontal: side),
      decoration: BoxDecoration(
        color: onDarkHeader
            ? const Color(0xCC090908)
            : AppColors.surface.withValues(alpha: 0.97),
        border: Border(
          bottom: BorderSide(
            color: onDarkHeader
                ? Colors.white.withValues(alpha: 0.08)
                : AppColors.border,
          ),
        ),
        boxShadow: elevated && !menuOpen
            ? const [
                BoxShadow(
                  color: Color(0x12050505),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          if (isWide)
            logo
          else
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: logo),
            ),
          if (isWide) ...[
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in LandingSection.values)
                  _NavLink(
                    label: s.label,
                    selected: s == active,
                    onDark: onDarkHeader,
                    onTap: () => onNavigate(s),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.xl),
          ] else ...[
            IconButton(
              tooltip: menuOpen ? 'Close menu' : 'Menu',
              onPressed: onMenuToggle,
              icon: Icon(
                menuOpen ? Icons.close_rounded : Icons.menu_rounded,
                color: onDarkHeader ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          _BrassButton(label: 'Login', onPressed: onLogin),
        ],
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({
    required this.label,
    required this.onTap,
    required this.selected,
    required this.onDark,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? (onDark ? AppColors.brandGoldLight : AppColors.brandBlack)
        : (onDark ? const Color(0xFFBDB6A6) : AppColors.textSecondary);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: fg,
          backgroundColor: Colors.transparent,
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.smAll),
          textStyle: TextStyle(
            fontFamily: _body,
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _MobileMenu extends StatelessWidget {
  const _MobileMenu({
    super.key,
    required this.onLogin,
    required this.onNavigate,
  });

  final VoidCallback onLogin;
  final ValueChanged<LandingSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          for (final s in LandingSection.values) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              title: Text(
                s.label,
                style: const TextStyle(
                  fontFamily: _body,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              onTap: () => onNavigate(s),
            ),
            const Divider(color: AppColors.border, height: 1),
          ],
          const SizedBox(height: AppSpacing.xl),
          _BrassButton(
            label: 'Login to Your Account',
            onPressed: onLogin,
            large: true,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Full-Viewport Editorial Hero
// ---------------------------------------------------------------------------

class HeroSection extends StatelessWidget {
  const HeroSection({
    super.key,
    required this.onLogin,
    required this.onExplore,
  });

  final VoidCallback onLogin, onExplore;

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    final side = _gutter(context);
    final screenHeight = MediaQuery.sizeOf(context).height;

    final mainCopy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          const TextSpan(
            children: [
              TextSpan(text: 'Building Better.\n'),
              TextSpan(
                text: 'Managing Smarter.',
                style: TextStyle(color: AppColors.brandGoldLight),
              ),
            ],
          ),
          style: TextStyle(
            fontFamily: _display,
            fontSize: wide ? 54 : 34,
            height: 1.08,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: const Color(0xFFF8F6F0),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Text(
            'A quiet, centralized workspace for Queen Builders — keeping project schedules, site reports, materials, and budgets aligned from ground-breaking to handover.',
            style: TextStyle(
              fontFamily: _body,
              fontSize: wide ? 17 : 15.5,
              height: 1.65,
              color: const Color(0xFFC8C2B6),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _BrassButton(
              label: 'Login to Your Account',
              onPressed: onLogin,
              large: true,
            ),
            TextButton.icon(
              onPressed: onExplore,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEAE5DA),
                backgroundColor: Colors.transparent,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                textStyle: const TextStyle(
                  fontFamily: _body,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.arrow_downward_rounded, size: 17),
              label: const Text('Explore capabilities'),
            ),
          ],
        ),
      ],
    );

    final assuranceStrip = Container(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: const Wrap(
        spacing: AppSpacing.xxl,
        runSpacing: AppSpacing.md,
        children: [
          _HeroAssurance(Icons.verified_user_outlined, 'Role-based access'),
          _HeroAssurance(Icons.hub_outlined, 'Single source of truth'),
          _HeroAssurance(
            Icons.lock_outline_rounded,
            'Authorized Queen Builders personnel',
          ),
        ],
      ),
    );

    return Container(
      constraints: BoxConstraints(minHeight: screenHeight),
      color: const Color(0xFF090908),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _HeroBlueprintPainter()),
              ),
            ),
          ),
          Container(
            constraints: BoxConstraints(minHeight: screenHeight),
            padding: EdgeInsets.fromLTRB(
              side,
              _navHeight + (wide ? 64 : 40),
              side,
              wide ? 44 : 32,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.md),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 7, child: mainCopy),
                      const SizedBox(width: 64),
                      const Expanded(flex: 4, child: _EditorialLedger()),
                    ],
                  )
                else
                  mainCopy,
                const SizedBox(height: AppSpacing.xxl),
                assuranceStrip,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Offline architectural blueprint grid and warm brass radial glow for the
/// landing hero, echoing the Queen Builders drafting canvas without any network
/// image dependency.
class _HeroBlueprintPainter extends CustomPainter {
  const _HeroBlueprintPainter();

  static const double _minorStep = 36;
  static const double _majorStep = _minorStep * 4;

  @override
  void paint(Canvas canvas, Size size) {
    // Soft warm brass ambient glow behind the headline and ledger.
    final primaryGlow = Rect.fromCircle(
      center: Offset(size.width * 0.22, size.height * 0.34),
      radius: size.width * 0.55,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.brandGold.withValues(alpha: 0.14),
            AppColors.brandGold.withValues(alpha: 0.03),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(primaryGlow),
    );

    final secondaryGlow = Rect.fromCircle(
      center: Offset(size.width * 0.84, size.height * 0.62),
      radius: size.width * 0.42,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.brandGoldLight.withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ).createShader(secondaryGlow),
    );

    // Subtle drafting grid lines.
    final minor = Paint()
      ..color = AppColors.brandGold.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = AppColors.brandGold.withValues(alpha: 0.095)
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += _minorStep) {
      final paint = (x % _majorStep == 0) ? major : minor;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += _minorStep) {
      final paint = (y % _majorStep == 0) ? major : minor;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HeroBlueprintPainter oldDelegate) => false;
}

class _HeroAssurance extends StatelessWidget {
  const _HeroAssurance(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.brandGoldLight),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: _body,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFFBDB6A6),
            ),
          ),
        ),
      ],
    );
  }
}

/// Restrained typographic index of the platform's workspaces — no nested cards
/// or fake charts, just calm architectural lines.
class _EditorialLedger extends StatelessWidget {
  const _EditorialLedger();

  static const _workspaces = [
    ('Project Management', 'Schedules, budgets & approvals'),
    ('Site Operations', 'Daily reports, tasks & deliveries'),
    ('Accounting', 'Payroll, billings & payables'),
    ('Client Portal', 'Verified progress & statements'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: const Color(0xCC131210),
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: const Color(0xFF2B2823)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'PLATFORM WORKSPACES',
            style: TextStyle(
              fontFamily: _body,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.brandGoldLight,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < _workspaces.length; i++) ...[
            if (i > 0)
              const Divider(color: Color(0xFF25231E), height: AppSpacing.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _workspaces[i].$1,
                        style: const TextStyle(
                          fontFamily: _display,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF6F4EE),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _workspaces[i].$2,
                        style: const TextStyle(
                          fontFamily: _body,
                          fontSize: 13,
                          color: Color(0xFFA9A295),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.north_east_rounded,
                  size: 15,
                  color: AppColors.brandGold,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Capabilities (Hairline Editorial Index — No Card Soup)
// ---------------------------------------------------------------------------

class _CapabilitiesSection extends StatelessWidget {
  const _CapabilitiesSection();

  static const _items = [
    (
      Icons.apartment_outlined,
      'Project & Schedule Control',
      'Plan milestones, monitor actual progress against approved schedules, and keep every project phase on track.',
    ),
    (
      Icons.edit_note_outlined,
      'Daily Site Reporting',
      'Foremen submit structured daily progress logs, crew attendance, and site photos directly from the field.',
    ),
    (
      Icons.inventory_2_outlined,
      'Materials & Procurement',
      'Track material requests, purchase orders, deliveries, and on-site inventory in one connected chain.',
    ),
    (
      Icons.payments_outlined,
      'Budgets, Billings & Payroll',
      'Review contract amounts, variation orders, progress billings, retention, and crew payroll with clear audit trails.',
    ),
    (
      Icons.groups_2_outlined,
      'Team & Role Coordination',
      'Assign managers, foremen, and crews cleanly so every stakeholder sees only the work they own.',
    ),
    (
      Icons.description_outlined,
      'Verified Documentation',
      'Export formal order slips, daily reports, and billing statements from live, approved project records.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    return _Band(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            title: 'Everything a construction team needs.',
            subtitle:
                'One calm operational system replacing scattered spreadsheets, paper logs, and disconnected updates.',
          ),
          const SizedBox(height: 56),
          const Divider(color: AppColors.border, height: 1),
          if (wide)
            Column(
              children: [
                for (var i = 0; i < _items.length; i += 2) ...[
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.xl,
                              bottom: AppSpacing.xl,
                              right: AppSpacing.xxl,
                            ),
                            child: _CapabilityRow(_items[i]),
                          ),
                        ),
                        const VerticalDivider(
                          color: AppColors.border,
                          width: 1,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.xl,
                              bottom: AppSpacing.xl,
                              left: AppSpacing.xxl,
                            ),
                            child: i + 1 < _items.length
                                ? _CapabilityRow(_items[i + 1])
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                ],
              ],
            )
          else
            Column(
              children: [
                for (final item in _items) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xl,
                    ),
                    child: _CapabilityRow(item),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow(this.item);

  final (IconData, String, String) item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(item.$1, size: 22, color: AppColors.brandGoldText),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.$2,
                style: const TextStyle(
                  fontFamily: _body,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.$3,
                style: const TextStyle(
                  fontFamily: _body,
                  fontSize: 14,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Roles & Workflow (Calm Dark Band)
// ---------------------------------------------------------------------------

class _RolesSection extends StatelessWidget {
  const _RolesSection();

  static const _steps = [
    ('Sign in', 'Access your assigned workspace with your company account.'),
    ('Plan & assign', 'Set schedules, budgets, and daily site priorities.'),
    ('Report on site', 'Submit progress logs, attendance, and material needs.'),
    ('Review & approve', 'Verify reports, process payroll, and update clients.'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    const pm = _RoleColumn(
      title: 'Project Manager',
      summary:
          'Directs overall delivery — coordinating schedules, approvals, procurement, and project budgets from start to close-out.',
      points: [
        'Oversee schedules, budgets, and resource allocation',
        'Review daily reports, material requests, and approvals',
        'Track progress against planned milestones',
      ],
    );
    const foreman = _RoleColumn(
      title: 'Site Foreman',
      summary:
          'Leads daily field execution — supervising crews, logging real progress, and keeping materials moving on site.',
      points: [
        'Manage daily to-do checklists and crew attendance',
        'Submit site progress reports and photo documentation',
        'Request materials and confirm site deliveries',
      ],
    );

    return _Band(
      color: const Color(0xFF0C0B0A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            title: 'Built around the people who build.',
            subtitle:
                'Clear responsibilities from the project office to the construction site, with dedicated workspaces for Accountants, Clients, and System Administrators.',
            onDark: true,
          ),
          const SizedBox(height: 52),
          if (wide)
            const IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: pm),
                  SizedBox(width: AppSpacing.xl),
                  Expanded(child: foreman),
                ],
              ),
            )
          else
            const Column(
              children: [
                pm,
                SizedBox(height: AppSpacing.lg),
                foreman,
              ],
            ),
          const SizedBox(height: 64),
          const Divider(color: Color(0xFF262420), height: 1),
          const SizedBox(height: AppSpacing.xxl),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xl),
                  Expanded(child: _WorkflowStep(_steps[i].$1, _steps[i].$2)),
                ],
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.lg),
                  _WorkflowStep(_steps[i].$1, _steps[i].$2),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _RoleColumn extends StatelessWidget {
  const _RoleColumn({
    required this.title,
    required this.summary,
    required this.points,
  });

  final String title;
  final String summary;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: const Color(0xFF141311),
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: const Color(0xFF282621)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: _display,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF6F4EE),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            summary,
            style: const TextStyle(
              fontFamily: _body,
              fontSize: 14.5,
              height: 1.6,
              color: Color(0xFFB5AFA3),
            ),
          ),
          const Divider(color: Color(0xFF262420), height: AppSpacing.xxl),
          for (final point in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: AppColors.brandGoldLight,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      point,
                      style: const TextStyle(
                        fontFamily: _body,
                        fontSize: 13.5,
                        height: 1.45,
                        color: Color(0xFFE6E1D6),
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

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep(this.title, this.detail);

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: _body,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.brandGoldLight,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          style: const TextStyle(
            fontFamily: _body,
            fontSize: 13.5,
            height: 1.55,
            color: Color(0xFFB5AFA3),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. FAQs (Clean Hairline Accordions)
// ---------------------------------------------------------------------------

class _FaqSection extends StatelessWidget {
  const _FaqSection();

  static const _faqs = [
    (
      'Who can access the system?',
      'Access is limited to authorized Queen Builders personnel and invited clients with an active account issued by the system administrator.',
    ),
    (
      'How do I sign in to my workspace?',
      'Click Login at the top of the page and enter your company email and password. If your account holds multiple roles, you can select your active workspace right after signing in.',
    ),
    (
      'What is included in the platform?',
      'Project and schedule tracking, daily site reports, crew attendance and payroll, material requests and site inventory, progress billings, variation orders, and a read-only client portal.',
    ),
    (
      'Need an account or password reset?',
      'Use Forgot password inside the Login dialog, or contact your Queen Builders system administrator for account provisioning.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    const intro = _SectionTitle(
      title: 'Common questions.',
      subtitle:
          'Straight answers on accessing and working inside the Queen Builders platform.',
    );

    final list = Column(
      children: [
        const Divider(color: AppColors.border, height: 1),
        for (final faq in _faqs) ...[
          _FaqRow(question: faq.$1, answer: faq.$2),
          const Divider(color: AppColors.border, height: 1),
        ],
      ],
    );

    return _Band(
      color: AppColors.surface,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(flex: 4, child: intro),
                const SizedBox(width: 64),
                Expanded(flex: 6, child: list),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                intro,
                const SizedBox(height: AppSpacing.xxl),
                list,
              ],
            ),
    );
  }
}

class _FaqRow extends StatelessWidget {
  const _FaqRow({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.lg),
        iconColor: AppColors.brandGoldText,
        collapsedIconColor: AppColors.textSecondary,
        title: Text(
          question,
          style: const TextStyle(
            fontFamily: _body,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: const TextStyle(
                fontFamily: _body,
                fontSize: 14,
                height: 1.65,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Minimal Closing Footer
// ---------------------------------------------------------------------------

class _FooterSection extends StatelessWidget {
  const _FooterSection({required this.onLogin, required this.onNavigate});

  final VoidCallback onLogin;
  final ValueChanged<LandingSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    const muted = TextStyle(
      fontFamily: _body,
      fontSize: 13.5,
      height: 1.6,
      color: Color(0xFFB5AFA3),
    );

    final brand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QbLogo(size: 38, onDark: true),
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: const Text(
            'Centralized construction project management for authorized Queen Builders personnel.',
            style: muted,
          ),
        ),
      ],
    );

    final actions = Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          children: [
            for (final s in LandingSection.values)
              InkWell(
                onTap: () => onNavigate(s),
                borderRadius: AppRadii.smAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    s.label,
                    style: const TextStyle(
                      fontFamily: _body,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFDAD4C8),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _BrassButton(label: 'Login to Your Account', onPressed: onLogin),
      ],
    );

    return _Band(
      color: AppColors.chrome,
      top: 64,
      bottom: 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [brand, actions],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                brand,
                const SizedBox(height: AppSpacing.xl),
                actions,
              ],
            ),
          const SizedBox(height: 44),
          const Divider(color: Color(0xFF24221E), height: 1),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '© ${DateTime.now().year} Queen Builders Construction Project Management System.',
            style: muted.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
