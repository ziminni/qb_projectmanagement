import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared timing for the app's motion, so every transition feels the same.
abstract final class AppMotion {
  /// Small state changes: hover, selection, colours.
  static const fast = Duration(milliseconds: 160);

  /// Content swaps, menus and dialogs.
  static const medium = Duration(milliseconds: 240);

  /// Page changes.
  static const page = Duration(milliseconds: 300);
  static const pageReverse = Duration(milliseconds: 220);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;

  /// For [AnimatedSwitcher]s: the new child fades in only once the old one
  /// is mostly gone, so the two never sit half-visible on top of each other.
  static const switchIn = Interval(0.35, 1, curve: Curves.easeOutCubic);
  static const switchOut = Interval(0.6, 1, curve: Curves.easeIn);

  /// The app's page transition, a fade-through: the outgoing page fades out
  /// over the first third, then the new page fades in while drifting up a
  /// few pixels. No sideways slide, and the pages barely overlap.
  static Widget fadeThrough(
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final incoming = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.25, 1, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.4, 1, curve: Curves.easeIn),
    );
    final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: const Interval(0, 0.35, curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(outgoing),
      child: FadeTransition(
        opacity: incoming,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(incoming),
          child: child,
        ),
      ),
    );
  }

  /// A go_router page using [fadeThrough].
  static Page<void> goPage({required LocalKey key, required Widget child}) =>
      CustomTransitionPage<void>(
        key: key,
        child: child,
        transitionDuration: page,
        reverseTransitionDuration: pageReverse,
        transitionsBuilder: (context, animation, secondary, child) =>
            fadeThrough(animation, secondary, child),
      );

  /// Dialog entrance: fade with a slight scale up.
  static Widget dialog(Animation<double> animation, Widget child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: enter,
      reverseCurve: exit,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}

/// [AppMotion.fadeThrough] for routes pushed with `Navigator.push`, on every
/// platform.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.page;

  @override
  Duration get reverseTransitionDuration => AppMotion.pageReverse;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => AppMotion.fadeThrough(animation, secondaryAnimation, child);
}
