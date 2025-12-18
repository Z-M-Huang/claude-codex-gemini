# Project Standards

## Coding Standards

### General Principles
- Write self-documenting code
- Keep functions small and focused (< 50 lines)
- No `any` types - use `unknown` if truly unknown
- Handle errors explicitly

### Naming Conventions
- Files: `kebab-case.ts`
- Classes: `PascalCase`
- Functions/variables: `camelCase`

---

## Review Checklist

### Must Check (Blockers - severity: error)
- No security vulnerabilities (SQL injection, XSS, OWASP Top 10)
- No secrets/credentials in code
- Error handling for failure paths
- Input validation at boundaries

### Should Check (severity: warning)
- Code follows project conventions
- No unnecessary code duplication
- Functions have single responsibility
- Tests cover main scenarios

### Over-Engineering Detection (severity: warning)
- Abstractions without multiple use cases
- Premature optimization
- Unnecessary configuration/flexibility
- Complex patterns for simple problems

### Nice to Have (severity: suggestion)
- Documentation for complex logic
- Consistent formatting

---

## Decision Rules
- Any `error` -> status: `needs_changes`
- 3+ `warning` -> status: `needs_changes`
- Only `suggestion` -> status: `approved`
