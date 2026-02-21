---
name: park
description: Save session progress and generate handoff summary for context transfer
agent: agent
tools: ["vscode", "read", "edit", "search", "todo"]
---

# Park Session - Context Handoff

You are preparing to hand off this development session to a fresh agent context. Your goal is to:

1. **Update project documentation** with accomplishments from this session - follow [Documentation Maintenance](../copilot-instructions.md#documentation-maintenance)
2. **Generate a handoff summary** for seamless continuation in a new session

**GOLDEN RULE**: Only include information that is directly relevant to work done in this session. The summary should be comprehensive but concise, focusing on what the next agent needs to know to pick up where you left off without having to read through the entire conversation history.

## Step 1: Review Current Session

Analyze the conversation history and identify:

- Files created, modified, or deleted
- Features implemented or bugs fixed
- Architectural decisions made
- Tests run and their results
- Any in-progress work or blockers
- Important insights or discoveries

## Step 2: Update Documentation

Update the following files as appropriate based on session accomplishments:

### [copilot-instructions.md](../copilot-instructions.md)

- Update "Project Overview" if significant functionality was added
- Document any new conventions or architecture decisions in appropriate sections
- Note any new tools, libraries, or workspace considerations

### Other docs (if applicable):

- **[architecture.md](../docs/architecture.md)** - New features, directory conventions, or structural changes
- **[glossary.md](../docs/glossary.md)** - New WoW concepts, addon terminology, or technical terms
- **[resources.md](../docs/resources.md)** - New API patterns, library usage, or development tools
- **[testing.md](../docs/testing.md)** - New testing approaches, test cases, or testing utilities
- **[RPGLootFeed.wiki](../../RPGLootFeed.wiki)** - User-facing feature documentation and guides

**Important**: Only update docs that are actually relevant to this session's work. Don't make changes just for the sake of it.

## Step 3: Generate Handoff Summary

Create a comprehensive handoff summary with these sections:

### 📋 Session Overview

- Brief description of the session's main goal
- Date and approximate duration

### ✅ Completed Work

List each accomplishment with:

- What was done
- Files affected (with line references if useful)
- Any important implementation details

### 🚧 In-Progress Work

If work was left incomplete:

- What was started but not finished
- Current state and what remains
- Any blockers or challenges discovered

### 💡 Key Insights & Decisions

- Architectural decisions made and why
- Important discoveries about the codebase or APIs
- Trade-offs considered
- Issues encountered and how they were resolved

### 📦 Files Modified

Comprehensive list organized by change type:

- **Created**: New files
- **Modified**: Changed files with brief description of changes
- **Deleted**: Removed files

### 🧪 Testing Status

- Tests run (if any)
- Results and any failures
- Manual testing performed
- Known issues or edge cases

### 🎯 Recommended Next Steps

Prioritized list of what should be tackled next:

1. Immediate follow-ups from this session
2. Related tasks that emerged
3. Longer-term items to consider

### 📝 Context to Preserve

Any important context that might not be obvious from the code:

- Why certain approaches were chosen
- What was tried and didn't work
- Quirks or limitations discovered
- Open questions or areas needing investigation

### 🚀 Quick Start for Next Session

A literal prompt or command the next agent can use to dive right in:

```
Example: "Continue implementing the leaderboard feature. The database schema has been updated in Database.lua (lines 45-67) to support activity tracking by BattleTag. Next, implement the UI component in Features/Leaderboard.lua following the patterns established in Features/Tasks.lua."
```

## Output Format

First, show the documentation updates you're making (you should actually apply these changes using the appropriate tools).

Then, create a `park-YYYYMMDDTHHmm.md` file in the `.github/parked-sessions` folder (create the folder if it doesn't exist) and output the handoff summary into the file in a clean, copy-paste-ready format that starts with a clear heading like:

```
═══════════════════════════════════════════════
🅿️  PARKED SESSION HANDOFF
═══════════════════════════════════════════════
```

Make the summary comprehensive enough that the next agent (or you in a new session) can pick up seamlessly without having to dig through the full conversation history.
