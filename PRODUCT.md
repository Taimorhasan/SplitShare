# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

People in Pakistan who share money with the same circle of people again and again:

- university / hostel students and friends splitting food, rides, trips and events;
- roommates and families sharing rent, bills and groceries every month;
- a group on a trip or day out where several people pay through the day and want one clear answer at the end;
- anyone splitting a bill with someone else.

They open the app in the middle of real life — at a dhaba table, in a car, at month end — usually one-handed, often to answer one question: "who owes whom, and how much?"

## Product Purpose

SplitShare records shared spending and turns it into exact, trustworthy balances so friends never argue about money. Success is that every person sees the same number, understands where it comes from, and can settle it in a tap.

## Positioning

Two ways to split, built for how groups here actually spend:

- **Expenses & groups** with friends who use the app (equal, percent, exact, or full-amount splits; partial payments; reminders).
- **Lain Dain** — a give-and-take tab for a trip or day out where people *don't* need the app: log who paid, choose who shared each payment, and get pair-by-pair "X pays Y" amounts after cancelling, or the fewest-payments route.

Balances from both are combined per person and per currency, so "you owe Usman Rs 444" is the same number everywhere.

## Operating Context

- Phones only (Android first in testing; iPhone supported), portrait, frequently on mid-range Android hardware.
- Used quickly and repeatedly: add a payment, check a balance, settle up.
- Data lives in Firebase (Auth + Firestore, free Spark plan); photos (avatars, receipts) are stored in Firestore, not Firebase Storage.
- Works offline from a local cache, then syncs.

## Capabilities and Constraints

- Sign-in: email/password, Google, Apple (Apple shown on Apple devices).
- Friends: search by name/email, QR code / friend code, phone contacts (matched by email on-device), requests.
- Groups: create, edit, add members, leave (only when settled), delete (creator only).
- Expenses: categories, date, notes, receipt photo; split Equally / Percent / Exact / Full amount; edit/delete by creator.
- Settle up: record partial payments, settle everything, send reminders; Lain Dain pay-backs are marked inside the trip.
- Multi-currency: each expense keeps its currency; balances are per currency, never converted.
- In-app notifications only (no push).
- Must stay free to run: no paid Firebase features.

Terminology: "Lain Dain" (the trip/give-and-take feature), "Settle up", "owes you" / "you owe", "Rs" for PKR.

## Brand Commitments

- Name: **SplitShare**.
- Language: English UI; "Lain Dain" kept as the Urdu name of the give-and-take feature.
- Main currency: **PKR (Rs)**; other currencies remain available.
- App icon / mark: a wallet with a "split" badge (currently rendered from `AppLogo`). Its colours may change with the redesign.

## Evidence on Hand

- No testimonials, user numbers, ratings or press exist. None may be invented in the app or store copy.
- Real example the user gave for Lain Dain: Ahad 8,000, Ali 7,500, Usman 890, Taimoor 500.

## Product Principles

1. **The number is the product.** Every balance must be exact, identical across screens, and explainable in one line.
2. **One-handed and quick.** The most common actions (add payment, see who owes whom, settle) are reachable in one or two taps.
3. **Clarity over decoration.** Nothing on screen that doesn't carry information or an action.
4. **Works for people without the app.** Lain Dain never assumes everyone has an account.
5. **Free to run.** No feature may require a paid backend tier.

## Accessibility & Inclusion

- Readable in bright sunlight and at night (light and dark modes), respecting the system setting.
- Honour large system text sizes (layouts must not break up to ~130%).
- Amounts are never conveyed by colour alone (always "owes you" / "you owe" text as well).
