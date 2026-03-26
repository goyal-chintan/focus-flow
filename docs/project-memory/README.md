# FocusFlow Project Memory

**Comprehensive record of design decisions, conversation outcomes, and project evolution.**

This is the single source of truth for understanding the "why" behind FocusFlow's architecture, UI decisions, and implementation patterns. It serves as both a knowledge base for contributors and an audit trail for decisions.

## Structure

```
project-memory/
├── decisions/           # Major decisions and their rationale
├── design-patterns/     # Recurring UI/architectural patterns
├── evolution/          # How thinking evolved over time
├── reference/          # Quick-reference guides
└── DECISION_LOG.db     # Queryable database of all decisions
```

## Key Files

- **[DECISION_LOG.db](./DECISION_LOG.db)** - SQLite database with searchable decision catalog
  - Query decisions by category, date range, status
  - Track decision dependencies and impacts
  - Filter by design area (Timer, UI, Data, etc.)

- **[decisions/DECISIONS.md](./decisions/DECISIONS.md)** - Narrative record of major decisions
  - Organized by feature area
  - Includes rationale and outcomes
  - Cross-linked to related decisions

- **[design-patterns/PATTERNS.md](./design-patterns/PATTERNS.md)** - Recurring design patterns
  - UI component patterns (Glass, Liquid Glass, etc.)
  - Architecture patterns (MVVM, State Management, etc.)
  - Data flow patterns

- **[evolution/TIMELINE.md](./evolution/TIMELINE.md)** - Chronological evolution
  - Session-by-session summary
  - How decisions evolved
  - Lessons learned

- **[reference/QUICK_START.md](./reference/QUICK_START.md)** - Quick reference for contributors
  - Key architectural concepts
  - Important rules and constraints
  - Common patterns to follow

## Querying the Database

```bash
# List all UI design decisions
sqlite3 docs/project-memory/DECISION_LOG.db "SELECT title, outcome FROM decisions WHERE category='UI' ORDER BY decision_date;"

# Find all decisions related to Timer
sqlite3 docs/project-memory/DECISION_LOG.db "SELECT title, status FROM decisions WHERE category='Timer';"

# See decision evolution
sqlite3 docs/project-memory/DECISION_LOG.db "SELECT decision_date, title, outcome FROM decisions ORDER BY decision_date;"
```

## How to Use This

### For Contributors
- Read **[reference/QUICK_START.md](./reference/QUICK_START.md)** to understand established patterns
- Check **[decisions/DECISIONS.md](./decisions/DECISIONS.md)** when modifying core features
- Query the database to understand "why" a certain approach was chosen

### For New Sessions
- After completing significant work, add a decision entry to the database
- Update relevant narrative files if new patterns emerge
- Link decisions to any preceding decisions they build upon

### For Refactoring/Rearchitecting
- Review [evolution/TIMELINE.md](./evolution/TIMELINE.md) to understand the reasoning behind current structure
- Query database for all decisions in an area before proposing changes
- Document new decisions using the same format

---

*Last Updated: 2026-03-26*
*Database version: 1.0*
