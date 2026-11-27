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

## Overview

Chai & Pista: warm and friendly, like splitting the bill over chai. A cream page, soft rounded cards, pistachio green for what comes back to you, pomegranate for what you owe and one saffron add button. Dark mode is the same set on roasted-chai brown.

Operate app: one-handed, answer "who owes whom" fast. Source of truth: `lib/core/app_colors.dart`, `lib/core/app_theme.dart`, `lib/core/widgets/`.

## Colors

- **Pistachio** `#3C6B22` (night `#A9D18E`): primary buttons, links, selection, "owes you".
- **Balance card** `#D5E8B5` with `#1F2A14` text (night `#2C3B1E` / `#D9EDB8`).
- **Pomegranate** `#B3263E` (night `#FF8E9C`): "you owe", destructive actions, errors.
- **Saffron** `#E39B17`: only the add button and badges.
- **Logo / splash**: split coin (saffron + pistachio halves) on espresso `#1C1813`; splash on the same espresso.
- Neutrals: page `#F6F1E7`, cards `#FFFDF8`, border `#E5DCCB`, text `#23201A` / `#6E6857` (night `#15130F`, `#1F1C16`, `#332E25`, `#F1EBDD`).
- People get a stable identity colour (`AppColors.forKey`): saffron, indigo, pomegranate, pistachio, plum, teal, terracotta, olive.

**Rule:** money direction always has words ("owes you" / "you owe") as well as colour.

## Typography

Figtree (bundled, `assets/fonts`, OFL) with tabular figures on every style. Totals 42/800, paise set smaller. Headlines 26/800, section titles 18/800, body 14–16.

## Layout

Page padding 20. Home: greeting, balance card with split bar, friend cards in a horizontal row, quick actions in round pistachio-tint circles, Lain Dain, month, recent activity.

## Elevation & Depth

No card shadows. Cards separate by a lighter fill plus a 1px border. Only sheets and toasts float (`AppShadows.sheet`).

## Shapes

Rounded: 10 / 14 / 20, 26 for the balance card and sheets, pills for chips and nav.

## Components

- **BalanceCard** (`lib/core/widgets/balance_card.dart`): one per screen. Pistachio by default, pomegranate tint when you owe, muted when settled. Optional owed/owe split bar and a `trailing` icon.
- **Buttons**: flat, 52px, radius 14; primary = pistachio.
- **Cards** (`AppCard`): cream surface, 1px border, radius 20.
- **Nav**: a floating dark pill, icon-only with tooltips and screen-reader labels; the selected tab sits on a pistachio capsule; saffron add button in the middle.

## Do's and Don'ts

- **Do** read colours from `AppColors` getters at build time (never `const`, never static final).
- **Do** keep one balance card per screen.
- **Don't** add gradients, glows, card shadows, emoji icons or eyebrow labels.
- **Don't** use `Colors.white` on coloured fills; use `AppColors.onPrimary` / `onAccent` so dark mode works.
