# Project Memory System - Bootstrap Complete

**Created:** 2026-03-26  
**Status:** ✅ Ready for Population

## What Has Been Set Up

A hybrid project memory system consisting of:

### 1. **SQLite Decision Database** (`DECISION_LOG.db`)
- **Location:** `docs/project-memory/DECISION_LOG.db`
- **Tables:**
  - `decisions` — Individual decisions with metadata (session, category, date, status, outcome)
  - `design_patterns` — Recurring patterns with rationale and examples
  - `session_summary` — Session-level summaries (theme, outcomes, decisions made)
  - `conversation_threads` — Threads of related decisions/discussions
- **Initial Data:** 6 decisions + 1 session summary + 6 design patterns from UI Redesign session

### 2. **Markdown Documentation**

#### Core Files
- **[README.md](./README.md)** — Overview and navigation guide
- **[decisions/DECISIONS.md](./decisions/DECISIONS.md)** — Narrative decision records (6 decisions from Session 1, fully documented)
- **[design-patterns/PATTERNS.md](./design-patterns/PATTERNS.md)** — Design patterns with examples (6 patterns documented)
- **[reference/QUICK_START.md](./reference/QUICK_START.md)** — Quick reference for contributors
- **[evolution/TIMELINE.md](./evolution/TIMELINE.md)** — Session-by-session evolution (template ready)

### 3. **Tools & Scripts**

- **[builder.py](./builder.py)** — Python utility to programmatically add decisions/sessions to database
- **.gitignore** — Excludes database from version control (ready for separate tracking)

---

## Initial Data: UI Redesign Session

### 6 Decisions Documented

1. **3-Gate Visual Review Process** — Established quality gates (pixel ≥80%, HIG, UX)
2. **Native Glass for Controls, Plain for Icons** — Button styling conventions
3. **Never Stack Glass on Glass** — Compositing rules
4. **Remove LiquidGlassPanel from List Rows** — Row styling patterns
5. **Design Reference Images as Source of Truth** — Reference-driven process
6. **Extract Complex Views to Computed Properties** — Architecture pattern for SwiftUI

### 6 Design Patterns Documented

1. **Liquid Glass Button Styling** — .glass, .glassProminent, .plain conventions
2. **Timer State Machine** — IDLE ↔ FOCUSING ↔ PAUSED → OVERTIME
3. **MVVM Scene Sharing** — @Observable ViewModel injected via .environment()
4. **Day Boundary Attribution** — Cross-midnight session overlap calculation
5. **Never Glass on Glass** — Compositing rules
6. **Reference-Driven Design** — PNG reference images as source of truth

---

## How to Use This System

### For Committing Future Session Insights

After completing work in a session:

```bash
# 1. Use builder.py to add decisions
python3 docs/project-memory/builder.py

# Or use SQL directly in SQLite CLI:
sqlite3 docs/project-memory/DECISION_LOG.db
INSERT INTO decisions (id, session_id, category, title, ...) VALUES (...);

# 2. Update narrative markdown files if needed
# - Add to decisions/DECISIONS.md
# - Add to design-patterns/PATTERNS.md  
# - Add to evolution/TIMELINE.md

# 3. Commit
git add docs/project-memory/
git commit -m "docs: add session X insights to project memory"
```

### For Querying Information

```bash
# List all UI decisions
sqlite3 docs/project-memory/DECISION_LOG.db \
  "SELECT title FROM decisions WHERE category='UI';"

# Find decisions from specific session
sqlite3 docs/project-memory/DECISION_LOG.db \
  "SELECT title FROM decisions WHERE session_id='SESSION_ID';"

# Get all active design patterns
sqlite3 docs/project-memory/DECISION_LOG.db \
  "SELECT pattern_name FROM design_patterns;"
```

### For Agents to Access Information

Agents should:
1. Start by reading [reference/QUICK_START.md](./reference/QUICK_START.md) for overview
2. Query database for decisions in their area: `sqlite3 DECISION_LOG.db "SELECT * FROM decisions WHERE category='YOUR_AREA';"`
3. Review [design-patterns/PATTERNS.md](./design-patterns/PATTERNS.md) for established conventions
4. Check [evolution/TIMELINE.md](./evolution/TIMELINE.md) to understand how thinking evolved

---

## Next Steps (Not Yet Done)

### Immediate (Recommended)

1. **Add remaining high-impact sessions** (5-10 total)
   - Timer state machine decisions
   - Data model decisions  
   - Notification architecture
   - Day boundary handling

2. **Fill in TIMELINE.md** with session-by-session evolution
   - Add session 2-10 summaries
   - Show decision reversals
   - Document pattern evolution

3. **Create indices for queryability**
   - Category index (Timer, UI, Data, Notifications, Architecture)
   - File map (which files were affected by which decisions)
   - Dependency graph (decision A led to decision B)

### Later (Nice-to-Have)

- VoiceOver accessibility audit trail
- Performance decision log
- External dependency decisions  
- Deployment/CI/CD decisions

---

## File Structure

```
docs/project-memory/
├── README.md                    # Main navigation guide
├── DECISION_LOG.db             # SQLite database (queryable)
├── builder.py                  # Python utility for adding decisions
├── .gitignore                  # Exclude database from version control
│
├── decisions/
│   └── DECISIONS.md            # Narrative decision records (6 documented)
│
├── design-patterns/
│   └── PATTERNS.md             # Design patterns with examples (6 documented)
│
├── reference/
│   └── QUICK_START.md          # Quick reference guide
│
└── evolution/
    └── TIMELINE.md             # Session-by-session evolution (template)
```

---

## Database Schema Reference

### `decisions` Table

```sql
id TEXT PRIMARY KEY,
session_id TEXT,
decision_date TEXT,
category TEXT,                  -- UI, Timer, Data, Notifications, Architecture
title TEXT,
description TEXT,
rationale TEXT,
outcome TEXT,
alternatives_considered TEXT,
impact TEXT,
status TEXT,                    -- 'active', 'deprecated', 'evolving'
related_decisions TEXT,
created_at TIMESTAMP
```

### `design_patterns` Table

```sql
id TEXT PRIMARY KEY,
pattern_name TEXT,
description TEXT,
examples TEXT,                  -- JSON array
rationale TEXT,
created_in_session TEXT,
category TEXT
```

### `session_summary` Table

```sql
session_id TEXT PRIMARY KEY,
session_index INTEGER,
start_date TEXT,
end_date TEXT,
theme TEXT,
description TEXT,
key_outcomes TEXT,             -- JSON array
decisions_made TEXT,           -- JSON array
learnings TEXT,
checkpoint_file TEXT
```

---

## Important Notes

1. **Database is committed separately** — Use `git add docs/project-memory/DECISION_LOG.db` when ready to lock in decisions

2. **Markdown is the narrative, SQL is the index** — Keep both in sync; markdown tells the story, SQL enables queries

3. **Reference images are law** — All visual decisions must be driven by Stitch folder images

4. **3-Gate review applies to all UI work** — Never present visual changes <80% match

5. **Status field allows tracking evolution** — Mark decisions as 'active', 'deprecated', or 'evolving' as they change

---

*For more information, see [README.md](./README.md)*
