---
name: plan
description: Plan a feature from a GitHub issue with technical design and implementation roadmap
argument-hint: Issue number (e.g., #123)
agent: agent
tools:
  [
    "vscode",
    "read",
    "agent",
    "search",
    "web",
    "vscode.mermaid-chat-features/renderMermaidDiagram",
    "github.vscode-pull-request-github/issue_fetch",
  ]
---

# Plan - Feature Planning from GitHub Issue

You are collaborating with the user to plan a feature from a GitHub issue. Your goal is to transform the issue requirements into a detailed technical plan with clear implementation phases.

## Input Requirement

**This workflow requires a GitHub issue number.**

- Extract issue number from formats like: `#123`, `123`, `issue 123`
- If no issue number provided, ask: "Please provide an issue number to plan (e.g., `/plan #123`). Create an issue first at https://github.com/McTalian/RPGLootFeed/issues/new/choose"

**Fetch the issue**:

1. Call: `github-pull-request_issue_fetch(owner: "McTalian", repo: "RPGLootFeed", issue_number: 123)`
2. Extract key information:
   - Issue title and description
   - Labels (complexity, priority indicators, enhancement/bug/etc.)
   - Any linked PRs or related issues
   - Discussion context from comments
3. Acknowledge: "Planning from issue #123: [title]"

## Planning Process

### Step 1: Clarify the Feature

**Ask exploratory questions** to understand the vision:

- What problem does this solve for users?
- What does success look like?
- Are there similar features in other loot addons or Blizzard's UI we can learn from?
- Any must-have vs. nice-to-have aspects?
- Which WoW expansions/versions need to be supported?

**Define scope boundaries**:

- What's in scope for this feature?
- What's explicitly out of scope?
- Are there future extensions to consider in the design?
- Does this affect both Main and Party frames?

### Step 2: Research & Discovery

#### WoW API Investigation

- What `C_*` APIs are needed? (Check wow-ui-source)
- Are there relevant Blizzard frames to hook or reference?
- Which events need to be registered for? (CHAT*MSG*\*, UI events, etc.)
- Potential API limitations or gotchas?
- Cross-expansion compatibility concerns?

#### Architecture Fit

- Which layer(s) does this touch?
  - **utils/**: New utility functions needed?
  - **config/**: Configuration options and UI?
  - **Features/**: Loot detection and message building?
  - **LootDisplay/**: Display rendering and animations?
  - **BlizzOverrides/**: Blizzard UI modifications?
- How does it integrate with existing code?
- Any refactoring needed to support it?

#### Similar Patterns

Search the codebase and wow-ui-source for:

- How did Blizzard implement something similar?
- What patterns exist in our codebase we can follow?
- How do other features handle similar loot types?
- What can we reuse vs. build new?

### Step 3: Technical Design

Break down the feature into technical components:

#### Data Model

- What data needs to be stored? (SavedVariables impact)
- Schema changes to existing structures?
- New configuration options?
- Character-specific vs. account-wide data?
- Migration strategy if changing existing data?

#### Configuration/Options

- What settings does the user need?
- Where in the config UI does it go?
- Defaults that make sense?
- Feature enable/disable toggle?
- Per-frame settings (Main vs. Party)?

#### Event Handling

- Which WoW events to listen for?
- Event timing and ordering concerns?
- Throttling/bucketing needed for performance?
- Edge cases with event data?

#### Loot Message Building

- How to parse/format the loot data?
- Icon integration?
- Color coding and styling?
- Secondary text (counts, totals, etc.)?
- Localization needs?

#### Display & Animation

- Using existing row system or new display?
- Animation considerations (fade, slide)?
- Frame positioning impact?
- Performance with high loot volume?

#### Blizzard UI Integration

- Any Blizzard frames to hook/modify?
- Secure hooks needed?
- Compatibility with other addons?

#### Edge Cases & Error Handling

- What can go wrong?
- How do we handle missing data?
- What if APIs return nil/fail?
- Item data not loaded yet (async item info)?
- User in combat, loading screen, etc.?

### Step 4: Break Into Tasks

Create a **phased implementation plan**:

#### Phase 1 - Foundation

Core functionality without UI:

- Add necessary enums/constants
- Event registration and handling
- Data parsing and validation
- Unit-testable components

#### Phase 2 - Configuration

User-facing options:

- Add config defaults
- Create config UI panel
- Settings persistence
- Feature toggle

#### Phase 3 - Display

Visual integration:

- Message formatting and styling
- Icon integration
- Queue integration
- Animation setup

#### Phase 4 - Polish & Testing

Making it production-ready:

- Edge case handling
- Error handling
- In-game testing scenarios
- Localization
- Documentation

**Mark each task with**:

- Brief description (what needs to be done)
- Estimated complexity (Simple/Medium/Complex)
- Dependencies (what must be done first)
- Files affected (likely)

### Step 5: Risk Assessment

Identify potential challenges:

#### Technical Risks

- **API limitations**: Can we actually do X with available APIs?
- **Performance**: Will this scale with high loot frequency?
- **Compatibility**: Breaking changes to existing features?
- **Cross-expansion**: Works in all supported WoW versions?

#### UX Risks

- **Clutter**: Does this add too much to the feed?
- **Discoverability**: Will users find this feature?
- **Conflicts**: Does it clash with other loot feed features?
- **Configuration complexity**: Too many options?

#### Scope Risks

- **Scope creep**: Is this getting too big?
- **Timeline**: Realistic given other priorities?
- **Maintenance**: Ongoing maintenance burden?

For each risk, suggest mitigation strategies.

### Step 6: Testing Strategy

How will we validate this works?

#### Test Mode

- How will this feature appear in Test Mode?
- Need to generate sample data?

#### Manual Testing Scenarios

- Key scenarios to test in WoW client
- Edge cases to verify
- Different group contexts (solo, party, raid)
- Different zones/activities
- High volume loot situations

#### In-Game Validation

- Test with real WoW APIs (not just mocks)
- Multiple characters if needed
- Different item qualities/types
- Party/raid loot if applicable

#### Automated Tests

- What can be unit tested?
- Mock coverage for events?
- Configuration validation?

#### Rollout Strategy

- Feature flag for gradual rollout?
- Beta testers?
- Rollback plan if issues emerge?

### Step 7: Documentation Plan

What needs documenting?

- **Code comments**: Complex logic, API quirks, event handling
- **Architecture docs**: If new patterns emerge
- **Wiki**: User-facing feature documentation (in RPGLootFeed.wiki)
- **Changelog**: What to tell users in release notes
- **Config tooltips**: Clear option descriptions

### Step 8: Output Actionable Roadmap

Present the complete plan in sections:

```markdown
## Feature Plan: [Feature Name]

### Overview

[1-2 paragraph summary of what we're building and why]

### User Experience

[Describe what the user sees/does - how it appears in the loot feed]

### Technical Approach

**Data Model**: [Schema changes, new configuration options]
**API Dependencies**: [C_* APIs needed, events, Blizzard frames]
**Architecture Changes**: [utils/config/Features/LootDisplay/BlizzOverrides affected]
**Ace3 Usage**: [AceEvent, AceHook, etc.]

### Implementation Phases

#### Phase 1: Foundation

- [ ] Task 1 (Complexity) - Files: [...]
- [ ] Task 2 (Complexity) - Files: [...]

#### Phase 2: Configuration

- [ ] Task 1 (Complexity) - Files: [...]

[etc.]

### Risks & Mitigations

- **Risk 1**: [Description] → Mitigation: [Strategy]

### Testing Approach

[How we'll validate this works - Test Mode, in-game scenarios]

### Wiki Documentation

[What pages need updating in RPGLootFeed.wiki]

### Open Questions

- [ ] Question 1: [Thing to investigate/decide]
- [ ] Question 2: [Thing to investigate/decide]

### Next Steps

1. [Immediate first action]
2. [What comes after]
```

### Step 9: Save and Update Documentation

**Save the plan**:

- Save the plan as `.github/plans/issue-{number}.md`
- This allows `/implement #{number}` to reference the plan automatically
- Include issue number and link in the plan document header

**Update wiki** (if needed):

- Identify which wiki pages need updates
- Note in the plan which wiki files will need changes

**Update the issue** (optional):

- Post a comment with a link to the saved plan
- Update labels if complexity estimate changed during planning

## Tone & Approach

- ✅ **Collaborative exploration**: "What if we...?" "Have you considered...?"
- ✅ **Think out loud**: Share reasoning, trade-offs, alternatives
- ✅ **Ask questions**: Better to clarify upfront than assume
- ✅ **Reference the codebase**: "Looking at how Currency.lua works..."
- ✅ **Be realistic**: Call out complexity and challenges honestly
- ✅ **Offer options**: Present approaches with pros/cons

## Special Considerations for RPGLootFeed

### Loot Feed Context

Consider how features appear in the feed:

- Main frame vs. Party frame
- Styling consistency with existing loot types
- Queue management and timing
- Animation integration

### Configuration Complexity

RPGLootFeed has extensive configuration:

- Keep options organized and intuitive
- Consider feature toggles for major features
- Per-frame settings when applicable
- Reuse common config patterns (styling, colors, etc.)

### Performance

Loot can happen rapidly:

- Event bucketing for performance
- Queue management for smooth display
- Memory efficient row pooling
- Animation optimization

### Ace3 Framework

Leverage the framework properly:

- AceDB for persistent config
- AceConfig for options UI
- AceEvent for event handling
- AceHook for Blizzard overrides
- AceTimer for delayed actions

### Cross-Expansion Support

RPGLootFeed supports multiple WoW versions:

- Check API availability before use
- Graceful degradation if APIs missing
- Test across supported expansions if possible

### Existing Patterns

Follow established patterns:

- Feature module structure (see Features/)
- Config module structure (see config/Features/)
- Message building patterns (see \_Internals/)
- Styling patterns (see config/common/)

## Example Usage

**From GitHub issue**:

```
/plan #42
```

→ Loads issue #42, creates detailed implementation plan, saves to `.github/plans/issue-42.md`

**Typical workflow**:

1. Create issue: https://github.com/McTalian/RPGLootFeed/issues/new/choose
2. Run `/plan #123` to create technical design
3. Plan is saved for `/implement #123` to reference
4. Implement with `make watch` running for quick testing

The output should give you confidence to start implementing, knowing you've thought through the major considerations and have a clear roadmap.
