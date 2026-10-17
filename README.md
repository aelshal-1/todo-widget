# Todo — iPhone to-do app with a home-screen widget

- Widget in 3 sizes. Tick tasks off right on the widget.
- Add tasks by typing or by voice (Arabic or English). Claude picks out the date and time.
- The due chip turns amber within 24 h, red within 2 h, and solid red when overdue.
- Notifications 30 minutes before and at the due time. Appointments can go to Calendar.
- PDF report you can save to Files.

## How it's built

There's no Mac involved. GitHub Actions builds an unsigned `Todo.ipa` on every push and attaches it to the latest Release:

`https://github.com/aelshal-1/todo-widget/releases/latest/download/Todo.ipa`

You install it with **SideStore** or **Sideloadly** using a free Apple ID. The install expires after 7 days. Refresh it in SideStore, or re-install it with Sideloadly. Your tasks are kept.

## Setup in the app

Settings (gear icon) → paste your Claude API key from console.anthropic.com → **Test**.
The key is kept only in the iPhone Keychain. It never goes in this repository.
