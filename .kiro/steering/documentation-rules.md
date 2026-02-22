---
inclusion: always
---

# Documentation Rules

## Markdown File Policy

**CRITICAL RULE**: Do NOT create unnecessary markdown documentation files unless explicitly requested by the user.

### Allowed MD Files
- `README.md` - Main documentation for packages/directories
- Files in `.kiro/specs/` - Spec-driven development documents
- User-requested documentation

### Prohibited MD Files
- `QUICKSTART.md`
- `TESTING.md`
- `STRUCTURE.md`
- `CONTRIBUTING.md`
- `CHANGELOG.md`
- `ARCHITECTURE.md`
- Any other supplementary documentation files

### Rationale
- Reduces noise and clutter
- Keeps documentation focused in README
- Prevents documentation drift and maintenance burden
- User can request specific docs if needed

### What to Do Instead
- Put all essential information in `README.md`
- Use code comments for implementation details
- Use docstrings for API documentation
- Keep it minimal and focused

## Example: Good Documentation Structure

```
scrapper/
├── README.md              ✓ Main documentation
├── scrapper/
│   ├── web_scraper.py    ✓ Code with docstrings
│   └── sources/
│       └── base.py       ✓ Code with docstrings
└── tests/
    └── scrapper/
        └── test_web_scraper.py
```

## Example: Bad Documentation Structure (DON'T DO THIS)

```
scrapper/
├── README.md
├── QUICKSTART.md          ✗ Unnecessary
├── TESTING.md             ✗ Unnecessary
├── STRUCTURE.md           ✗ Unnecessary
├── CONTRIBUTING.md        ✗ Unnecessary
└── scrapper/
    └── sources/
        └── ADDING_NEW_SOURCES.md  ✗ Unnecessary
```

## When User Asks for Documentation
If the user explicitly requests documentation:
1. Ask if they want it in README or separate file
2. If separate file, create only what they requested
3. Keep it concise and focused

## Summary
**Default behavior**: Only create README.md files. Everything else requires explicit user request.

---

# Simplicity and Cleanup Rules

## Keep It Simple

**CRITICAL RULE**: Always prefer simple, minimal setups over complex configurations.

### Packaging and Setup
- **Prefer `requirements.txt`** over complex `pyproject.toml` + `setup.py` + `MANIFEST.in`
- **Avoid unnecessary packaging files** unless the project needs to be published to PyPI
- **Use simple scripts** (like `run_tests.sh`) instead of complex build systems
- **Don't over-engineer** - start simple, add complexity only when needed

### Examples

**Good (Simple):**
```
scrapper/
├── requirements.txt       ✓ Simple dependency list
├── run_tests.sh          ✓ Simple test runner
└── README.md             ✓ Documentation
```

**Bad (Over-engineered):**
```
scrapper/
├── requirements.txt
├── pyproject.toml        ✗ Unnecessary for internal package
├── setup.py              ✗ Unnecessary for internal package
├── MANIFEST.in           ✗ Unnecessary for internal package
├── setup.cfg             ✗ Unnecessary
├── tox.ini               ✗ Unnecessary
└── README.md
```

## Proactive Cleanup

When you notice unnecessary files or complexity:

1. **Identify the issue** - What files/setup are unnecessary?
2. **Suggest cleanup** - Explain what can be removed and why
3. **Wait for confirmation** - Don't delete without user approval
4. **Perform cleanup** - After confirmation, remove unnecessary files
5. **Update documentation** - Remove references to deleted files

### What to Look For

**Unnecessary packaging files:**
- `pyproject.toml`, `setup.py`, `setup.cfg` (unless publishing to PyPI)
- `MANIFEST.in`, `tox.ini`, `noxfile.py`
- Root-level `__init__.py` files that serve no purpose

**Redundant configuration:**
- Multiple config files doing the same thing
- Unused environment files
- Empty or placeholder files

**Over-documentation:**
- Multiple README files
- Unnecessary markdown files (see Documentation Rules above)

### When to Keep Complex Setup

Only use complex packaging when:
- Publishing to PyPI
- Need editable installs across multiple projects
- Building distributable packages
- User explicitly requests it

## Guiding Principle

**Start simple. Add complexity only when there's a clear need.**

If you can accomplish the same goal with:
- `requirements.txt` instead of `pyproject.toml` → use `requirements.txt`
- A simple script instead of a build system → use the script
- One README instead of multiple docs → use one README

Choose the simpler option.
