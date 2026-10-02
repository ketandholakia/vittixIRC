# Publishing VIRC (Vittix IRC) on F-Droid

Status of this repository's F-Droid readiness and the exact steps from here to a
merged submission. This file complements `fdroid/fdroiddata/` (the build recipe).

## What is already done

- [x] **License** — GPL-3.0-or-later; `LICENSE` file at the repo root.
- [x] **Application ID** — `io.github.ketandholakia.virc` (namespace, Kotlin
      packages and fdroiddata metadata file renamed).
- [x] **FOSS dependency check** — all Dart/Flutter and Android dependencies are
      free software. No Firebase, no Google Play services, no ads, no tracking.
      → No `AntiFeatures` needed in the metadata.
- [x] **Portable Gradle config** — the machine-specific `org.gradle.java.home`
      entry was removed from `android/gradle.properties` (it now lives in the
      local machine config `~/.gradle/gradle.properties`) so the source builds
      on F-Droid's Linux build machines.
- [x] **Fastlane metadata** added at `fastlane/metadata/android/en-US/`
      (title, short description, full description, changelog for versionCode 1).
      This is read by F-Droid automatically from the tagged commit.
- [x] **Branding** — VIRC branding pack integrated: launcher icons (all
      densities), Android adaptive icon (incl. the Android 13 monochrome layer),
      native launch splash (light/dark), fastlane listing icon, and app naming.
- [x] **Build recipe** at `fdroid/fdroiddata/io.github.ketandholakia.virc.yml`.
- [x] **Workspace/agent files excluded from git** — they must not become public
      when the repository is pushed (AGENTS.md, SOUL.md, USER.md, IDENTITY.md,
      HEARTBEAT.md, TOOLS.md, todo.md, `.agents/`, `.openclaw/`, `.openclaw-attachments/`).

## Decisions (resolved)

1. **License:** GPL-3.0-or-later — `LICENSE` added at the repo root.
2. **Application ID:** `io.github.ketandholakia.virc` — applied everywhere
   (namespace, Kotlin package, fdroiddata metadata file name).
3. **Repository:** `https://github.com/ketandholakia/vittixIRC` · author credit:
   Ketan Dholakia.

## Step 1 — Publish the source repository

```powershell
# from the project directory (D:\ketan\github\vittixIRC)
git config user.name  "Ketan Dholakia"     # identity for public commits
git config user.email "ketandholakia@users.noreply.github.com"

git remote add origin https://github.com/ketandholakia/vittixIRC.git
git checkout main
git merge fix/all-issues                   # brings in the release prep commits
git push -u origin main

# F-Droid requires a tag for every release commit:
git tag -a v1.0.0 -m "VIRC 1.0.0"
git push origin v1.0.0
```

The README clone URL is already updated to the real repository.

## Step 2 — Submit to fdroiddata (merge request)

App data for F-Droid lives in <https://gitlab.com/fdroid/fdroiddata>. The
fastest route is a merge request containing a working build recipe — we
already have one, so no RFP is needed.

1. Create a free account on gitlab.com and fork `fdroid/fdroiddata`.
2. Locally:

```bash
git clone https://gitlab.com/<your-gitlab-user>/fdroiddata.git
cd fdroiddata
git checkout -b io.github.ketandholakia.virc
cp /path/to/vittixIRC/fdroid/fdroiddata/io.github.ketandholakia.virc.yml \
   metadata/io.github.ketandholakia.virc.yml
# no placeholders left in the recipe; just confirm `commit: v1.0.0` matches
# the pushed tag, then:
git add metadata/io.github.ketandholakia.virc.yml
git commit -m "New app: VIRC"
git push -u origin io.github.ketandholakia.virc
```

3. Open the merge request (target branch: `master` of `fdroid/fdroiddata`).
   The CI pipeline automatically runs a build from your recipe (this is the
   real test — a full Flutter build on their build machines takes a while).
   If it fails, check the log; for Flutter apps the usual fixes are adjusting
   the pinned `srclibs: flutter@<version>` or adding `sudo:` packages.
   Push updates to the branch to re-run CI.
4. Answer reviewer questions. Once merged, the app is built, signed with
   F-Droid's key and published (index updates within roughly a day).

Optional (local sanity checks, requires fdroidserver):
`fdroid lint io.github.ketandholakia.virc` and
`fdroid rewritemeta io.github.ketandholakia.virc`.

Alternative: file a request for packaging at <https://gitlab.com/fdroid/rfp>
(slower — a volunteer packager would write the recipe; we already have one).

## Step 3 — Ongoing releases

`UpdateCheckMode: Tags` + `AutoUpdateMode: Version` means F-Droid notices new
tags and opens the update MR automatically. Per release:

1. bump the version in `pubspec.yaml` (e.g. `1.0.1+2`),
2. commit, `git tag v1.0.1`, `git push origin v1.0.1`.

Optionally add `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt`
(with the new versionCode) so the "what's new" text ships with the release.

## Later / optional polish

- **Screenshots** — add `fastlane/metadata/android/en-US/images/phoneScreenshots/`.
  Capture from a device/emulator (portrait, ideally 1080×1920+).
- **In-app logo** — the wordmark/icon assets are bundled under `assets/branding/`
  and can be shown in-app (e.g. empty states or an about screen).
- **Reproducible builds** — publish your own signed release APK; if F-Droid can
  rebuild it bit-for-bit, users get stronger guarantees. Read
  <https://f-droid.org/en/docs/Reproducible_Builds/> before the second release.
- **Your own signing key** — generate an upload keystore if you also plan to
  distribute APKs yourself. Never commit it (`*.jks`/`*.keystore` are already
  gitignored).
- **IzzyOnDroid** (<https://apt.izzysoft.de/fdroid/>) can be used in parallel
  and also picks up fastlane metadata.

## Useful links

- Inclusion policy: <https://f-droid.org/en/docs/Inclusion_Policy/>
- Quick start guide: <https://f-droid.org/en/docs/Submitting_to_F-Droid_Quick_Start_Guide/>
- Build metadata reference: <https://f-droid.org/en/docs/Build_Metadata_Reference/>
- Repository style guide: <https://f-droid.org/en/docs/Repository_Style_Guide/>
- Reproducible builds: <https://f-droid.org/en/docs/Reproducible_Builds/>
