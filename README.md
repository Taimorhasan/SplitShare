# SplitShare 💸

SplitShare is a cross-platform Flutter app for splitting bills and tracking shared
expenses with friends, roommates and groups. It uses **GetX** for state and
navigation and **Firebase** (Auth, Cloud Firestore, Storage) as the backend.

## Features

- **Dashboard** – net balance, what you're owed and what you owe (per currency),
  this month's spending by category, top balances and recent activity.
- **Expenses** – add or edit expenses with categories, date, notes and receipt
  photos. Split **equally**, by **percentage** or by **exact amounts**; equal and
  percentage splits are distributed to the cent so they always add up.
- **Settle up** – record partial payments or settle everything with a friend,
  send payment reminders. Payments appear in history and reduce balances.
- **Groups** – trips, homes, couples… with group balances, member management,
  editing, leaving (once settled) and deletion (creator only).
- **Friends** – search by name or email, QR code / friend code, scan a QR code,
  match your phone contacts by email (on-device), friend requests, per-friend
  balances and shared expense history.
- **Notifications** – in-app inbox for requests, new expenses, payments and
  reminders, with deep links. Can be switched off in Profile.
- **Profile** – edit name/photo/phone (phone is private), default currency,
  change password, export your data as JSON, help & FAQ.
- **Multi-currency** – every expense keeps its own currency; balances are tracked
  per currency (no conversion).

## Tech stack

| Area | Choice |
|---|---|
| Framework | Flutter (Material 3), Dart 3 |
| State / routing | GetX (`GetxController`, `Obx`, named routes) |
| Backend | Firebase Auth, Cloud Firestore, Firebase Storage |
| Key packages | `image_picker`, `cached_network_image`, `qr_flutter`, `mobile_scanner`, `flutter_contacts`, `share_plus`, `shared_preferences`, `google_sign_in`, `sign_in_with_apple` |

## Project structure

```
lib/
├── main.dart                 # Firebase init, controller registration, GetMaterialApp
├── app/routes/               # AppRoutes (names) + AppPages (route table)
├── controllers/              # Business logic (one per domain)
│   ├── auth_controller.dart
│   ├── profile_controller.dart
│   ├── friend_controller.dart
│   ├── group_controller.dart
│   ├── expense_controller.dart   # balance maths, payments, settle-up
│   ├── notification_controller.dart
│   └── shell_controller.dart     # bottom-nav tab state + AppNav helpers
├── core/                     # Design system — import 'core/ui.dart'
│   ├── app_colors.dart, app_theme.dart (spacing, radius, shadows, motion)
│   ├── formatters.dart (money, dates), categories.dart, feedback.dart (toasts)
│   └── widgets/ (buttons, cards, inputs, states, dialogs, illustrations…)
└── modules/                  # Screens
    ├── main_layout.dart      # App shell: fixed bottom bar + IndexedStack tabs
    ├── widgets/expense_tile.dart
    └── *_screen.dart
```

## Data model (Firestore)

- `users/{uid}` – public profile: `name`, `nameLowercase`, `email`, `avatarUrl`,
  `currencyCode`, `notificationsEnabled`, `createdAt`.
  - `private/contact` – owner-only (`phone`).
  - `friends/{friendUid}` – friend preview.
  - `friendRequests/{senderUid}` – incoming requests.
  - `notifications/{id}` – inbox (`fromUid` must be the sender).
- `groups/{id}` – `name`, `icon` (group type), `members[]`, `memberDetails[]`,
  `currencyCode`, `createdBy`, `createdAt`, `lastActive`.
- `expenses/{id}` – `type` (`expense` | `payment`), `amount`, `currencyCode`,
  `paidBy{uid,name}`, `individualSplits{uid: owed}`, `involvedUsers[]`,
  `participantNames`, `splitType`, `settledPairs[]`, `isSettled`, `createdBy`,
  `groupId?`, `receiptUrl?`.

**Balance rule:** every participant's split is owed to the payer unless that
pair is in `settledPairs`. A payment is stored as an expense paid by the sender
with the receiver's split equal to the amount, so it nets the debt down.

## Setup

The Firebase config files are **not** in this repository (they contain the
project's API keys). Generate your own before the first run:

```bash
dart pub global activate flutterfire_cli
flutterfire configure        # creates lib/firebase_options.dart and
                             # android/app/google-services.json
flutter pub get
flutter run
```

These files are listed in `.gitignore` — never commit them.

### Deploy Firebase rules and indexes (required)

The app relies on the security rules and composite indexes in this repo:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

To use Google / Apple sign-in, enable those providers in the Firebase console
(Apple on Android/web also needs the Apple provider's service ID configured).

### Tests

```bash
flutter analyze
flutter test
```
