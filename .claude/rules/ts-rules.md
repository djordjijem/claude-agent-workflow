---
paths: src/**/*.ts, src/**/*.tsx, **/*.ts
---

# TypeScript Rules

## `any` is BANNED

Never use `any`. This is non-negotiable.

| Situation | Solution |
|-----------|----------|
| Don't know the type | Create an interface/type |
| External data (API, JSON) | Use `unknown` + type guard |
| Complex generic | Define proper generic constraints |
| "It's faster with any" | No. Define the type. |

## Global Types

Location: `src/types/types.ts`

All shared types, interfaces, and type utilities go here.
```typescript
// src/types/types.ts
export interface User { ... }
export interface ApiResponse<T> { ... }
export type ID = string | number;
```

## Type Guards for `unknown`
```typescript
function isUser(data: unknown): data is User {
  return (
    typeof data === "object" &&
    data !== null &&
    "id" in data &&
    "name" in data
  );
}

// Usage
function processData(data: unknown) {
  if (isUser(data)) {
    console.log(data.name); // ✅ typed as User
  }
}
```

## If tempted to use `any`:
1. STOP
2. Ask: "What is this data actually shaped like?"
3. Create the type
4. Use it