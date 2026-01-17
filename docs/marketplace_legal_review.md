# Marketplace Search Source - Legal Review

## Status: **DEFERRED - NOT RECOMMENDED FOR IMPLEMENTATION**

## Executive Summary

Implementation of marketplace search (Craigslist and Facebook Marketplace) is **deferred** due to significant legal risks and Terms of Service violations. Both platforms explicitly prohibit web scraping, and Craigslist has a history of aggressive legal action against scrapers.

## Legal Analysis

### Craigslist

**Terms of Service:**
- Explicitly forbids scraping: "You agree not to copy/collect CL content via robots, spiders, scripts, scrapers, crawlers, or any automated or manual equivalent."
- Terms last updated: August 16, 2019
- License grants narrow rights and forbids derivative works

**Legal Precedents:**
1. **Craigslist v. 3Taps** - Successful use of contract law (breach of ToS) and CFAA arguments
2. **Craigslist v. Radpad** - Judgment of ~$60 million
3. **Craigslist v. Instamotor** - Settlement of $31 million

**Risk Level:** **VERY HIGH** - Craigslist actively pursues legal action against scrapers.

### Facebook Marketplace

**Terms of Service:**
- Prohibits unauthorized scraping and automated data collection
- Applies to both logged-in users and potentially logged-out visitors (context-dependent)

**Legal Precedents:**
1. **Bright Data v. Meta (2024)** - Court found that scraping public data while logged out may not violate ToS in certain circumstances
   - However, this is case-specific and context-dependent
   - Commercial use increases legal exposure
   - Scraping private/restricted data is clearly prohibited

**Risk Level:** **HIGH** - While recent case law provides some nuance, legal risk remains significant.

## Key Legal Factors

| Factor | Legal Risk |
|--------|------------|
| Scraping public data while logged out | Medium-High (context-dependent) |
| Scraping data behind login/authentication | Very High |
| Commercial use of scraped data | Very High |
| Bypassing access controls (CAPTCHA, rate limits) | Very High |
| Respecting robots.txt and rate limits | Medium (still violates ToS) |

## Applicable Laws

1. **Breach of Contract** - Violating ToS can lead to civil liability
2. **Computer Fraud and Abuse Act (CFAA)** - Prohibits unauthorized access or exceeding authorized access
3. **Copyright Law** - May apply if substantial content is copied
4. **Privacy/Data Protection Laws** - May apply depending on data collected

## Recommendations

### DO NOT Implement Without:
1. **Thorough legal review** by qualified counsel
2. **Explicit written permission** from platforms
3. **Comprehensive risk assessment** including potential liability

### Alternatives:
1. **Official APIs** - Neither platform offers public APIs for marketplace data
2. **Partnership** - Partner with platforms for authorized access
3. **Authorized Data Providers** - Use third-party services with proper licensing
4. **User-Initiated Sharing** - Allow users to manually share listings (no scraping)

### If Proceeding (Not Recommended):
1. Ensure compliance with robots.txt
2. Implement strict rate limiting
3. Respect all access controls
4. Do not bypass CAPTCHAs or authentication
5. Only scrape publicly visible data (if legally permissible)
6. Avoid commercial use of scraped data
7. Implement proper attribution
8. Have legal counsel review implementation

## Implementation Status

**Current Status:** Returns empty results. Implementation deferred.

**Decision Date:** Based on legal review completed during implementation planning.

**Review Date:** Should be re-evaluated if:
- Platforms offer official APIs
- Legal landscape changes significantly
- Partnership opportunities arise

## References

- Craigslist Terms of Use: https://www.craigslist.org/about/terms.of.use.en
- Facebook Help Center: https://www.facebook.com/help/463983701520800
- Bright Data v. Meta (2024) - U.S. District Court, Northern District of California
- Craigslist v. 3Taps, Radpad, Instamotor - Various U.S. District Courts

## Notes

This review is based on publicly available information and case law as of early 2025. Legal landscape may change. This is not legal advice - consult qualified legal counsel before making implementation decisions.
