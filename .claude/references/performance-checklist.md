# Performance Checklist

Quick reference checklist for web application performance. Use alongside the `performance-optimization` skill.

## Table of Contents

- [Core Web Vitals Targets](#core-web-vitals-targets)
- [Frontend Checklist](#frontend-checklist)
- [Backend Checklist](#backend-checklist)
- [Measurement Commands](#measurement-commands)
- [Common Anti-Patterns](#common-anti-patterns)

## Core Web Vitals Targets

| Metric | Good | Needs Work | Poor |
|--------|------|------------|------|
| LCP (Largest Contentful Paint) | ≤ 2.5s | ≤ 4.0s | > 4.0s |
| INP (Interaction to Next Paint) | ≤ 200ms | ≤ 500ms | > 500ms |
| CLS (Cumulative Layout Shift) | ≤ 0.1 | ≤ 0.25 | > 0.25 |

## TTFB Diagnosis

When TTFB is slow (> 800ms), check each component in DevTools Network waterfall:

- [ ] **DNS resolution** slow → add `<link rel="dns-prefetch">` or `<link rel="preconnect">` for known origins
- [ ] **TCP/TLS handshake** slow → enable HTTP/2, consider edge deployment, verify keep-alive
- [ ] **Server processing** slow → profile backend, check slow queries, add caching

## Backend Checklist

### Database
- [ ] No N+1 query patterns (use eager loading / joins)
- [ ] Queries have appropriate indexes
- [ ] List endpoints paginated (never `SELECT * FROM table`)
- [ ] Connection pooling configured
- [ ] Slow query logging enabled

### API
- [ ] Response times < 200ms (p95)
- [ ] No synchronous heavy computation in request handlers
- [ ] Bulk operations instead of loops of individual calls
- [ ] Response compression (gzip/brotli)
- [ ] Appropriate caching (in-memory, Redis, CDN)

### Infrastructure
- [ ] CDN for static assets
- [ ] Server located close to users (or edge deployment)
- [ ] Horizontal scaling configured (if needed)
- [ ] Health check endpoint for load balancer

## Measurement Commands

```bash
# Lighthouse CLI
npx lighthouse https://localhost:3000 --output json --output-path ./report.json

# Bundle analysis
npx webpack-bundle-analyzer stats.json
# or for Vite:
npx vite-bundle-visualizer

# Check bundle size
npx bundlesize

# Web Vitals in code
import { onLCP, onINP, onCLS } from 'web-vitals';
onLCP(console.log);
onINP(console.log);
onCLS(console.log);
```

## Common Anti-Patterns

| Anti-Pattern | Impact | Fix |
|---|---|---|
| N+1 queries | Linear DB load growth | Use joins, includes, or batch loading |
| Unbounded queries | Memory exhaustion, timeouts | Always paginate, add LIMIT |
| Missing indexes | Slow reads as data grows | Add indexes for filtered/sorted columns |
| Layout thrashing | Jank, dropped frames | Batch DOM reads, then batch writes |
| Large bundles | Slow Time to Interactive | Code split, tree shake, audit deps |
| Blocking main thread | Poor INP, unresponsive UI | Use Web Workers, defer work |
| Memory leaks | Growing memory, eventual crash | Clean up listeners, intervals, refs |