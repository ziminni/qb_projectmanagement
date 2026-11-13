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
  home('Home'),
  about('About'),
  features('Features'),
  personnel('Key Personnel'),
  howItWorks('How It Works'),
  faq('FAQs');

  const LandingSection(this.label);
  final String label;
}

const _navHeight = 80.0;

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
    final scrolled = _scroll.offset > 8;
    var active = LandingSection.home;
    for (final s in LandingSection.values) {
      final box = _keys[s]!.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= _navHeight + 120) active = s;
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
    // Land the section just below the fixed header.
    final target = section == LandingSection.home
        ? 0.0
        : (_scroll.offset + box.localToGlobal(Offset.zero).dy - _navHeight)
              .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOutCubic,
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
                    onExplore: () => _goTo(LandingSection.features),
                  ),
                ),
                keyed(LandingSection.about, const AboutSection()),
                keyed(LandingSection.features, const FeaturesSection()),
                keyed(LandingSection.personnel, const KeyPersonnelSection()),
                keyed(LandingSection.howItWorks, const HowItWorksSection()),
                const BenefitsSection(),
                keyed(LandingSection.faq, const FAQSection()),
                _CtaBand(onLogin: _login),
                FooterSection(onLogin: _login, onNavigate: _goTo),
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
              // The phone menu fades and drops in rather than popping.
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
// Layout helpers
// ---------------------------------------------------------------------------

bool _isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;

double _gutter(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width > AppSpacing.maxContentWidth + 2 * AppSpacing.xl
      ? (width - AppSpacing.maxContentWidth) / 2
      : AppSpacing.lg;
}

/// Body text. Headlines use [_display].
const _inter = AppFonts.body;
const _display = AppFonts.display;

/// A full-width band with centred, max-width content.
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
    final v = _isWide(context) ? 96.0 : 64.0;
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

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text, {this.onDark = false});
  final String text;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 2,
          color: onDark ? AppColors.brandGoldLight : AppColors.brandGold,
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: _inter,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: onDark
                  ? AppColors.brandGoldLight
                  : AppColors.brandGoldText,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.centered = false,
    this.onDark = false,
  });
  final String eyebrow, title, subtitle;
  final bool centered, onDark;

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    final align = centered ? TextAlign.center : TextAlign.left;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Column(
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          _Eyebrow(eyebrow, onDark: onDark),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: align,
            style: TextStyle(
              fontFamily: _display,
              fontSize: wide ? 38 : 28,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: onDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            subtitle,
            textAlign: align,
            style: TextStyle(
              fontFamily: _inter,
              fontSize: 16,
              height: 1.6,
              color: onDark ? AppColors.chromeText : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays [children] out in rows of [columns], each row as tall as its
/// tallest item.
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children});
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        if (c > 0) cells.add(const SizedBox(width: AppSpacing.lg));
        final index = i + c;
        cells.add(
          Expanded(
            child: index < children.length
                ? children[index]
                : const SizedBox.shrink(),
          ),
        );
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: AppSpacing.lg));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cells,
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

int _columnsFor(BuildContext context, {int wide = 4}) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= AppSpacing.wideBreakpoint) return wide;
  if (width >= 600) return 2;
  return 1;
}

/// Card that lifts and picks up a gold edge on hover.
class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.child, this.dark = false});
  final Widget child;
  final bool dark;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: dark ? AppColors.chromeRaised : AppColors.surface,
          borderRadius: AppRadii.lgAll,
          border: Border.all(
            color: _hover
                ? AppColors.brandGold
                : (dark ? AppColors.chromeBorder : AppColors.border),
          ),
          boxShadow: _hover && !dark
              ? const [
                  BoxShadow(
                    color: Color(0x1A6E5A22),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile(this.icon, {this.dark = false, this.size = 48});
  final IconData icon;
  final bool dark;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark ? const Color(0x26AC934F) : AppColors.selected,
        borderRadius: AppRadii.mdAll,
      ),
      child: Icon(
        icon,
        size: size * 0.5,
        color: dark ? AppColors.brandGoldLight : AppColors.brandGoldText,
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  const _GoldButton({
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
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.pillAll),
        padding: EdgeInsets.symmetric(
          horizontal: large ? AppSpacing.xl : AppSpacing.lg + 4,
          vertical: large ? AppSpacing.md + 6 : AppSpacing.md,
        ),
        textStyle: TextStyle(
          fontFamily: _inter,
          fontSize: large ? 15 : 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(label),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation
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

  /// Adds a shadow once the page has scrolled under the header.
  final bool elevated;

  /// The section currently in view, highlighted in the links.
  final LandingSection active;
  final bool isWide, menuOpen;
  final VoidCallback onLogin, onMenuToggle;
  final ValueChanged<LandingSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final side = _gutter(context);
    final logo = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onNavigate(LandingSection.home),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: QbLogo(size: isWide ? 48 : 42),
        ),
      ),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _navHeight,
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          // Thin gold rule along the top edge.
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.brandGold,
                  AppColors.brandGoldLight,
                  AppColors.brandGold,
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: side),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: elevated ? Colors.transparent : AppColors.border,
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (isWide)
                    logo
                  else
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: logo,
                      ),
                    ),
                  if (isWide) ...[
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final s in LandingSection.values)
                                _NavLink(
                                  label: s.label,
                                  selected: s == active,
                                  onTap: () => onNavigate(s),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                  ] else ...[
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      tooltip: menuOpen ? 'Close menu' : 'Menu',
                      onPressed: onMenuToggle,
                      icon: AnimatedSwitcher(
                        duration: AppMotion.fast,
                        transitionBuilder: (child, animation) =>
                            RotationTransition(
                              turns: Tween<double>(
                                begin: 0.75,
                                end: 1,
                              ).animate(animation),
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                        child: Icon(
                          menuOpen ? Icons.close_rounded : Icons.menu_rounded,
                          key: ValueKey(menuOpen),
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  _GoldButton(label: 'Login', onPressed: onLogin),
                ],
              ),
            ),
          ),
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
  });
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: selected
              ? AppColors.brandBlack
              : AppColors.textSecondary,
          overlayColor: AppColors.brandGold,
          // The app theme boxes text buttons in; nav links stay bare.
          backgroundColor: selected ? AppColors.selected : Colors.transparent,
          side: BorderSide.none,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.smAll),
          textStyle: TextStyle(
            fontFamily: _inter,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(height: AppSpacing.xs),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 2,
              width: selected ? 20 : 0,
              decoration: const BoxDecoration(
                color: AppColors.brandGold,
                borderRadius: AppRadii.pillAll,
              ),
            ),
          ],
        ),
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          for (final s in LandingSection.values)
            ListTile(
              title: Text(
                s.label,
                style: const TextStyle(
                  fontFamily: _inter,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
              shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
              onTap: () => onNavigate(s),
            ),
          const SizedBox(height: AppSpacing.lg),
          _GoldButton(
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
// Hero
// ---------------------------------------------------------------------------

class HeroSection extends StatelessWidget {
  const HeroSection({
    super.key,
    required this.onLogin,
    required this.onExplore,
  });
  final VoidCallback onLogin, onExplore;

  static const _imageUrl =
      'https://images.unsplash.com/photo-1486325212027-8021e42edcc7?auto=format&fit=crop&w=1920&q=80';

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    final side = _gutter(context);

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: AppRadii.pillAll,
            border: Border.all(
              color: AppColors.brandGold.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.brandGoldLight,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Flexible(
                child: Text(
                  'Queen Builders · Construction PMS',
                  style: TextStyle(
                    fontFamily: _inter,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
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
            fontSize: wide ? 46 : 32,
            height: 1.05,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'A centralized construction project management platform designed '
            'exclusively for Queen Builders — projects, schedules, materials, '
            'budgets and site progress in one place.',
            style: TextStyle(
              fontFamily: _inter,
              fontSize: wide ? 18 : 16,
              height: 1.6,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _GoldButton(
              label: 'Login to Your Account',
              onPressed: onLogin,
              large: true,
            ),
            OutlinedButton(
              onPressed: onExplore,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.transparent,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadii.pillAll,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md + 6,
                ),
                textStyle: const TextStyle(
                  fontFamily: _inter,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Explore Features'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl + AppSpacing.lg),
        const Wrap(
          spacing: AppSpacing.xl,
          runSpacing: AppSpacing.md,
          children: [
            _HeroPoint(Icons.verified_user_outlined, 'Role-based access'),
            _HeroPoint(Icons.hub_outlined, 'Single source of truth'),
            _HeroPoint(Icons.lock_outline_rounded, 'Authorized personnel only'),
          ],
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.chrome,
        image: DecorationImage(
          image: const NetworkImage(_imageUrl),
          fit: BoxFit.cover,
          opacity: 0.28,
          // Offline or blocked: keep the plain dark background.
          onError: (_, _) {},
        ),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xF2050505), Color(0xB3050505), Color(0x66050505)],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            side,
            _navHeight + (wide ? 96 : 56),
            side,
            wide ? 112 : 72,
          ),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 6, child: copy),
                    const SizedBox(width: 56),
                    const Expanded(flex: 5, child: _HeroPreview()),
                  ],
                )
              : copy,
        ),
      ),
    );
  }
}

class _HeroPoint extends StatelessWidget {
  const _HeroPoint(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.brandGoldLight),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: _inter,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}

/// Illustrative product preview: a stylised "projects at a glance" panel.
class _HeroPreview extends StatelessWidget {
  const _HeroPreview();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('Schedule', 0.72, Icons.calendar_month_rounded),
      ('Materials', 0.48, Icons.inventory_2_outlined),
      ('Site progress', 0.86, Icons.engineering_outlined),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.chromeRaised.withValues(alpha: 0.92),
        borderRadius: AppRadii.xlAll,
        border: Border.all(color: AppColors.chromeBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 48,
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const _IconTile(Icons.apartment_rounded, dark: true, size: 40),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Text(
                  'Project overview',
                  style: TextStyle(
                    fontFamily: _inter,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x2610B981),
                  borderRadius: AppRadii.pillAll,
                ),
                child: const Text(
                  'On track',
                  style: TextStyle(
                    fontFamily: _inter,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6EE7B7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final (label, value, icon) in rows) ...[
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.chromeText),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontFamily: _inter,
                      fontSize: 13,
                      color: AppColors.chromeText,
                    ),
                  ),
                ),
                Text(
                  '${(value * 100).round()}%',
                  style: const TextStyle(
                    fontFamily: _inter,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: AppRadii.pillAll,
              child: LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: AppColors.chromeBorder,
                valueColor: const AlwaysStoppedAnimation(AppColors.brandGold),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          const Divider(color: AppColors.chromeBorder, height: AppSpacing.xl),
          const Row(
            children: [
              Expanded(
                child: _PreviewStat(
                  label: 'Daily reports',
                  icon: Icons.assignment_turned_in_outlined,
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: _PreviewStat(
                  label: 'Approvals',
                  icon: Icons.fact_check_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewStat extends StatelessWidget {
  const _PreviewStat({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.chrome,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: AppColors.chromeBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.brandGoldLight),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: _inter,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  static const _pillars = [
    (
      Icons.folder_copy_outlined,
      'Centralized project information',
      'All project details, schedules, documents and communications live in one place, so authorized personnel always work from current information.',
    ),
    (
      Icons.groups_2_outlined,
      'Improved coordination',
      'Project Managers and Site Foremen stay aligned on daily priorities, task assignments and site progress through shared dashboards and updates.',
    ),
    (
      Icons.insights_rounded,
      'Progress monitoring',
      'Track construction progress against approved plans with real-time visibility into milestones, budgets and resource usage.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    const header = _SectionHeader(
      eyebrow: 'About the system',
      title: 'Every project, every site, one platform.',
      subtitle:
          'The Queen Builders Construction Project Management System centralizes project information and simplifies coordination across every phase of construction.',
    );
    final pillars = Column(
      children: [
        for (final (i, p) in _pillars.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.lg),
          _HoverCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconTile(p.$1),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.$2,
                        style: const TextStyle(
                          fontFamily: _inter,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs + 2),
                      Text(
                        p.$3,
                        style: const TextStyle(
                          fontFamily: _inter,
                          fontSize: 14,
                          height: 1.6,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    return _Band(
      color: AppColors.surface,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(flex: 5, child: header),
                const SizedBox(width: 64),
                Expanded(flex: 6, child: pillars),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: AppSpacing.xxl),
                pillars,
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Features
// ---------------------------------------------------------------------------

class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key});

  static const _features = [
    (
      Icons.manage_search_rounded,
      'Project Management',
      'Plan, track and oversee construction projects from initiation to close-out.',
    ),
    (
      Icons.task_alt_rounded,
      'Task Management',
      'Assign tasks, set priorities and monitor completion across teams.',
    ),
    (
      Icons.people_alt_outlined,
      'Employee Management',
      'Maintain worker records, roles and assignments for every project.',
    ),
    (
      Icons.event_note_outlined,
      'Schedule Management',
      'Build and maintain project schedules with key milestones and deadlines.',
    ),
    (
      Icons.payments_outlined,
      'Budget & Expense Monitoring',
      'Track project budgets, expenses and payments in one place.',
    ),
    (
      Icons.timeline_rounded,
      'Construction Progress Tracking',
      'Record and review actual progress against planned milestones.',
    ),
    (
      Icons.inventory_2_outlined,
      'Materials & Inventory',
      'Manage material requests, purchase orders and site inventory levels.',
    ),
    (
      Icons.description_outlined,
      'Reports & Documentation',
      'Generate progress reports and maintain project documentation.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _Band(
      color: AppColors.background,
      child: Column(
        children: [
          const _SectionHeader(
            eyebrow: 'System features',
            title: 'Everything a construction team needs',
            subtitle:
                'The major capabilities available to authorized personnel across the Queen Builders platform.',
            centered: true,
          ),
          const SizedBox(height: 56),
          _Grid(
            columns: _columnsFor(context),
            children: [
              for (final f in _features)
                _HoverCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _IconTile(f.$1),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        f.$2,
                        style: const TextStyle(
                          fontFamily: _inter,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        f.$3,
                        style: const TextStyle(
                          fontFamily: _inter,
                          fontSize: 14,
                          height: 1.55,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Key personnel
// ---------------------------------------------------------------------------

class KeyPersonnelSection extends StatelessWidget {
  const KeyPersonnelSection({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    const pm = _PersonnelCard(
      icon: Icons.assignment_ind_outlined,
      role: 'Project Manager',
      position: 'Project Delivery Lead',
      description:
          'Oversees the overall construction project from start to finish.',
      responsibilities: [
        'Manage project schedules, budgets and resources',
        'Coordinate employees and project activities',
        'Monitor project performance and completion',
      ],
    );
    const foreman = _PersonnelCard(
      icon: Icons.engineering_outlined,
      role: 'Site Foreman',
      position: 'Site Operations Lead',
      description:
          'Supervises daily construction site operations and reports progress to the Project Manager.',
      responsibilities: [
        "Assign and monitor workers' tasks",
        'Track actual construction progress',
        'Report site updates and concerns',
        'Ensure activities follow approved plans',
      ],
    );
    return _Band(
      color: AppColors.chrome,
      child: Column(
        children: [
          const _SectionHeader(
            eyebrow: 'Key personnel',
            title: 'Built around the people who build',
            subtitle:
                'The two primary roles responsible for delivering Queen Builders construction projects through the system.',
            centered: true,
            onDark: true,
          ),
          const SizedBox(height: 56),
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
        ],
      ),
    );
  }
}

class _PersonnelCard extends StatelessWidget {
  const _PersonnelCard({
    required this.icon,
    required this.role,
    required this.position,
    required this.description,
    required this.responsibilities,
  });
  final IconData icon;
  final String role, position, description;
  final List<String> responsibilities;

  @override
  Widget build(BuildContext context) {
    return _HoverCard(
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconTile(icon, dark: true, size: 56),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      position.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: _inter,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: AppColors.brandGoldLight,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      role,
                      style: const TextStyle(
                        fontFamily: _display,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            description,
            style: const TextStyle(
              fontFamily: _inter,
              fontSize: 15,
              height: 1.6,
              color: AppColors.chromeText,
            ),
          ),
          const Divider(
            color: AppColors.chromeBorder,
            height: AppSpacing.xxl + AppSpacing.sm,
          ),
          const Text(
            'KEY RESPONSIBILITIES',
            style: TextStyle(
              fontFamily: _inter,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.chromeText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final r in responsibilities)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: AppColors.brandGold,
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Text(
                      r,
                      style: const TextStyle(
                        fontFamily: _inter,
                        fontSize: 14,
                        height: 1.4,
                        color: Colors.white,
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

// ---------------------------------------------------------------------------
// How it works
// ---------------------------------------------------------------------------

class HowItWorksSection extends StatelessWidget {
  const HowItWorksSection({super.key});

  static const _steps = [
    (
      'Authorized personnel log in',
      'Users sign in with their company account through the secure sign-in window.',
    ),
    (
      'Access assigned projects',
      'Personnel reach the projects and responsibilities assigned to their role.',
    ),
    (
      'Project Managers coordinate',
      'Project Managers manage schedules, budgets, resources and project activities.',
    ),
    (
      'Site Foremen supervise',
      'Site Foremen oversee daily operations, assign tasks and submit progress updates.',
    ),
    (
      'Monitor and document',
      'Project information is tracked, monitored and documented through the system.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    return _Band(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: wide
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            eyebrow: 'How it works',
            title: 'From sign-in to site report',
            subtitle:
                'A simple, role-based workflow for managing construction projects from start to finish.',
            centered: wide,
          ),
          const SizedBox(height: 56),
          if (wide)
            Stack(
              children: [
                // Connector line behind the step markers.
                Positioned(
                  top: 23,
                  left: 0,
                  right: 0,
                  child: FractionallySizedBox(
                    widthFactor: 0.8,
                    child: Container(height: 2, color: AppColors.border),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, s) in _steps.indexed)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                          child: Column(
                            children: [
                              _StepMarker(i + 1),
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                s.$1,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: _inter,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                s.$2,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: _inter,
                                  fontSize: 13,
                                  height: 1.55,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            )
          else
            Column(
              children: [
                for (final (i, s) in _steps.indexed)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          children: [
                            _StepMarker(i + 1),
                            if (i < _steps.length - 1)
                              Expanded(
                                child: Container(
                                  width: 2,
                                  color: AppColors.border,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.md,
                              bottom: AppSpacing.xl,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.$1,
                                  style: const TextStyle(
                                    fontFamily: _inter,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  s.$2,
                                  style: const TextStyle(
                                    fontFamily: _inter,
                                    fontSize: 14,
                                    height: 1.55,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StepMarker extends StatelessWidget {
  const _StepMarker(this.number);
  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.brandBlack,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.brandGold, width: 2),
        boxShadow: const [BoxShadow(color: AppColors.surface, spreadRadius: 6)],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: const TextStyle(
          fontFamily: _inter,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.brandGoldLight,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Benefits
// ---------------------------------------------------------------------------

class BenefitsSection extends StatelessWidget {
  const BenefitsSection({super.key});

  static const _benefits = [
    (
      Icons.hub_outlined,
      'Centralized Project Management',
      'All project information in one secure, accessible platform.',
    ),
    (
      Icons.forum_outlined,
      'Improved Communication',
      'Clear coordination between Project Managers and Site Foremen.',
    ),
    (
      Icons.access_time_rounded,
      'Task & Schedule Monitoring',
      'Efficient tracking of assignments, deadlines and milestones.',
    ),
    (
      Icons.account_balance_wallet_outlined,
      'Budget & Resource Management',
      'Better visibility into project spending and resource allocation.',
    ),
    (
      Icons.assessment_outlined,
      'Accurate Progress Reporting',
      'Reliable documentation of construction progress and site updates.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    const header = _SectionHeader(
      eyebrow: 'System benefits',
      title: 'Less paperwork. More progress.',
      subtitle:
          'How the Queen Builders platform improves construction operations for authorized personnel.',
    );
    final list = _Grid(
      columns: MediaQuery.sizeOf(context).width >= 600 ? 2 : 1,
      children: [
        for (final b in _benefits)
          _HoverCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconTile(b.$1, size: 44),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.$2,
                        style: const TextStyle(
                          fontFamily: _inter,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs + 2),
                      Text(
                        b.$3,
                        style: const TextStyle(
                          fontFamily: _inter,
                          fontSize: 13,
                          height: 1.55,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    return _Band(
      color: AppColors.background,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(flex: 4, child: header),
                const SizedBox(width: 64),
                Expanded(flex: 7, child: list),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: AppSpacing.xxl),
                list,
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// FAQ
// ---------------------------------------------------------------------------

class FAQSection extends StatelessWidget {
  const FAQSection({super.key});

  static const _faqs = [
    (
      'Who can access the system?',
      'Access is limited to authorized Queen Builders personnel with a valid company account issued by the system administrator.',
    ),
    (
      'How can authorized personnel log in?',
      'Click Login at the top of the page, enter your company email and password, then sign in. Multi-role users may be asked to select a role after logging in.',
    ),
    (
      'What are the responsibilities of Project Managers?',
      'Project Managers oversee the overall project, manage schedules, budgets and resources, coordinate employees and activities, and monitor performance and completion.',
    ),
    (
      'What are the responsibilities of Site Foremen?',
      'Site Foremen supervise daily site operations, assign and monitor worker tasks, track actual progress, report updates and concerns to Project Managers, and ensure activities follow approved plans.',
    ),
    (
      'What features are available in the system?',
      'The system includes project management, task management, employee management, schedule management, budget and expense monitoring, construction progress tracking, materials and inventory management, and reports and documentation.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          eyebrow: 'FAQs',
          title: 'Frequently asked questions',
          subtitle:
              'Common questions about accessing and using the Queen Builders Construction Project Management System.',
        ),
        const SizedBox(height: AppSpacing.xl),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.selected,
            borderRadius: AppRadii.lgAll,
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.support_agent_rounded, color: AppColors.brandGoldText),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Need an account or locked out? Contact your system administrator for access.',
                  style: TextStyle(
                    fontFamily: _inter,
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final items = Column(
      children: [for (final f in _faqs) _FaqItem(question: f.$1, answer: f.$2)],
    );
    return _Band(
      color: AppColors.surface,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: header),
                const SizedBox(width: 64),
                Expanded(flex: 6, child: items),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: AppSpacing.xxl),
                items,
              ],
            ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  const _FaqItem({required this.question, required this.answer});
  final String question, answer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xs,
          ),
          iconColor: AppColors.brandGoldText,
          collapsedIconColor: AppColors.textSecondary,
          title: Text(
            question,
            style: const TextStyle(
              fontFamily: _inter,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  answer,
                  style: const TextStyle(
                    fontFamily: _inter,
                    fontSize: 14,
                    height: 1.6,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Call to action + footer
// ---------------------------------------------------------------------------

class _CtaBand extends StatelessWidget {
  const _CtaBand({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ready to get to work?',
          style: TextStyle(
            fontFamily: _display,
            fontSize: wide ? 32 : 26,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: AppColors.brandBlack,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Sign in with your Queen Builders company account to open your projects.',
          style: TextStyle(
            fontFamily: _inter,
            fontSize: 15,
            height: 1.5,
            color: Color(0xCC050505),
          ),
        ),
      ],
    );
    final button = FilledButton(
      onPressed: onLogin,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brandBlack,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.pillAll),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md + 6,
        ),
        textStyle: const TextStyle(
          fontFamily: _inter,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: const Text('Login to Your Account'),
    );
    return _Band(
      color: AppColors.background,
      top: 0,
      bottom: wide ? 96 : 64,
      child: Container(
        padding: EdgeInsets.all(wide ? 56 : AppSpacing.xl),
        decoration: const BoxDecoration(
          borderRadius: AppRadii.xlAll,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brandGoldLight, AppColors.brandGold],
          ),
        ),
        child: wide
            ? Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: AppSpacing.xl),
                  button,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  copy,
                  const SizedBox(height: AppSpacing.xl),
                  button,
                ],
              ),
      ),
    );
  }
}

class FooterSection extends StatelessWidget {
  const FooterSection({
    super.key,
    required this.onLogin,
    required this.onNavigate,
  });
  final VoidCallback onLogin;
  final ValueChanged<LandingSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(context);
    const muted = TextStyle(
      fontFamily: _inter,
      fontSize: 13,
      height: 1.6,
      color: AppColors.chromeText,
    );
    const heading = TextStyle(
      fontFamily: _inter,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: Colors.white,
    );

    final brand = const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QbLogo(size: 44, onDark: true),
        SizedBox(height: AppSpacing.lg),
        Text(
          'A centralized construction project management platform for Queen Builders personnel.',
          style: muted,
        ),
      ],
    );
    Widget link(String label, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.smAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(label, style: muted),
        ),
      ),
    );
    final links = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('QUICK LINKS', style: heading),
        const SizedBox(height: AppSpacing.lg),
        for (final s in LandingSection.values)
          link(s.label, () => onNavigate(s)),
      ],
    );
    final access = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ACCESS', style: heading),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          'For authorized Queen Builders personnel only.',
          style: muted,
        ),
        const SizedBox(height: AppSpacing.lg),
        _GoldButton(label: 'Login', onPressed: onLogin),
      ],
    );

    return _Band(
      color: AppColors.chrome,
      top: 72,
      bottom: AppSpacing.xxl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: brand),
                const SizedBox(width: 64),
                Expanded(flex: 2, child: links),
                const SizedBox(width: AppSpacing.xxl),
                Expanded(flex: 3, child: access),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                brand,
                const SizedBox(height: AppSpacing.xxl),
                links,
                const SizedBox(height: AppSpacing.xl),
                access,
              ],
            ),
          const SizedBox(height: 56),
          const Divider(color: AppColors.chromeBorder, height: 1),
          const SizedBox(height: AppSpacing.xl),
          Text(
            '© ${DateTime.now().year} Queen Builders Construction Project Management System.',
            style: muted.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
