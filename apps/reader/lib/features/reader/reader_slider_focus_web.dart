import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'reader_page_navigation.dart' show readerPageSliderIdentifier;

const _sliderSelector =
    '[flt-semantics-identifier="$readerPageSliderIdentifier"] input[role="slider"]';

/// Flutter Web briefly disables the range input when the browser reports the
/// pointer leaving a shrinking viewport. Wait for that same input to reenable
/// before restoring keyboard focus displaced to the page body.
void Function() preserveReaderSliderFocus() {
  final listeners = web.AbortController();
  final options = web.AddEventListenerOptions(signal: listeners.signal);
  final capture = web.AddEventListenerOptions(
    signal: listeners.signal,
    capture: true,
  );
  var height = web.window.innerHeight;
  web.HTMLInputElement? pending;
  late final web.MutationObserver observer;

  void cancel() {
    pending = null;
    observer.disconnect();
  }

  observer = web.MutationObserver(
    (() {
      final input = pending;
      if (input == null || input.disabled) return;
      cancel();
      if (input.isConnected &&
          input.matches(_sliderSelector) &&
          input.closest('[aria-disabled="true"]') == null &&
          web.document.hasFocus() &&
          web.document.activeElement?.isSameNode(web.document.body) == true) {
        input.focus(web.FocusOptions(preventScroll: true));
      }
    }).toJS,
  );

  void track(web.EventTarget? target) {
    if (target == null || !target.isA<web.HTMLInputElement>()) return;
    final input = target as web.HTMLInputElement;
    if (!input.disabled || !input.matches(_sliderSelector)) return;
    cancel();
    pending = input;
    observer.observe(
      input,
      web.MutationObserverInit(
        attributes: true,
        attributeFilter: ['disabled'.toJS].toJS,
      ),
    );
  }

  web.window.addEventListener(
    'resize',
    ((web.Event _) {
      final next = web.window.innerHeight;
      if (next < height) track(web.document.activeElement);
      height = next;
    }).toJS,
    options,
  );
  web.document.addEventListener(
    'focusout',
    ((web.FocusEvent event) {
      if (event.relatedTarget == null && web.window.innerHeight < height) {
        track(event.target);
      }
    }).toJS,
    capture,
  );
  web.document.addEventListener(
    'focusin',
    ((web.Event _) {
      // The body can receive the browser's fallback focus during the resize.
      if (pending != null &&
          web.document.activeElement?.isSameNode(web.document.body) != true) {
        cancel();
      }
    }).toJS,
    capture,
  );
  final onInteraction = ((web.Event _) => cancel()).toJS;
  for (final type in ['keydown', 'pointerdown', 'wheel', 'visibilitychange']) {
    web.document.addEventListener(type, onInteraction, capture);
  }
  web.window.addEventListener('blur', onInteraction, options);
  return () {
    cancel();
    listeners.abort();
  };
}
