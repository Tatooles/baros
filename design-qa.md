# Baros Marketing Site Design QA

- Source visual truth: `/var/folders/0b/qtw7v97n21v4h2hvyp7yrb2m0000gn/T/codex-clipboard-91af3a8a-3ec3-462e-87f8-d2e2667ca6f9.png`
- Desktop implementation: `/private/tmp/baros-site-qa/implementation-annotations-desktop.jpg`
- Annotated viewport implementation: `/private/tmp/baros-site-qa/implementation-annotations.jpg`
- Mobile implementation: `/private/tmp/baros-site-qa/implementation-mobile-hero.jpg`
- Mobile annotated implementation: `/private/tmp/baros-site-qa/implementation-annotations-mobile.jpg`
- Mobile product story: `/private/tmp/baros-site-qa/implementation-mobile-story.jpg`
- Mobile Privacy navigation: `/private/tmp/baros-site-qa/navigation-privacy-mobile-top.jpg`
- Mobile Support navigation: `/private/tmp/baros-site-qa/navigation-support-mobile.jpg`
- Desktop viewport: 1488 × 1058 CSS px
- Mobile viewport: 390 × 844 CSS px
- Navigation regression viewport: 409 × 863 CSS px
- Source pixels: 1487 × 1058
- Desktop implementation pixels: 1488 × 1058
- Mobile implementation pixels: 390 × 844
- Density normalization: the desktop source and implementation were compared at their native, effectively 1:1 pixel sizes. No density conversion was needed.
- State: signed-out marketing homepage with the hero at page load; product-story section after activating the primary CTA; Privacy and Support document routes.

## Full-view comparison evidence

The source and final desktop capture were opened together in the same comparison pass. The implementation preserves the source's warm off-white canvas, restrained navigation, left editorial hero, right product screen, official App Store badge artwork, coral accent, broad negative space, and three-column feature strip. The intentionally different product image is a real Baros simulator capture rather than the light mock application shown in the source.

The final opening viewport includes the top of the feature strip, matching the source's hierarchy. The real app screen is undistorted, sharp at its rendered size, and presented with a restrained device-like border and shadow.

## Focused-region comparison evidence

The hero and product screen were large enough to inspect type, crop, image quality, radii, border, and shadow in the full-size 1488 × 1058 comparison, so a separate desktop crop was not needed. Mobile hero and product-story captures were reviewed separately to verify wrapping, spacing, CTA treatment, product-image crop, and the responsive navigation.

## Required fidelity surfaces

- Fonts and typography: system San Francisco fallbacks closely match the source. Display sizing, tight tracking, line height, and body hierarchy are consistent, legible, and stable across desktop and mobile.
- Spacing and layout rhythm: desktop section alignment and negative space follow the reference. Mobile collapses to one column with no horizontal overflow at 390 px.
- Colors and visual tokens: warm neutral canvas, near-black type, coral accent, pale borders, and restrained elevation align with the reference while picking up the real app's accent.
- Image quality and asset fidelity: the app icon and both product screens come from the built Baros app. The App Store badge is Apple's official unmodified artwork. No placeholder product art, custom SVG substitute, or fake app UI is used.
- Copy and content: product claims match implemented Baros behavior: local use without an account, offline logging, and optional account-backed sync.
- Accessibility and behavior: semantic landmarks and headings are present; images have useful alternative text; focus styles and reduced-motion handling are included; the primary CTA, Privacy route, and Support route were exercised successfully.

## Comparison history

1. Initial pass found two P2 issues: the hero image retained its HTML height while its CSS width changed, visibly distorting the app screen, and the resulting oversized hero pushed the feature strip below the reference viewport.
2. Fix: set responsive images to `height: auto`, rebalanced the hero's minimum height and device width, and aligned the copy inset and display scale more closely to the source.
3. Post-fix evidence: `/private/tmp/baros-site-qa/implementation-desktop.jpg` shows the undistorted real screen and the feature strip entering the 1488 × 1058 opening viewport.
4. Mobile route testing found one P2 issue: the generic first-link hiding rule also hid Support on document pages.
5. Fix: scope that rule to the marketing header only.
6. Post-fix evidence: the final Privacy and Support DOM snapshots each expose both document links at 390 px, and both routes load with their expected titles.
7. Browser annotations requested removal of the trust pill's empty trailing space and replacement of the coral CTA with the original-style App Store badge.
8. Fix: size the desktop trust pill to its contents, use Apple's official badge artwork, and retain a separate working `See how it works` link. Post-fix evidence: `/private/tmp/baros-site-qa/implementation-annotations.jpg` and `/private/tmp/baros-site-qa/implementation-annotations-desktop.jpg`.
9. A mobile annotation identified excessive space and an inherited divider above `THE WORKOUT IS THE INTERFACE`; the hero's `QUIET NATIVE` label was also judged to be nonessential editorial copy.
10. Fix: remove `QUIET NATIVE`, reduce only the mobile product-story top padding, and clear the story heading's generic top border and padding at the mobile breakpoint. Desktop product-story spacing remains unchanged.
11. Navigation testing found one P2 consistency issue: the Privacy and Support links changed positions between the homepage and document pages.
12. Fix: standardize all headers to `Privacy` then `Support`. Post-fix evidence: `/private/tmp/baros-site-qa/navigation-privacy-mobile-top.jpg` and `/private/tmp/baros-site-qa/navigation-support-mobile.jpg`; navigating in both directions preserves the order and current-page underline.

## Findings

No actionable P0, P1, or P2 findings remain.

The App Store badge is intentionally not clickable because the repository does not provide a verified live App Store product URL. The adjacent product-tour link remains functional.

## Primary interactions tested

- `See how it works` scrolls to `#inside-the-app`.
- `See how Baros handles your data` opens `/privacy`.
- The Privacy header opens `/support`.
- Privacy and Support retain the same header positions when navigating in either direction.
- Both document routes expose Home, Support, and Privacy navigation on mobile.
- Browser console errors checked: none.

## Follow-up polish

- P3: link the official App Store badge once a verified product-page URL exists.

## Implementation checklist

- [x] Real Baros app icon and screens
- [x] Desktop visual comparison
- [x] Mobile responsive check
- [x] Primary CTA and document navigation
- [x] Privacy and Support routes preserved
- [x] Console error check

final result: passed
