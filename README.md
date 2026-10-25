# Anuj Properties — website

Lead-generation website for **Anuj Properties**, real estate consultant in Parsvnath City, Sector 8, Sonipat (since 1998).
Static HTML/CSS/JS built by a small PowerShell builder — no Node, no framework, no server.

- Live: https://zeus-shourya.github.io/anuj-properties/
- Calls / WhatsApp: +91 98134 41130 (set in `src/site.json`)

## Layout

```
src/
  site.json        business details (name, address, phone, hours, Google IDs), baseUrl, ga4Id, formEndpoint
  partials/        layout, header, footer, enquiry form, mobile action bar, CTA band, SVG icons
  pages/           one file per page: <!--page {json front matter} --> + body
  data/            reviews.json (Google reviews), listings.json (empty = no listings page)
  assets/          css, js, images (photos are the business's own Google Business Profile uploads)
tools/
  build.ps1        builds docs/ — pages, sitemap.xml, robots.txt, JSON-LD, audit + link check
  images.ps1       crops/resizes photos to JPEG + WebP
  brand.ps1        logo, favicon.ico, app icons
  og.ps1           social share image per page (re-run after changing an H1)
docs/              THE PUBLISHED SITE (generated — never edit by hand)
serve.ps1          local preview server
```

## Everyday use

```powershell
powershell -ExecutionPolicy Bypass -File tools\build.ps1      # rebuild docs\ (exits non-zero on any issue)
powershell -ExecutionPolicy Bypass -File serve.ps1            # preview at http://localhost:4381/
git add -A; git commit -m "Update"; git push                  # GitHub Pages redeploys in ~1 minute
```

Preview through `serve.ps1` (or the live URL). Opening the HTML files directly in an app preview shows
a static snapshot where photos and page links don't work.

**Edit text:** change the page in `src/pages/`, rebuild. **Phone, address, hours, rating:** `src/site.json`, rebuild.
**Add listings:** add entries to `src/data/listings.json` (id, title, purpose, type, locality, size, price,
features, photo, status) — the build then creates `/properties/` and adds it to the footer and sitemap.

## Hosting & custom domain

GitHub Pages serves the `docs/` folder of `main`. To move to the client's own domain:

1. In `src/site.json` set `"baseUrl": "https://www.example.com/"` and `"customDomain": "www.example.com"`.
2. Rebuild (writes `docs/CNAME`, updates canonical URLs, sitemap, structured data), commit, push.
3. At the domain registrar add a `CNAME` record `www` → `zeus-shourya.github.io` (and for the bare domain,
   A records 185.199.108.153 / .109.153 / .110.153 / .111.153).
4. In the repo's Settings → Pages, confirm the domain and tick **Enforce HTTPS**.
   The github.io address then redirects to the new domain automatically.

## Optional integrations (both off by default)

- **Google Analytics 4:** put the Measurement ID (`G-XXXXXXX`) in `ga4Id`, rebuild. The privacy policy updates
  itself. Events sent: `generate_lead` (form), `click_to_call`, `whatsapp_click`, `get_directions`, `map_load`.
  Mark `generate_lead`, `click_to_call` and `whatsapp_click` as key events in GA4.
- **Email copy of form enquiries:** create a free Web3Forms key (or a Formspree form) with the client's email;
  set `formEndpoint` (e.g. `https://api.web3forms.com/submit`) and `formAccessKey`, rebuild. The WhatsApp
  hand-off keeps working alongside it.

## Search Console (once the final domain is live)

1. Add a **Domain** property for the custom domain (DNS TXT verification).
2. Submit `https://<domain>/sitemap.xml`.
3. Use URL Inspection on the home page and the two area pages to request indexing.
4. Note: on `zeus-shourya.github.io/anuj-properties/` robots.txt is not at the host root, so it is ignored by
   crawlers until the custom domain is set; per-page meta robots is in place either way.

## Google Business Profile (the biggest lead source for a local dealer)

- Add the phone number (the profile has none) and change "Website" to the site URL — it currently points to a
  WhatsApp link missing the 91 country code.
- Keep name, address and hours exactly as on the site. Post updates/photos regularly and ask happy clients
  for reviews (link: footer "Write a review").

## Pending client confirmation

- The note on the Parsvnath City page and in the document guide about the developer's insolvency (NCLT, 30 April 2026).
- HRERA agent registration number, if any (must be quoted when facilitating sales in registered projects).
- Brokerage / fee policy, owner's full name, business email.

## Testing checklist

- [ ] PageSpeed Insights (mobile) on home, a service page and a guide — LCP < 2.5 s, CLS < 0.1, INP < 200 ms
- [ ] Google Rich Results Test on home (RealEstateAgent, FAQ) and a guide (Article, BreadcrumbList)
- [ ] Mobile: menu, Call / WhatsApp / Enquire bar, form validation and WhatsApp hand-off on a real phone
- [ ] Share a page link on WhatsApp and check the preview image
- [ ] Search Console: sitemap processed, pages indexed, no mobile usability or HTTPS issues
- [ ] GA4 (if enabled): key events arriving from a test call/WhatsApp tap and a test enquiry
