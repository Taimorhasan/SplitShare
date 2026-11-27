---
name: SplitShare
description: Chai & Pista — a warm cream page, pistachio for money coming back, pomegranate for money you owe, saffron for the add button.
colors:
  page: "#F6F1E7"
  surface: "#FFFDF8"
  surface-muted: "#EFE8DA"
  border: "#E5DCCB"
  text: "#23201A"
  text-secondary: "#6E6857"
  text-muted: "#8F887A"
  pistachio: "#3C6B22"
  pistachio-tint: "#E1EECF"
  balance-card: "#D5E8B5"
  on-balance-card: "#1F2A14"
  owes-you: "#2F5F20"
  pomegranate: "#B3263E"
  pomegranate-tint: "#F6DDE1"
  saffron: "#E39B17"
  nav-pill: "#23201A"
  night-page: "#15130F"
  night-surface: "#1F1C16"
  night-border: "#332E25"
  night-text: "#F1EBDD"
  night-pistachio: "#A9D18E"
  night-balance-card: "#2C3B1E"
  night-pomegranate: "#FF8E9C"
typography:
  total:
    fontFamily: "Figtree"
    fontSize: "42px"
    fontWeight: 800
    letterSpacing: "-1.2px"
  headline:
    fontFamily: "Figtree"
    fontSize: "26px"
    fontWeight: 800
  title:
    fontFamily: "Figtree"
    fontSize: "18px"
    fontWeight: 800
  body:
    fontFamily: "Figtree"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: "Figtree"
    fontSize: "12.5px"
    fontWeight: 600
rounded:
  sm: "10px"
  md: "14px"
  lg: "20px"
  xl: "26px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  page: "20px"
  xxl: "24px"
components:
  button-primary:
    backgroundColor: "{colors.pistachio}"
    textColor: "{colors.surface}"
    rounded: "{rounded.md}"
    height: "52px"
  balance-card:
    backgroundColor: "{colors.balance-card}"
    textColor: "{colors.on-balance-card}"
    rounded: "{rounded.xl}"
    padding: "22px"
  card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.lg}"
    padding: "16px"
  nav-pill:
    backgroundColor: "{colors.nav-pill}"
    rounded: "31px"
    height: "62px"
  nav-add:
    backgroundColor: "{colors.saffron}"
    textColor: "{colors.text}"
    rounded: "23px"
---

# Design System: SplitShare

<!-- impeccable:design-map -->
Name: SplitShare
Colors: primary: pistachio #3C6B22; secondary: pomegranate #B3263E; tertiary: saffron #E39B17; neutral: cream #F6F1E7; neutral: chai #15130F
Fonts: Figtree (total, headline, title, body, label)
Spacing: xs 4px, sm 8px, md 12px, lg 16px, page 20px, xxl 24px
Radius: sm 10px, md 14px, lg 20px, xl 26px
Don't:
- Don't add gradients, glows, card shadows, emoji icons or eyebrow labels.
- Don't use `Colors.white` on coloured fills; use `AppColors.onPrimary` / `onAccent` so dark mode works.
Do:
- Do read colours from `AppColors` getters at build time (never `const`, never static final).
- Do keep one balance card per screen.
Map: lib/core/app_colors.dart
Map: lib/core/app_theme.dart
Map: lib/core/widgets/
Map: tool/render_app_icon_test.dart
Map: assets/fonts
Map: lib/core/widgets/balance_card.dart
Full: .impeccable/design-full.md (read a section when you need its detail)
