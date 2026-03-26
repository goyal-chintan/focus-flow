# 📚 FocusFlow Project Memory — Complete Reference

**Status:** ✅ Bootstrap complete with initial population  
**Last Updated:** 2026-03-26  
**Scope:** 55 sessions, 6 major themes, 7 flagship sessions  

---

## 🎯 What Is This?

A **hybrid documentation system** combining:
- **SQLite Database** — Queryable decision catalog with metadata
- **Markdown Chronicles** — Narrative records of sessions, decisions, and patterns
- **Reference Guides** — Quick-start for contributors and agents

**Purpose:** Preserve institutional knowledge, enable informed decision-making, and serve as a knowledge base for independent agents.

---

## 📖 Core Documents (Start Here)

### For Quick Understanding
1. **[BOOTSTRAP_COMPLETE.md](./BOOTSTRAP_COMPLETE.md)** — System overview and setup instructions
2. **[SESSION_CHRONICLE.md](./evolution/SESSION_CHRONICLE.md)** — 55 sessions synthesized into 7 major themes
3. **[QUICK_START.md](./reference/QUICK_START.md)** — Quick reference for contributors

### For Deep Dives
1. **[DECISIONS.md](./decisions/DECISIONS.md)** — Narrative decision records (6 UI decisions with full context)
2. **[PATTERNS.md](./design-patterns/PATTERNS.md)** — Design patterns with examples (6 patterns documented)
3. **[TIMELINE.md](./evolution/TIMELINE.md)** — Evolution of key areas (template ready for population)

### The Database
- **[DECISION_LOG.db](./DECISION_LOG.db)** — SQLite database with 6 decisions, 1 session, 6 patterns
  ```bash
  sqlite3 DECISION_LOG.db "SELECT title FROM decisions WHERE category='UI';"
  ```

---

## 🚀 The 7 Major Development Themes

| Theme | Status | Key Achievement | Key Session |
|-------|--------|-----------------|-------------|
| **Focus Coach & AI** | ✅ Complete | Evidence-based intervention, on-device only | 1070162e |
| **Apple-Grade UI** | ✅ 80%+ done | 54 bugs fixed, premium Obsidian Glass | 2d4d0538 |
| **Crash Recovery** | ✅ Complete | UserDefaults system, 13+ vectors fixed | 1070162e |
| **Motion Psychology** | ✅ Complete | 5 tokens, 48+ interactions, psychology-mapped | aa8577f7 |
| **Guardian Override** | 🔄 90% done | Procrastination prevention, escalation first | 4933647b |
| **Calendar Integration** | ✅ Hardened | Multiple crash vectors fixed, defensive APIs | b0068dec |
| **Design System** | ✅ Complete | 3-gate review, reference-driven, design tokens | 491f35aa |

---

## 📊 Critical Decisions Summary

### Most Impactful (Non-Negotiable)

1. **3-Gate UI Review** → Never present UI <80% visual match to references
2. **On-Device Focus Coach** → Privacy first, no cloud, explainable
3. **Evidence-Based Coach Logic** → 6 layers backed by PubMed research
4. **Reference Images as Source of Truth** → PNG designs override code convenience
5. **Motion Psychology Mapping** → All animation serves explicit behavioral purpose

### Architecture Decisions

6. **UserDefaults Crash Recovery** → Simple, robust, proven stable
7. **Guardian Override System** → Outside-session scoring, not in-app
8. **Obsidian Glass Design Language** → Dark brand identity, native materials

---

## 🔍 How to Use This System

### For Contributors
```bash
# 1. Start here
cat docs/project-memory/reference/QUICK_START.md

# 2. Check decisions in your area
sqlite3 docs/project-memory/DECISION_LOG.db \
  "SELECT title FROM decisions WHERE category='UI';"

# 3. Review design patterns
cat docs/project-memory/design-patterns/PATTERNS.md

# 4. Understand evolution
cat docs/project-memory/evolution/SESSION_CHRONICLE.md
```

### For Agents
1. Read [QUICK_START.md](./reference/QUICK_START.md) for overview
2. Query database for decisions in your area
3. Review [PATTERNS.md](./design-patterns/PATTERNS.md) for established conventions
4. Check [SESSION_CHRONICLE.md](./evolution/SESSION_CHRONICLE.md) for context

### For Adding New Insights
```bash
# 1. Add decision to database
sqlite3 docs/project-memory/DECISION_LOG.db
INSERT INTO decisions (...) VALUES (...);

# 2. Update narrative markdown
vi docs/project-memory/decisions/DECISIONS.md

# 3. Commit
git add docs/project-memory/
git commit -m "docs: add session X insights"
```

---

## 📁 File Structure

```
docs/project-memory/
├── README.md                          # Navigation guide
├── INDEX.md                           # This file
├── BOOTSTRAP_COMPLETE.md              # Setup instructions
├── DECISION_LOG.db                    # SQLite database (queryable)
├── builder.py                         # Python utility for adding decisions
├── .gitignore                         # Exclude database from main tracking
│
├── decisions/
│   └── DECISIONS.md                   # Narrative decision records (6 UI decisions documented)
│
├── design-patterns/
│   └── PATTERNS.md                    # Design patterns with examples (6 patterns)
│
├── reference/
│   └── QUICK_START.md                 # Quick reference for contributors
│
└── evolution/
    ├── TIMELINE.md                    # Session evolution (template)
    └── SESSION_CHRONICLE.md           # Complete 55-session synthesis
```

---

## 🗂️ Current Database Contents

### Decisions (6 from Session 491f35aa)
1. 3-Gate Visual Review Process
2. Native Glass for Controls, Plain for Icons
3. Never Stack Glass on Glass
4. Remove LiquidGlassPanel from List Rows
5. Design Reference Images are Source of Truth
6. Extract Complex Views to Computed Properties

### Design Patterns (6)
1. Liquid Glass Button Styling
2. Timer State Machine
3. MVVM Scene Sharing
4. Day Boundary Attribution
5. Never Glass on Glass
6. Reference-Driven Design

### Sessions (1)
1. Apple Liquid Glass UI Redesign (491f35aa-8366-4f7b-83ca-04f133f8b943)

---

## 🎓 Key Learnings

### What Worked
- ✅ 3-Gate UI Review (systematic quality assurance)
- ✅ Evidence-based design (backed by research)
- ✅ Reference images as source (prevents divergence)
- ✅ Parallel agent dispatch (accelerated work)
- ✅ UserDefaults recovery (proven stability)

### Hard-Won Insights
- 💡 Animation + content competition = layout loop
- 💡 Code signing changes binary → use timestamps
- 💡 OS API integration → must be defensive everywhere
- 💡 Motion psychology → timing matters as much as interaction
- 💡 Reference images save expensive rework cycles

---

## 📈 Next Steps for Population

### High Priority (Recommended)
1. Add 5-10 more flagship sessions (Timer logic, Data models, Guardian)
2. Populate TIMELINE.md with session-by-session evolution
3. Create decision dependency graph (which decisions enabled which)
4. Build category indices (all Timer decisions, all Data decisions, etc.)

### Medium Priority
1. Add file impact map (which files affected by which decisions)
2. Document reversal & refinement history
3. Create pattern evolution narrative
4. Add external dependency decisions

### Nice-to-Have
1. VoiceOver accessibility audit trail
2. Performance decision log
3. Deployment & CI/CD decisions
4. Testing strategy document

---

## 🔗 Important External References

### CRITICAL: UI Design Reference
**File:** `~/.copilot/session-state/491f35aa-8366-4f7b-83ca-04f133f8b943/files/ui-design-learnings.md`  
318 lines, must-read before any UI work

**Content:**
- Source of truth hierarchy
- 3-gate review process
- 8 common design mistakes + fixes
- Design token reference
- File map for all screens

### Design Documents (in repo)
- `docs/plans/2026-03-22-personal-focus-coach-design.md` (415 lines)
- `docs/plans/2026-03-22-personal-focus-coach-implementation-plan.md` (880 lines)
- `docs/plans/2026-03-25-notification-first-coach-escalation-design.md`
- `docs/plans/2026-03-19-obsidian-glass-design-language.md`

### Stitch Reference Images
**Folder:** `Stitch/stitch_popover_break_light 2/` (13 subfolders, one per screen)  
**Purpose:** Source of truth for all visual decisions

---

## ❓ FAQ

**Q: Is the database committed to version control?**  
A: No (see `.gitignore`). Commit it separately after major session cycles when you want to lock in decisions.

**Q: How do I query the database?**  
A: Use SQLite CLI or Python sqlite3 module:
```bash
sqlite3 DECISION_LOG.db "SELECT title FROM decisions WHERE category='UI';"
```

**Q: Can I add decisions programmatically?**  
A: Yes, use `builder.py` or direct SQL INSERT commands.

**Q: What if I change a decision?**  
A: Update the `status` field to 'evolving' or 'deprecated' and add a related decision with the new approach.

**Q: Where are the other 50 sessions documented?**  
A: See [SESSION_CHRONICLE.md](./evolution/SESSION_CHRONICLE.md) for synthesis of all 55 sessions. Individual session details available in `~/.copilot/session-state/`.

---

## 🛠️ Tools & Scripts

- **builder.py** — Python utility to add decisions/sessions to database
- **SQLite database** — Query with `sqlite3 DECISION_LOG.db` command
- **Markdown files** — Human-readable narrative documents
- **.gitignore** — Excludes database from main repo tracking

---

## 📝 Version History

| Date | Change |
|------|--------|
| 2026-03-26 | Bootstrap complete: 6 decisions, 6 patterns, 1 session, all foundational docs created |

---

## 👤 Maintained By

**Initial Setup:** Copilot CLI with brainstorming-general skill  
**Data Source:** 55 FocusFlow development sessions across copilot workspace  
**Purpose:** Serve as institutional memory and knowledge base for agents and contributors

---

**🚀 Ready to use!** Start with [BOOTSTRAP_COMPLETE.md](./BOOTSTRAP_COMPLETE.md) or [SESSION_CHRONICLE.md](./evolution/SESSION_CHRONICLE.md).

*Last Updated: 2026-03-26*
