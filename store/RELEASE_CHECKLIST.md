# CreditCardAPR — Release Checklist
**Version:** 1.0.0+1  
**AAB:** build/app/outputs/bundle/release/app-release.aab (45.7 MB)  
**Date:** April 30, 2026

---

## ① AdMob Console — Create Ad Units

Publisher ID: `ca-app-pub-5379540026739666`  
App: **CreditCardAPR** (Android)

Create 3 ad units — replace XXXXXXXXXX in `lib/core/ads/ad_config.dart`:

| Type | Getter | Replace |
|------|--------|---------|
| Banner | `bannerAndroid` | `ca-app-pub-5379540026739666/XXXXXXXXXX` |
| Interstitial | `interstitialAndroid` | `ca-app-pub-5379540026739666/XXXXXXXXXX` |
| Rewarded Video | `rewardedAndroid` | `ca-app-pub-5379540026739666/XXXXXXXXXX` |

Also update App ID in `AndroidManifest.xml`:
```xml
android:value="ca-app-pub-5379540026739666~XXXXXXXXXX"
```

After replacing IDs → rebuild AAB: `flutter build appbundle --obfuscate --split-debug-info=build/debug_info/`

---

## ② Play Console — IAP Product

1. Go to Play Console → CreditCardAPR → Monetize → In-app products
2. Create product:
   - **Product ID:** `premium_upgrade`
   - **Name:** Premium Upgrade
   - **Description:** Unlimited saves, no ads, PDF export, full history
   - **Price:** $2.99 (one-time)
   - **Status:** Active ✅

---

## ③ Privacy Policy Hosting

Host `store/privacy/index.html` at:  
`https://abassimaj.github.io/creditcardapr-privacy/`

Steps:
1. Create GitHub repo: `creditcardapr-privacy`
2. Upload `index.html` to root
3. Enable GitHub Pages (Settings → Pages → main branch)

---

## ④ Play Console Listing

| Locale | Source |
|--------|--------|
| English (US) | `store/en-US/listing.txt` |
| Spanish (US) | `store/es-US/listing.txt` |

- Privacy Policy URL: `https://abassimaj.github.io/creditcardapr-privacy/`
- Category: Finance
- Content rating: Everyone
- Contact email: abassimaj@gmail.com

---

## ⑤ Pre-Release Final Checks

- [ ] Real AdMob IDs in `ad_config.dart` (both files)
- [ ] Real AdMob App ID in `AndroidManifest.xml`
- [ ] `premium_upgrade` IAP product Active in Play Console
- [ ] Privacy policy hosted at GitHub Pages URL
- [ ] AAB rebuilt after ID replacement
- [ ] Debug banner not visible (`debugShowCheckedModeBanner: false` ✅)
- [ ] `kDebugMode` flags not in release path
- [ ] flutter test → 28/28 ✅
- [ ] flutter analyze → 0 errors ✅

---

## ⑥ Security Audit Status (OWASP)

| Risk | Status |
|------|--------|
| M1 Hardcoded secrets | ✅ Test IDs only — replace before release |
| M5 Network security | ✅ network_security_config.xml — HTTP blocked |
| M7 Binary protection | ✅ --obfuscate + --split-debug-info |
| M9 Insecure storage | ✅ allowBackup=false |

---

## ⑦ Monetization Config (Final)

| Setting | Value |
|---------|-------|
| Rewarded cap/day | 3 |
| Rewarded duration | 60 min |
| Interstitial threshold | 8 calcs |
| Interstitial cooldown | 5 min |
| Review trigger | 3rd save |
| Review cooldown | 90 days |
| Premium price | $2.99 (one-time) |
| Free history limit | 100 saves |
