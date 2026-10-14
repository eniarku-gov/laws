# Hosting the laws at `laws.eniarku.org`

A complete setup guide: new GitHub repo, GitHub Pages, DNS at Squarespace Domains, the GitHub Actions build, and day-to-day use. Your existing Jekyll site (`eniarku.org`) is not touched.

Throughout this guide the GitHub account is **`eniarku-gov`**; it becomes `eniarku-gov.github.io` in DNS. The new repo is `eniarku-gov/laws`.

---

## 0. The plan in one picture

```
eniarku.org          -> existing Jekyll repo        (unchanged)
laws.eniarku.org     -> NEW repo "laws"
   /                 -> landing page (landing/)
   /ecl/             -> Compiled Law book           (ecl/_book)
   /resolutions/     -> Council Resolutions book    (resolutions/_book)
```

GitHub Pages publishes one site per repository, and each repository can have its own custom domain. So the laws get their own repo and their own subdomain, and the two sites deploy independently.

The History links between the two books are relative paths (`../../resolutions/...`), so **both books must live in this one repo**, mounted side by side as above.

---

## 1. Before you start

**Accounts and tools**

| Need | Notes |
|---|---|
| GitHub account `eniarku-gov` | The new repo (`laws`) goes here. |
| Squarespace Domains access | You'll add DNS records for `eniarku.org`. |
| R + the `yaml` package | `install.packages("yaml")` |
| Quarto 1.6.x | The workflow pins 1.6.40, the version this was tested with. |
| Python 3 | Used by the build script's link checker and local server. |
| Ruby / Jekyll | **Not needed** in the new repo. |

**Two decisions to make now**

1. **Public or private repo?** On a private repo, GitHub Pages generally requires a paid GitHub plan. A public repo also exposes your CR source files, which is probably fine for published law.
2. **Where the laws permanently live.** People will cite and bookmark these URLs. `laws.eniarku.org` is a good permanent home; moving later would break every link unless you add redirects.

---

## 2. Folder and repo structure

The `laws-site/` folder delivered alongside this guide is the starting skeleton. Its contents become the root of the new repo:

```
laws/                               <- repo root
├── .github/
│   ├── workflows/pages.yml         <- build + deploy (GitHub Actions)
│   └── dependabot.yml              <- keeps Action versions current
├── .gitignore
├── build-local.sh                  <- the whole build; used locally AND by the workflow
├── landing/
│   ├── index.html                  <- laws.eniarku.org/
│   └── 404.html
├── ecl/                            <- Compiled Law book (mostly generated)
│   ├── _quarto.yml
│   ├── index.qmd
│   ├── generate.R
│   ├── latest-section.lua
│   ├── list-detect.lua
│   ├── act-breadcrumb.html
│   ├── law.css
│   ├── titles.yml                  <- Title number -> Title name (you edit this)
│   ├── images/coat-of-arms.png     <- YOU add this
│   ├── _chapters.yml               <- generated (git-ignored)
│   └── title1/, title2/, ...       <- generated (git-ignored)
└── resolutions/                    <- your existing CR book, moved in as-is
    ├── _quarto.yml
    ├── index.qmd
    ├── _res-head.qmd
    └── 2026/26CR1.qmd, ...
```

**What you supply**

- `ecl/images/coat-of-arms.png`: your image (a different name works if you update `COAT_OF_ARMS` in `act-breadcrumb.html` and the `resources:` entry in `ecl/_quarto.yml`).
- `resolutions/`: your existing book. List every CR that should be linkable from a History line as a **chapter** in `resolutions/_quarto.yml`; a CR that isn't a chapter has no page to link to.
- `ecl/titles.yml`: replace the sample names with your real Titles (`1: General Provisions`, ...).

**Settings worth reviewing**

| File | Setting |
|---|---|
| `ecl/generate.R` (top) | `cr_base` (path from an Act page to the resolutions book; leave as `../../resolutions` unless you change the mount points), `title_sep`, `enactment_clause` |
| `ecl/act-breadcrumb.html` (top) | `COAT_OF_ARMS` path |
| `build-local.sh` (top) | `SITE_TZ`, the time zone used to decide what "today" is (set to `America/New_York`) |
| `.github/workflows/pages.yml` | The cron time |
| `landing/index.html` | Page text; a commented-out card shows where to add future collections |

---

## 3. Create the repo and test locally

1. **Create the repo** on GitHub (named `laws`, under `eniarku-gov`). Don't add a README or license yet if you plan to push an existing folder.
2. **Assemble the folder** on your computer: copy the contents of `laws-site/` into a new folder, then add your `resolutions/` book and your `coat-of-arms.png`.
3. **Run the full build locally** from the repo root:

   ```bash
   bash build-local.sh --serve
   ```

   This runs `generate.R`, renders both books, assembles `_site/`, checks every internal link and image, and serves the result at <http://localhost:4000>. Preview a future date with:

   ```bash
   COMPILE_AS_OF=2026-12-31 bash build-local.sh --serve
   ```

4. **Look at it.** Check the landing page; an Act page (breadcrumb, coat of arms, Title name in the sidebar, History links); and follow a History link into the resolutions book.
5. **Fix anything the generator reports.** `ERROR` lines stop the build before anything is written; `WARNING` lines are worth reading.
6. **Commit and push to `main`:**

   ```bash
   git init -b main
   git add .
   git commit -m "Initial laws site"
   git remote add origin https://github.com/eniarku-gov/laws.git
   git push -u origin main
   ```

   The first workflow run will build but not deploy until you finish section 4.

---

## 4. GitHub Pages setup

Do these in order. The order matters for security: verify the domain *before* pointing DNS at GitHub, so nobody else can claim `laws.eniarku.org` in the gap.

### 4.1 Turn on Pages with GitHub Actions

Repo → **Settings → Pages → Build and deployment → Source: GitHub Actions**.

### 4.2 Verify `eniarku.org` (recommended)

Verification stops other GitHub users from publishing to your domain or its immediate subdomains.

1. Open the **Pages** settings for the account or org that owns the repo (user: profile photo → Settings → Pages; org: the org's Settings → Pages).
2. Click **Add a domain**, enter `eniarku.org`.
3. GitHub shows a **TXT record** to create, with the name `_github-pages-challenge-eniarku-gov` and a value. Leave this page open and do section 5.1, then come back and click **Verify**.
4. Keep the TXT record in DNS permanently, or the domain stops being verified.

If `eniarku.org` is already listed as verified for this account, skip this step.

### 4.3 Set the custom domain

After the DNS records from section 5 exist: repo → **Settings → Pages → Custom domain** → enter `laws.eniarku.org` → **Save**. GitHub runs a DNS check. With Actions-based deploys no `CNAME` file is needed in the repo; the setting is stored in the repo's Pages settings.

### 4.4 Enforce HTTPS

When the DNS check passes, GitHub provisions a certificate. This usually takes minutes to an hour, occasionally longer. When the **Enforce HTTPS** checkbox becomes available, tick it.

---

## 5. DNS at Squarespace Domains

You'll add two records to `eniarku.org`'s DNS. **Don't change or delete any existing record**: the ones that point `eniarku.org` at your Jekyll site stay as they are.

**To open the DNS editor:** Squarespace → **Domains** → select `eniarku.org` → **DNS → DNS Settings** → scroll to **Custom Records** → **Add Record**. (Menu labels shift occasionally; look for "DNS Settings" and "Custom records".)

> This only works if the domain uses Squarespace's nameservers. If its nameservers point elsewhere, add the records at that DNS provider instead; the values are identical.

### 5.1 The verification record (TXT)

| Field | Value |
|---|---|
| Type | `TXT` |
| Host | `_github-pages-challenge-eniarku-gov` |
| Data | the value GitHub shows you in step 4.2 |
| TTL | default |

Enter only the host part; Squarespace appends `.eniarku.org`. Save, then click **Verify** on GitHub (retry after a few minutes if needed).

### 5.2 The subdomain record (CNAME)

| Field | Value |
|---|---|
| Type | `CNAME` |
| Host | `laws` |
| Data | `eniarku-gov.github.io` |
| TTL | default |

Two common mistakes: including the repo name in the target (it must be just `eniarku-gov.github.io`) and typing the full `laws.eniarku.org` as the host (it must be just `laws`). There must not already be another record for the host `laws`.

### 5.3 Check that it propagated

```bash
dig laws.eniarku.org CNAME +short
# expect: eniarku-gov.github.io.

dig _github-pages-challenge-eniarku-gov.eniarku.org TXT +short
```

On Windows: `nslookup -type=CNAME laws.eniarku.org`. A web checker such as dnschecker.org also works. Changes usually appear within minutes but can take up to 24 hours.

Then do 4.3 and 4.4.

---

## 6. GitHub Actions: what the workflow does

`.github/workflows/pages.yml` runs on three triggers:

| Trigger | Why |
|---|---|
| Push to `main` | Publishes your changes. |
| Daily schedule (05:15 UTC) | CRs with a future effective date go live on that date; the generator decides "in effect" at build time. |
| Manual (**Actions → Build and deploy laws site → Run workflow**) | Rebuild on demand. |

The `build` job:

1. Checks out the repo, then sets up R (and installs `yaml`) and Quarto 1.6.40.
2. Runs `bash build-local.sh --no-jekyll`, which:
   - runs `generate.R` (any `ERROR` **fails the build**, so a bad CR can't publish a half-updated code);
   - renders `ecl/` and `resolutions/`;
   - assembles `_site/` (landing page at the root, books at `/ecl/` and `/resolutions/`);
   - checks internal links and images, and that the coat of arms file exists. This check is **non-fatal**: broken links are printed in the log but don't stop the deploy.
3. Uploads `_site/`, and the `deploy` job publishes it.

Because CI runs the same script you run locally, **what you test locally is what gets deployed.**

**Things to know**

- **Time zone.** "Today" in `generate.R` comes from `SITE_TZ` in `build-local.sh`, which is `America/New_York`. That is Eastern Time, so it follows EST in winter and EDT in summer automatically. If you want a fixed UTC−5 all year (no daylight saving), use `Etc/GMT+5` instead (the sign looks backwards but is correct). Because CI and your local builds run the same script, they always agree. The cron schedule itself is always UTC: 05:15 UTC is 00:15 EST (01:15 during EDT), just after local midnight.
- **Scheduled runs can pause.** On public repos, GitHub disables scheduled workflows after about 60 days with no repository activity. If a future-dated CR doesn't appear, check the Actions tab and re-enable the workflow, or just push a commit.
- **Action versions.** The `dependabot.yml` file opens a pull request when an Action version in `pages.yml` goes out of date. Merge those occasionally.

---

## 7. Day-to-day use

**Publishing a new CR**

1. Write the CR in `resolutions/<year>/`, with `params.dates.assent` (and `effective` if different), `params.title`, `params.enacted_as`, and exactly one of `creates` / `amends` / `regulates` / `repeals` as needed. A CR that creates an Act also needs `params.short_title` and `params.enacted_title`.
2. Add it as a chapter in `resolutions/_quarto.yml`. History entries on the `ecl` side link to that CR's rendered **HTML page**, for example `https://laws.eniarku.org/resolutions/2026/26CR2.html`, built from the CR's file path (`resolutions/2026/26CR2.qmd`). If the CR isn't a chapter, the page doesn't exist and the link check will report it. File-name capitalization matters, because GitHub Pages URLs are case-sensitive.
3. Preview: `bash build-local.sh --serve`.
4. `git add . && git commit -m "26CR12" && git push`.
5. Watch the **Actions** tab. A successful run is live in a few minutes.

**A CR with a future effective date.** Assent it now; it's excluded until its effective date, and the daily rebuild publishes it on that day. Test it ahead of time with `COMPILE_AS_OF=<date>`.

**A new Title.** Add its number and name to `ecl/titles.yml`. Without a name, the generator warns and shows "Title N".

**Replacing the coat of arms.** Overwrite `ecl/images/coat-of-arms.png`, commit and push.

---

## 8. Link the two sites together

In your Jekyll repo, add a link to `https://laws.eniarku.org/` in your navigation or wherever fits. That's the only change the Jekyll site needs. The laws landing page already links back to `eniarku.org`.

---

## 9. Adding more law types later

Orders-in-Council, Letters Patent and Sovereign Proclamations follow the same pattern: a source folder, a book (or a generated section of the compiled book), and a mount point under `_site/` (for example `/oic/`), plus a card on `landing/index.html`. To link their IDs from History lines, the generator will need a registry mapping every source ID to its page URL; that's the planned next step.

---

## 10. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| GitHub says the DNS check is unsuccessful | The CNAME is missing, the target is wrong (must be exactly `eniarku-gov.github.io`), the host was typed as the full domain, or it hasn't propagated yet. Check with `dig`; wait and retry. |
| "Enforce HTTPS" is greyed out | The certificate isn't provisioned yet. Wait (up to a few hours at worst) and make sure the DNS check passes. |
| Site shows a 404 right after deploy | Pages source isn't set to **GitHub Actions** (4.1), or the first deploy hasn't finished; check the Actions tab. |
| Workflow fails at "Build site" | Open the log and read the `ERROR:` lines from `generate.R`: usually a missing `params.enacted_as`, a bad date, or a Title mismatch. |
| Link check lists missing History links | The CR isn't listed as a chapter in `resolutions/_quarto.yml`. |
| An Act shows "Title N" instead of a name | Add the Title to `ecl/titles.yml`. |
| A future-dated CR didn't appear on its date | Scheduled workflow paused for inactivity, or `SITE_TZ` in `build-local.sh` is wrong. Run the workflow manually. |
| Changes don't show up in the browser | Hard-refresh; browsers cache CSS and scripts. |
| Coat of arms missing on Act pages | The image path or `resources:` entry doesn't match. The build script's final check prints "coat of arms file not found". |

---

## 11. Checklist

- [ ] New repo `laws` created under `eniarku-gov`; skeleton, `resolutions/`, and coat of arms added
- [ ] `titles.yml` edited; `SITE_TZ` in `build-local.sh` confirmed
- [ ] `bash build-local.sh --serve` works locally with no errors
- [ ] Pushed to `main`
- [ ] Pages source set to **GitHub Actions**
- [ ] TXT record added at Squarespace; `eniarku.org` verified on GitHub
- [ ] CNAME `laws` → `eniarku-gov.github.io` added at Squarespace
- [ ] Custom domain `laws.eniarku.org` saved; DNS check passes
- [ ] **Enforce HTTPS** ticked
- [ ] Workflow run succeeded; `https://laws.eniarku.org/` loads; a History link works
- [ ] Link to the laws site added in the Jekyll site
