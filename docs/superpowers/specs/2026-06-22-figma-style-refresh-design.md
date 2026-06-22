# Figma Style Refresh Design

## Goal

Apply the Figma `swm design` common design system to the existing Flutter app without changing backend behavior or screen flow.

## Scope

Use approach B: refresh the shared theme, common components, and key screens while preserving current navigation and data APIs.

In scope:

- Replace the Meta blue/black theme with the Figma pink study palette.
- Update shared buttons, input fields, chips, cards, and panel chrome.
- Restyle the right-side menu as Figma-style 44px icon buttons.
- Restyle onboarding controls, study material cards, quiz controls, wardrobe/profile surfaces where they use shared tokens.
- Keep the visual novel full-screen experience intact, but align overlay buttons and badges with the new system.

Out of scope:

- New app navigation.
- New backend storage or API behavior.
- New Figma asset import pipeline.
- Rebuilding every screen from scratch.

## Design Tokens

Colors:

- Background: `#FFF5F7`
- Surface/card: `#FFFFFF`
- Divider/border: `#F0D6E0`
- Primary text: `#2D1B33`
- Secondary text: `#9B8A9F`
- Disabled: `#D6CDD9`
- Icon base: `#E8E0EB`
- Primary accent: `#E8457A`
- Primary pressed: `#C03260`
- Accent soft: `#FFE4EC`
- Character accents: `#F2426B`, `#E34FCF`, and soft variants where needed.

Typography:

- Use the app's existing Flutter font setup, but tune sizes and weights to the Figma scale.
- Primary title: 24 bold.
- Section title: 20/28 bold.
- Body: 16/24 regular.
- Secondary body: 14/21 regular.
- Labels/status: 12/18 regular or bold.
- Remove negative letter spacing from the current theme.

Shape and spacing:

- Primary and secondary text buttons are pill shaped.
- Icon buttons are 44px with 14px radius and 18px icons.
- Cards use white surfaces, pink border, 16px padding, and modest radius.
- Chips use soft pink backgrounds with accent or secondary text.

## Component Changes

`MetaTheme` becomes the source of the Figma tokens. Existing names remain where possible to avoid broad rewrites.

`RoundedSection` becomes a Figma card surface: white background, pink border, smaller shadow or no shadow, and consistent padding.

Buttons:

- `FilledButton`: primary accent background, white text, 48-56px height depending on context.
- `OutlinedButton`: accent border and accent text, soft pressed state.
- Disabled buttons use disabled color and white/soft backgrounds.

Icon buttons:

- Side menu uses white or soft-accent square buttons with 14px radius instead of dark circular buttons.
- Labels use 10-11px secondary text.

Inputs and chips:

- Inputs use white fill, pink border, primary text, and accent focus border.
- Choice/filter chips use Figma soft accent states.

## Screen Changes

Onboarding:

- Keep the 3-step wizard.
- Restyle title, step indicator, form fields, and chips.
- Keep existing validation and character creation behavior.

Study panel:

- Convert the PDF section to a StudyCard-style surface.
- Material rows become bordered rows with soft selected states.
- Upload and quiz buttons use primary/secondary Figma styles.
- Quiz generation notice uses the shared card surface.

Shell and panels:

- Main panel background uses `#FFF5F7`.
- Panel app bars use white surfaces and pink dividers.
- Side menu becomes a compact vertical Figma icon button rail.

Visual quiz:

- Keep the full-screen character image.
- Restyle close/progress/difficulty controls and the bottom quiz card with the Figma palette.
- Preserve existing answer, explanation, and affinity behavior.

Wardrobe and profiles:

- Shared theme changes should automatically improve controls.
- Make targeted edits only where local widgets hard-code old Meta colors or card shapes.

## Rollback Strategy

Before implementation, commit this spec and plan as a checkpoint. Implementation changes should be made in a separate commit or left as a clear working-tree diff. If the visual refresh is rejected, revert the implementation commit or restore only the files changed by the refresh.

Existing unrelated work must be preserved. At the time of writing, `frontend/pubspec.lock` already has local modifications and should not be included in the style-refresh checkpoint unless explicitly requested.

## Verification

- Run `flutter analyze` in `frontend`.
- Run Flutter web or the available app target if dependencies are present.
- Capture or manually inspect the main flows: onboarding, visual novel shell, study panel, quiz view, wardrobe, and profiles.
- Confirm no text overlaps at common mobile and desktop widths.
