# Lockin

An iPhone app that plans your work for you and keeps you off social media while you do it.

1. **Add a task** - title, difficulty, how long it takes, deadline.
2. **Lockin fills your calendar** - focus blocks are placed in your free hours before each deadline.
3. **You get a notification** when a block is about to start, when it starts and when it ends.
4. **Social media is blocked** while a block runs: opening a blocked app sends you straight back to Lockin.

## What it does beyond the basic idea

- **Splits big tasks into focus blocks** (45 min by default) with breaks in between, spread over several days.
- **Plans around your free hours** - set them per weekday in the *Me* tab.
- **Hard tasks get extra time** (+25%), go first in the day and get a longer break.
- **Workload at a glance** - the Today tab shows how many hours are left in total, today's plan and the next 7 days.
- **Deadline warnings** - if a task cannot be finished in time with your free hours, it is flagged *At risk*.
- **Missed a block? It is planned again automatically.** After each block you check in with one tap (also from the notification).
- **Move, skip or start early** - tap any block in the calendar. Moved blocks are pinned.
- **Strict mode** - ending a session early needs an 8 second hold.
- **Streak and stats** - focus time, sessions and how many distractions were blocked.
- **Morning summary** notification with the day's plan.

## Get the app onto your iPhone (no Mac needed)

1. Put this folder in a GitHub repository (it must be the top level of the repository).
2. GitHub builds the app automatically: open the repository's **Actions** tab, wait for the *Build IPA* run to go green.
3. Open the finished run, download **Lockin-ipa** under *Artifacts* and unzip it. You get `Lockin.ipa`.
4. Open **Sideloadly**, plug in your iPhone, drag in `Lockin.ipa`, enter your Apple ID and press Start.
5. On the iPhone: *Settings > General > VPN & Device Management* - trust your Apple ID. On iOS 16 and later also switch on *Settings > Privacy & Security > Developer Mode*.

With a free Apple ID the app stops opening after 7 days. Sideload the same `.ipa` again to renew it - your tasks stay as long as you do not delete the app first.

If you have a Mac instead: `brew install xcodegen`, run `xcodegen generate` in this folder and open `Lockin.xcodeproj`.

## Set up the blocking (once, about 2 minutes)

Lockin blocks apps through an automation in Apple's Shortcuts app. The same steps are inside the app under *Me > Set up social media blocking*.

1. Shortcuts app > **Automation** > **+**.
2. Choose **App**, pick the apps to block (Instagram, TikTok, Snapchat, YouTube ...), tick **Is Opened**, choose **Run Immediately**.
3. **New Blank Automation** > add the action **Focus Minutes Left** (search for "Lockin").
4. Add **If**: *Focus Minutes Left* - *is greater than* - *0*.
5. Inside the If, add **Show Lockin Shield**. Leave *Otherwise* empty.
6. Done. Start a focus session and open a blocked app to test it.

### Why not real Screen Time blocking?

Apple's system-level app blocking (the Family Controls / Screen Time API) only works for apps signed with a paid Apple Developer account that has the Family Controls permission. Sideloadly with a free Apple ID cannot provide it, so that code would simply not run. The Shortcuts automation works on every iPhone with iOS 16 or later. Its limit: you can switch the automation off in Shortcuts yourself.

## For developers

```
Lockin/Core       data model, scheduler, persistence (plain Swift, no UI)
Lockin/App        app entry point and the data store
Lockin/Services   notifications and the Shortcuts actions
Lockin/Views      SwiftUI screens
Tests             unit tests for the scheduler
```

The planning logic is tested on its own:

```bash
swift test
```
