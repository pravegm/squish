# App Store Connect in one command

`asc.swift` pushes the whole Squish listing to App Store Connect from `docs/appstore/asc-metadata.json`. You do two things by hand: create an API key, and create the app record. The tool does the rest, and it's safe to run again: it changes only what differs.

You need a Mac with Xcode 27.1. There's nothing to install.

## 1. Create the app record (2 minutes, once)

Apple's API can't create apps, so do this in the browser.

1. Go to [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**.
2. Fill in the form:
   - **Platform:** iOS
   - **Name:** `Squish: Fold-to-Crush Press`
   - **Primary language:** English (UK)
   - **Bundle ID:** `com.pravegm.squish`
   - **SKU:** anything, for example `squish`
   - **User access:** Full
3. If the bundle ID isn't in the list, open the project in Xcode once with automatic signing and your team selected. Xcode registers the ID, with Game Center switched on.

## 2. Create an API key (1 minute, once)

1. In App Store Connect, go to **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → **+**.
2. Name the key `squish-asc` and give it the **App Manager** role. App Manager can edit metadata, pricing, Game Center and screenshots.
3. Click **Download** to get `AuthKey_XXXXXXXXXX.p8`. Apple lets you download it **once only**.
4. Note the **Key ID** (shown in the key's row) and the **Issuer ID** (shown above the table).
5. Move the key somewhere private:

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_*.p8 ~/.appstoreconnect/private_keys/
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_*.p8
```

**Keep the key secret.** Never commit it, paste it in chat, or put it in the repo. The repo is public.

## 3. Run it (2 minutes)

From the repo root:

```bash
export ASC_KEY_ID=XXXXXXXXXX        # the Key ID
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# ASC_KEY_PATH defaults to ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8

xcrun swift tools/appstore/asc.swift check   # auth, app found, which version is editable. Changes nothing.
xcrun swift tools/appstore/asc.swift plan    # dry run: prints every change it would make
xcrun swift tools/appstore/asc.swift push    # does it
```

What each command does:

- **`validate`** works offline and needs no key. It checks the metadata file, the badge images and the screenshots.
- **`plan`** and **`push`** print one block per step:
  - `+` creates something
  - `~` updates a field, showing the old value → the new value
  - `-` deletes something (only screenshots or a badge being replaced)
  - `=` means already up to date
- **`push` resumes.** If anything fails (for example, an image is still processing), run `push` again.
- **One part at a time:** `push --only gamecenter,price`, or `push --skip screenshots`.
  - Steps: `appinfo categories agerating version localizations review gamecenter screenshots price accessibility`.
- **Screenshots.** The metadata lists the frames by their path inside a downloaded "App Store screenshots" run, for example `store-69/store/P1-duck-mid.png`. Download a green run first and point the tool at it:

  ```bash
  gh run download <run-id> -R pravegm/squish -D ~/squish-store
  export ASC_SCREENSHOTS_DIR=~/squish-store
  xcrun swift tools/appstore/asc.swift push      # uploads the frames listed in the metadata, in order
  ```

  Without `ASC_SCREENSHOTS_DIR`, the screenshot step is skipped and everything else still goes up.

  Or skip the list: `upload-screenshots ~/squish-store` takes every frame inside a `store/` folder, never `verify/`. It sorts each frame into its set by pixel size and refuses a set whose `MANIFEST.txt` doesn't say `missing: 0  flagged: 0`.

## What the tool pushes

| Step | What |
|---|---|
| `appinfo` | Name, subtitle and privacy policy URL for each locale (en-GB, en-US). Also the app's primary language |
| `categories` | Games (Casual, Simulation) as primary, Entertainment as secondary |
| `agerating` | The age rating questionnaire answers (target 9+) |
| `version` | Version 1.0: copyright (`2026 <legal name>`), release type **Scheduled**, earliest release 24 Nov 2026 08:00 UTC |
| `localizations` | Description, keywords, promotional text, support URL and marketing URL |
| `review` | App Review notes, "no demo account", and the contact name, phone and email |
| `gamecenter` | Enables Game Center for the app and for version 1.0. Creates the 10 achievements, their text in en-GB and en-US, and a badge for each locale |
| `screenshots` | 6.9" and 6.1" sets in order, plus the iPhone Duo inner and outer sets once Apple's API offers them for your app (`check` tells you) |
| `price` | £2.99 with the UK as base territory. Apple equalises the other countries. If the API refuses, the tool prints the exact clicks instead |
| `accessibility` | Accessibility Nutrition Labels, only if the metadata has an `accessibility` block (see below) |

**Fields only you can fill.** Set these in `asc-metadata.json` and run `push` again:

- `review.contact`: phone and email;
- `copyrightHolder`: your legal name or studio name.

Until you do, the tool skips just those fields and says so. Everything else still goes up. URLs that still contain `[domain]` are skipped the same way.

## Still by hand in App Store Connect, and why

- **The app record** (step 1). Apple doesn't allow creating apps through the API.
- **App Privacy** → "Data Not Collected" → Publish. There is no public API for the privacy questionnaire.
- **Agreements, Tax and Banking.** Under **Business**, the Paid Apps agreement, tax forms and bank account must all be Active before a paid app can sell. These are legal forms that only the account holder can sign.
- **Small Business Program** (15% commission). You enrol on developer.apple.com, not in App Store Connect, and it isn't an API.
- **Availability and pre-order.** Under **Pricing and Availability**, choose all countries, plus a pre-order if you want one. The tool sets the price only.
- **Family Sharing**: App Information → on. It's permanent once you turn it on.
- **Accessibility Nutrition Labels.** The API supports them, but declare only what passes Apple's criteria on the final build. Either tick them in App Store Connect, or add a block like this to the metadata (`"publish": true` makes them public):
  ```json
  "accessibility": {"deviceFamily": "IPHONE", "supportsVoiceover": true, "supportsReducedMotion": true, "supportsSufficientContrast": true, "publish": false}
  ```
- **The build.** In Xcode, use Product → Archive → Distribute. Then pick the build on the 1.0 page and click **Add for Review**.
- **iPhone Duo screenshots**, only if `check` says "iPhone Duo: none offered". In that case, upload them in the browser when the slot appears. A metadata edit doesn't need a new build.

## Or let GitHub run it (no Mac needed)

Store the key as repository secrets. Only GitHub Actions can read them; they never appear in logs.

1. In GitHub, go to **pravegm/squish** → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.
2. Add three secrets:
   - `ASC_KEY_ID`: the Key ID
   - `ASC_ISSUER_ID`: the Issuer ID
   - `ASC_PRIVATE_KEY`: the whole contents of the `.p8` file, from `-----BEGIN PRIVATE KEY-----` to `-----END PRIVATE KEY-----`
3. Go to **Actions** → **App Store Connect tool** → **Run workflow**. Tick **push**. Optionally:
   - give a step list, for example `gamecenter`;
   - give the ID of a green "App Store screenshots" run, to upload its frames.

The workflow then runs `check`, `plan` and `push`, and deletes the key file at the end. Without the secrets, or without **push** ticked, it never touches App Store Connect.

Every push to `tools/appstore/` or `asc-metadata.json` typechecks the tool and validates the metadata. It also renders the badges into the run's `badges` artifact. A preview of all ten is in `tools/appstore/badges/preview.png`.

## Files

- `asc.swift`: the tool. It uses only Foundation and CryptoKit. It signs an ES256 token from the `.p8` key; the key never leaves your Mac.
- `badges.swift`: renders the 10 achievement badges (1024 × 1024, opaque sRGB). Run it with `xcrun swift tools/appstore/badges.swift`. It fails if the IDs differ from the app's `Achievement.gameCenterID` or from `docs/appstore/achievements.md`.
- `badges/`: the rendered badges, named `<achievement ID>.png`.
- `fixtures/asc-metadata.sample.json`: a CI test fixture. The real data is `docs/appstore/asc-metadata.json`.
