# Figma Style Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the Figma `swm design` visual system to the current Flutter app while preserving all existing app behavior.

**Architecture:** Keep the existing Flutter screen structure and API flow. Centralize visual changes in `MetaTheme` and shared components first, then make targeted screen edits only where old colors, radii, or surfaces are hard-coded.

**Tech Stack:** Flutter, Dart, Material 3, existing FastAPI backend unchanged.

---

## File Structure

- Modify: `frontend/lib/app/theme/meta_theme.dart`
  - Owns Figma color tokens, radius, spacing, Material theme, button styles, input styles, chip styles, app bar styles, and dialog defaults.
- Modify: `frontend/lib/features/shared/rounded_section.dart`
  - Turns shared sections into Figma-style white cards with pink border and consistent padding.
- Modify: `frontend/lib/features/shell/study_shell.dart`
  - Updates panel background/app bar and right-side icon rail.
- Modify: `frontend/lib/features/onboarding/onboarding_screen.dart`
  - Updates wizard header, step indicator, chips, and bottom actions to match Figma tone.
- Modify: `frontend/lib/features/study/study_screen.dart`
  - Updates study material section, material rows, quiz notice, visual quiz controls, bottom quiz card, badges, and answer controls.
- Inspect and optionally modify: `frontend/lib/features/wardrobe/wardrobe_screen.dart`, `frontend/lib/features/profiles/profiles_screen.dart`, `frontend/lib/features/profiles/character_edit_screen.dart`, `frontend/lib/features/play/play_screen.dart`
  - Only change local old-theme hard-coding that does not pick up shared theme changes.

## Task 1: Baseline and Theme Tokens

- [ ] **Step 1: Confirm current working tree**

Run:

```powershell
git status --short
```

Expected: note pre-existing `frontend/pubspec.lock` modification and do not include it in commits for this refresh.

- [ ] **Step 2: Update Figma tokens in `meta_theme.dart`**

Replace the existing Meta blue/black palette with the Figma palette while preserving commonly used symbol names. Add explicit Figma names for new usages:

```dart
class MetaColors {
  static const primary = Color(0xFFE8457A);
  static const primaryDeep = Color(0xFFC03260);
  static const primarySoft = Color(0xFFFFE4EC);
  static const canvas = Color(0xFFFFF5F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFFFE4EC);
  static const inkButton = Color(0xFFE8457A);
  static const inkDeep = Color(0xFF2D1B33);
  static const ink = Color(0xFF2D1B33);
  static const steel = Color(0xFF9B8A9F);
  static const stone = Color(0xFFD6CDD9);
  static const hairline = Color(0xFFF0D6E0);
  static const hairlineSoft = Color(0xFFF0D6E0);
  static const iconBase = Color(0xFFE8E0EB);
  static const characterRed = Color(0xFFF2426B);
  static const characterMagenta = Color(0xFFE34FCF);
  static const success = Color(0xFF31A24C);
  static const warning = Color(0xFFF7B928);
  static const critical = Color(0xFFE41E3F);
}
```

- [ ] **Step 3: Update text, button, input, chip, app bar, and dialog theme**

Use Figma type scale: 24 bold titles, 20/28 section titles, 16/24 body, 14/21 body, 12/18 labels. Set `letterSpacing: 0` throughout. Configure `FilledButton`, `OutlinedButton`, `InputDecorationTheme`, `ChipThemeData`, `AppBarTheme`, and `DialogTheme`.

- [ ] **Step 4: Run static analysis**

Run:

```powershell
flutter analyze
```

from `frontend`. Expected: no new analyzer errors from theme edits.

## Task 2: Shared Card and Shell Chrome

- [ ] **Step 1: Update `RoundedSection`**

Make it default to white surface, `MetaColors.hairline` border, 16px radius or the local radius argument, and Figma padding. Keep the public constructor compatible.

- [ ] **Step 2: Update panel scaffold in `study_shell.dart`**

Set panel background to `MetaColors.canvas`, app bar to `MetaColors.surface`, add a pink bottom divider, and restyle the leading close/back icon as a Figma icon button.

- [ ] **Step 3: Update side menu in `study_shell.dart`**

Change `_SideButton` from a dark circle to a 44x44 rounded rectangle with 14px radius. Use selected-looking soft pink surface and accent icon color. Keep current callbacks and labels.

- [ ] **Step 4: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: no new analyzer errors from shared chrome edits.

## Task 3: Onboarding Wizard Refresh

- [ ] **Step 1: Restyle onboarding scaffold**

Use `MetaColors.canvas` background, Figma title scale, and white/pink bordered bottom action area if needed.

- [ ] **Step 2: Restyle `_StepIndicator`**

Use `MetaColors.primary` for active bars, `MetaColors.hairline` for inactive, 6px height, and secondary labels with active bold primary text.

- [ ] **Step 3: Restyle local gender chips**

Use Figma accent states instead of blue/red gender-specific colors unless the selected value needs semantic distinction. Keep selected text readable.

- [ ] **Step 4: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: no new analyzer errors from onboarding edits.

## Task 4: Study and Visual Quiz Refresh

- [ ] **Step 1: Restyle study PDF section**

Keep existing upload, select, delete, and quiz logic. Update the copy surface to shared card styling and make material rows match bordered Figma cards.

- [ ] **Step 2: Restyle `_GeneratingQuizNotice`, `_ErrorBanner`, `_AffinityGainBar`, `_TutorReactionBubble`, and `_ChoiceButton`**

Use Figma palette and shapes while preserving all method signatures and behavior.

- [ ] **Step 3: Restyle `_VisualQuiz` controls**

Use Figma icon button/badge colors for close, progress, difficulty, and bottom quiz card. Keep image fit and gradient readability.

- [ ] **Step 4: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: no new analyzer errors from study and quiz edits.

## Task 5: Secondary Screens and Verification

- [ ] **Step 1: Inspect remaining old-token hard-coding**

Run:

```powershell
rg -n "MetaColors\\.(primaryDeep|inkButton|surfaceSoft|hairlineSoft|steel|stone)|Color\\(0xFF0064E0\\)|Color\\(0xFF0457CB\\)|Colors\\.blue" frontend/lib
```

Expected: any results are either compatible aliases or targeted for update.

- [ ] **Step 2: Apply targeted wardrobe/profile/play polish**

Update only local surfaces that visibly conflict with the new shared theme.

- [ ] **Step 3: Run analysis and app build smoke test**

Run:

```powershell
flutter analyze
flutter build web
```

Expected: analysis passes and web build completes.

- [ ] **Step 4: Review rollback diff**

Run:

```powershell
git diff --stat
git diff -- frontend/lib/app/theme/meta_theme.dart frontend/lib/features/shared/rounded_section.dart frontend/lib/features/shell/study_shell.dart frontend/lib/features/onboarding/onboarding_screen.dart frontend/lib/features/study/study_screen.dart
```

Expected: visual-only changes, no backend/API behavior changes, no unrelated `frontend/pubspec.lock` inclusion.
