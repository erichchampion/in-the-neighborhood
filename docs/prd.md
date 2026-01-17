# Product Requirements Document: In the Neighborhood

**Version:** 0.1 Draft  
**Date:** January 16, 2026  
**Status:** Concept/Pre-Planning

---

## Executive Summary

In the Neighborhood is an iOS metasearch application that helps conscious consumers find products at local merchants and ethical online retailers while avoiding mega-retailers (Amazon, Walmart, Target, Home Depot, etc.). The app uses on-device AI to understand search intent, queries multiple sources simultaneously, and prioritizes local businesses over corporate chains.

---

## Problem Statement

Consumers who want to support local businesses or avoid certain large retailers face significant friction:
- Google search results heavily favor mega-retailers
- No single tool aggregates local + ethical online options
- Users don't know which local stores carry specific products
- Time-consuming to check multiple sources manually
- Local inventory visibility is essentially non-existent

---

## Goals & Non-Goals

### Goals
- Enable product discovery at local merchants within user's region
- Provide ethical online alternatives when local options unavailable
- Respect user privacy (no search history tracking, on-device processing)
- Deliver results in under 3 seconds
- Support conscious consumerism without requiring behavior change

### Non-Goals
- Real-time inventory tracking (technically infeasible for most local merchants)
- Price comparison engine (focus is discovery, not lowest price)
- Marketplace/transaction platform (we don't handle payments)
- Social features or reviews (users can navigate to existing platforms for that)

---

## Target Users

### Primary Persona: "Conscious Consumer"
- Age 25-45, urban/suburban, college-educated
- Values supporting local economy, sustainability, ethical business
- iPhone user, tech-comfortable
- Willing to pay slightly more for values alignment
- Frustrated with Amazon dominance

### Secondary Persona: "Local First Researcher"
- Already committed to avoiding mega-retailers
- Currently uses multiple apps/sites to find alternatives
- Needs efficiency tool to reduce research time

---

## Core Features (MVP)

Website: in-the-neighborhood.com
BundleId: com.in-the-neighborhood

### 1. Intelligent Search
**On-Device Query Enhancement**
- Local LLM (Mistral 3B) processes natural language queries
- Extracts: product type, business categories, price constraints, condition (new/used)
- Runs on-device for privacy (no query data leaves phone)
- Fallback to direct search if LLM unavailable

**User Experience:**
```
User types: "ergonomic office chair under $300"

Behind the scenes:
- LLM identifies: product="office chair", price_max=300, categories=["furniture store", "office supply"]
- System generates parallel searches with location context
```

### 2. Multi-Source Metasearch
**Simultaneous Queries:**
- **Local Discovery**: MapKit MKLocalSearch for relevant business categories
- **Web Search**: Aggregated results from multiple search engines (DuckDuckGo, Bing)
- **Specialized Sources**: 
  - Books → Bookshop.org API
  - Used goods → Craigslist, Facebook Marketplace (where accessible)
  - Niche products → Category-specific APIs

**Result Filtering:**
- Client-side filtering removes deny-listed domains
- Configurable deny list (user can add/remove retailers)
- Default deny list: Amazon, Walmart, Target, Home Depot, Lowe's, Best Buy

### 3. Prioritized Results Display

**Tier 1: Local Merchants** (top of results)
- Business name, address, phone, distance
- "Call" and "Directions" buttons
- Note: "Call to check availability"
- Source indicator (e.g., "via Apple Maps")

**Tier 2: Regional/Ethical Online**
- Specialized online retailers (Bookshop.org, ethical marketplaces)
- Regional chains not on deny list
- Direct links to product pages

**Tier 3: General Online**
- Other non-denied retailers
- Clearly labeled as "online option"

### 4. Location Services
- Request location permission on first search
- Use city/region for query enhancement
- Fall back to zip code entry if permission denied
- Remember last location (with user consent)

### 5. Settings & Customization
- Manage deny list (add/remove retailers)
- Search radius preference (5/10/25/50 miles)
- Toggle result categories (local only, include online, etc.)
- Privacy: clear search history, export data

---

## Technical Architecture

### Frontend (iOS/Swift)
- SwiftUI for UI
- MapKit for local business discovery
- Core Location for user positioning
- MLX Swift or llama.cpp for on-device Mistral 3B

### Query Processing Pipeline
```
User Input → Local LLM Enhancement → Parallel Search Dispatch
                                          ↓
                     ┌──────────────────┬────────────────┬──────────────┐
                     ↓                  ↓                ↓              ↓
                 MapKit API      Web Metasearch   Bookshop.org    Specialized
                     ↓                  ↓                ↓              ↓
                     └──────────────────┴────────────────┴──────────────┘
                                          ↓
                            Results Aggregation & Filtering
                                          ↓
                            Priority Ranking & Deduplication
                                          ↓
                                    Display to User
```

### Backend (Minimal)
- **Optional lightweight server** for:
  - Aggregating web search API calls (to avoid API key exposure)
  - Caching popular queries (privacy-preserving, no PII)
  - Analytics (aggregated, anonymized usage patterns)
- **Alternative**: Fully client-side with embedded API keys (less ideal for security)

### Data Storage
- Local only (no cloud sync in MVP)
- Core Data for search history (optional, user-controlled)
- UserDefaults for preferences

---

## User Flows

### First-Time User
1. Opens app → Welcome screen explains value proposition
2. Grants location permission (optional but encouraged)
3. Enters first search query
4. Sees tutorial overlay explaining result tiers
5. Taps local business → Call or Directions
6. Returns to app, searches again

### Returning User
1. Opens app directly to search
2. Previous searches auto-suggested
3. Quickly finds local option or ethical online alternative
4. Shares result with friend via standard iOS share sheet

---

## Success Metrics

### Primary KPIs
- **Searches per user per week** (target: 3+)
- **Local business tap-through rate** (target: 30%+)
- **Return user rate at 30 days** (target: 40%+)
- **Average search-to-result time** (target: <3 seconds)

### Secondary Metrics
- Deny list customization rate
- Settings engagement
- Search query diversity (are users searching broad product categories?)

---

## Open Questions & Risks

### Technical Risks
1. **LLM performance on device**: Can Mistral 3B run fast enough on older iPhones (iPhone 12+)?
2. **Search result quality**: Will metasearch yield relevant results without inventory data?
3. **API rate limits**: How do we handle rate limiting from free search APIs?

### Product Risks
1. **Value perception**: Will users accept "call to check availability" friction?
2. **Result completeness**: What if local searches return zero results in rural areas?
3. **Monetization**: How do we sustain this without compromising ethics? (Affiliate links? Subscription?)

### Business Risks
1. **Legal**: Are we violating any ToS by scraping/aggregating results?
2. **Competitive**: Could Google/Apple easily replicate this with better data access?

### Questions to Resolve
- Should we include affiliate links? (Bookshop.org has affiliate program)
- Do we need user accounts, or fully anonymous?
- Should we support web/Android, or iOS-only initially?
- How do we handle product categories poorly served by local (e.g., specialized electronics)?

---

## Future Enhancements (Post-MVP)

### Phase 2
- **Saved searches**: Alert when new local options appear
- **Community contributions**: Users flag local stores that carry products
- **Integration with local inventory systems** (where available)
- **Browser extension**: Works on desktop shopping

### Phase 3
- **Barcode scanning**: Scan product in-store, find local alternatives
- **Shopping lists**: Multi-product searches
- **Carbon footprint estimates**: Compare local vs. shipped
- **Social features**: Share local finds with friends

---

## Design Principles

1. **Privacy First**: No tracking, on-device processing, transparent data practices
2. **Speed Matters**: Sub-3-second results or users abandon
3. **Honest Limitations**: Don't promise inventory data we can't provide
4. **Progressive Disclosure**: Simple search box, advanced options hidden
5. **Local Pride**: Celebrate supporting local economy in UI/messaging

---

## Competitive Landscape

**Direct Competitors:**
- None with exactly this approach

**Indirect Competitors:**
- Google Shopping (but promotes mega-retailers)
- Yelp (discovery, but not shopping-focused)
- Shop local directories (manual, not search-driven)
- Bookshop.org, Faire (category-specific)

**Our Differentiation:**
- Only tool that combines local + ethical online in single search
- On-device AI for privacy + relevance
- Explicit anti-mega-retailer positioning

---

## Timeline Estimate (Rough)

- **MVP Development**: 12-16 weeks (solo developer)
  - Weeks 1-3: Core search architecture + MapKit integration
  - Weeks 4-6: LLM integration + query enhancement
  - Weeks 7-9: Metasearch aggregation + filtering
  - Weeks 10-12: UI/UX polish
  - Weeks 13-16: Testing + App Store submission

- **Beta Testing**: 4 weeks
- **Public Launch**: Week 20

---

## Appendix

### Technology Stack
- **iOS**: Swift 6+, SwiftUI, iOS 18+
- **AI**: Mistral 3B via MLX Swift or llama.cpp
- **Maps**: MapKit, Core Location
- **Networking**: URLSession, async/await
- **Storage**: Core Data (optional), UserDefaults

### Initial Deny List
- Amazon (amazon.com, whole foods, etc.)
- Walmart (walmart.com, samsclub.com)
- Target (target.com)
- Home Depot (homedepot.com)
- Lowe's (lowes.com)
- Best Buy (bestbuy.com)
- [User can customize]

### Ethical Online Whitelist (Initial)
- Bookshop.org (books)
- Etsy (handmade/vintage)
- REI (outdoor gear, co-op model)
- B Corps and certified benefit corporations
- [Expandable based on user feedback]

---

**Document Owner**: Erich  
**Last Updated**: January 16, 2026  
**Next Review**: Upon stakeholder feedback