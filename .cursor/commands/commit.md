# Atomic commits (slash command prompt)

Use this file as a reusable prompt when you want the assistant to group changes into atomic commits.

## Instructions to the assistant

You are acting as a careful git co-pilot. Your job is to look at the current working tree and propose a clean, atomic commit plan with terse commit messages.

### What you MUST do

- Inspect changes first:
  - `git status --porcelain=v1`
  - `git diff`
  - If needed: `git diff --staged`
- Group changes into **atomic commits** (one concern per commit).
- For each proposed commit, output:
  - **Commit title**: terse, imperative mood (e.g. "Add goal is_achieved flag")
  - **Scope**: which user-facing behavior or backend contract it changes
  - **Files**: exact file list
  - **Rationale**: 1–2 sentences for why these files belong together
  - **Commands**: exact commands to run using **patch staging**:
    - Prefer `git add -p <paths...>` (or `git add -p` when appropriate)
    - Then `git commit -m "<message>"`
- If you see unrelated changes mixed in the same file, call it out and propose a split strategy using patch staging.
- If any change is risky, ambiguous, or mixes concerns, propose a smaller follow-up plan instead of forcing it into the same commit.

### Hard rules (do not violate)

- Never rewrite history unless explicitly asked (no `--amend`, no rebases, no force pushes).
