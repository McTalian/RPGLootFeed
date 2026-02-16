---
name: implement
description: Implement a feature from a GitHub issue with plan integration
argument-hint: Issue number (e.g., #123)
agent: agent
tools:
  [
    "vscode",
    "execute",
    "read",
    "edit",
    "search",
    "web",
    "todo",
    "github.vscode-pull-request-github/issue_fetch",
  ]
---

# Implement - Issue-Based Implementation

You are implementing a feature or enhancement based on a GitHub issue. This workflow loads the issue content, checks for an existing implementation plan, and executes the work systematically.

## Implementation Process

### Step 1: Load Issue Context

**Parse the issue number** from the user's command:

- Extract issue number from formats like: `#123`, `123`, `issue 123`
- If no number provided, ask the user which issue to implement

**Fetch the issue** using GitHub tools:

1. Fetch issue content: `github-pull-request_issue_fetch(owner: "McTalian", repo: "RPGLootFeed", issue_number: 123)`
2. Extract key information:
   - Issue title and description
   - Labels (complexity, priority indicators, bug/enhancement/feature)
   - Any linked PRs or related issues
   - Discussion context from comments

### Step 2: Check for Implementation Plan

**Look for existing plan document**:

- Search for plan document in issue comments (user may have posted one)
- Search for plan document by convention: `.github/plans/issue-{number}.md`
- Search workspace for related planning documents

**If plan exists**:

- Load the plan document
- Use it as the implementation roadmap
- Validate that the plan still aligns with current issue description
- Call out any discrepancies between plan and issue

**If no plan exists**:

- Ask user: "No implementation plan found. Would you like to:"
  - A) Create a plan first with `/plan #123`
  - B) Implement directly from issue description (for simple issues)
  - C) Continue with quick planning phase now

For option C, conduct abbreviated planning (5-10 minutes):

- Key technical approaches
- Files to modify
- Major steps
- Risks to watch for

### Step 3: Pre-Implementation Checks

**Validate environment**:

- Check git status is clean (warn if uncommitted changes)
- Confirm current branch (main or feature branch?)
- Suggest creating feature branch: `git checkout -b feature/issue-{number}-brief-name`

**Load necessary context**:

- Read relevant files mentioned in issue/plan
- Search for related code patterns in codebase
- Check WoW API documentation if needed (wow-ui-source)
- Load conditional instructions for file types you'll be editing

**Review complexity**:

- Issue labels indicate complexity level
- Adjust approach based on complexity:
  - **Low complexity**: Direct implementation
  - **Medium complexity**: Phase-based approach with validation checkpoints
  - **High complexity**: Suggest breaking into sub-tasks or using `/refactor` for major changes

### Step 4: Execute Implementation

**Follow the plan** (if available) or **implement from issue description**:

**For each implementation step**:

1. Announce what you're working on
2. Make the necessary code changes
3. Explain key decisions as you go
4. Call out any deviations from the plan (with reasoning)

**Coding standards** (automatically loaded for Lua files):

- Follow project conventions from conditional instructions
- Use proper nil guards and defensive coding
- Match existing code style (tabs, camelCase, etc.)
- Add comments for complex logic
- Maintain consistency with existing features

**Incremental validation**:

- After each logical chunk, check for errors: `get_errors()`
- Fix syntax/lint errors before proceeding
- Validate TOC references: `make toc_check`
- Build and check: `make dev`

### Step 5: Testing Guidance

**Test Mode integration**:

- If feature adds to loot feed, ensure Test Mode generates sample data
- Update TestMode.lua if needed to preview the feature

**Manual testing readiness**:

- Provide clear testing instructions for the feature
- List key scenarios to test in WoW client
- Call out edge cases from the plan/issue
- Suggest `make watch` for rapid testing iteration

**Test checklist from issue**:

- If issue includes acceptance criteria, create test checklist
- Mark each criterion with how to validate it
- Note different contexts to test (solo, party, raid, etc.)
- Consider different item qualities, currencies, etc.

**Testing scenarios**:

```markdown
### Testing Instructions

#### Test Mode

1. `/rlf test` to enable Test Mode
2. Verify [feature] appears correctly
3. Check styling and animations

#### In-Game Testing

1. [Specific activity to trigger feature]
2. Expected result: [what should happen]
3. Edge case: [unusual scenario to test]
4. Performance: [high volume scenario if applicable]

#### Configuration Testing

1. Open config: `/rlf config`
2. Navigate to [relevant section]
3. Toggle [feature setting]
4. Verify behavior changes appropriately
```

### Step 6: Documentation Updates

**Code documentation**:

- Add comments for complex logic
- Document event handlers
- Explain non-obvious decisions

**Wiki updates** (if applicable):

- Check if RPGLootFeed.wiki needs updates
- Note which wiki pages describe this feature
- Provide wiki update suggestions

**Config tooltips**:

- Ensure option descriptions are clear
- Add helpful examples or warnings

**Changelog**:

- Note changes for release notes
- Follow existing changelog format

### Step 7: Completion Summary

**Provide implementation summary**:

```markdown
## Implementation Complete: [Issue Title]

### Changes Made

- **File 1**: [What changed and why]
- **File 2**: [What changed and why]

### New Features/Behavior

- [User-visible change 1]
- [User-visible change 2]

### Configuration Options Added

- [Option 1]: [Purpose and default]
- [Option 2]: [Purpose and default]

### Key Decisions

- **Decision 1**: [Rationale]
- **Decision 2**: [Rationale]

### Deviations from Plan

- [If plan existed] Deviation 1: [Why and what was done instead]

### Testing Instructions

1. Build: `make dev` (or `make watch` for auto-rebuild)
2. Launch WoW and test:
   - **Test Mode**: `/rlf test` to preview
   - **Scenario 1**: [How to test]
   - **Scenario 2**: [How to test]
3. Configuration: `/rlf config` → [relevant section]
4. Key edge cases to verify:
   - Edge case 1
   - Edge case 2

### TOC Check Results

[Include output from `make toc_check`]

### Known Limitations

- [Any limitations or future enhancements]

### Wiki Updates Needed

- [ ] [Page 1]: [What needs updating]
- [ ] [Page 2]: [What needs updating]

### Next Steps

- [ ] Test in WoW client with `make watch` running
- [ ] Verify no LUA errors with BugGrabber/BugSack
- [ ] Test in solo, party, and raid contexts (if applicable)
- [ ] Check all acceptance criteria from issue
- [ ] Test configuration options
- [ ] Verify Test Mode preview works
- [ ] Update wiki if needed
- [ ] Commit with message: "Implements #123: [brief description]"
- [ ] Close issue if complete (or note remaining work)
```

### Step 8: Offer Follow-Up Actions

**Ask if user wants you to**:

- Create commit with proper message
- Update issue with implementation notes
- Generate PR description (if on feature branch)
- Update wiki documentation
- Create follow-up issues for discovered work
- Run additional validation checks

## Special Considerations

### Complex/Multi-Phase Issues

For high-complexity issues (per labels or plan):

- **Break into sub-phases**: Foundation → Config → Display → Polish
- **Checkpoint frequently**: Validate at end of each phase
- **Consider `/refactor`**: For large structural changes, delegate to refactoring workflow
- **Create sub-tasks**: If issue is too large, suggest breaking into multiple issues

### API Investigation During Implementation

If you discover API limitations or missing information:

- Check wow-ui-source for examples
- Document findings as you go
- Add notes to implementation summary
- Suggest updating issue with new insights
- Consider experimental implementation with fallback

### Blocked Work

If you hit a blocker during implementation:

- **Stop and document**: What's blocking, why, what's needed
- **Suggest alternatives**: Different approach? Defer part to future issue?
- **Update issue**: Add comment about blocker
- **Park progress**: Save partial work with blocker notes

## RPGLootFeed-Specific Patterns

### Feature Implementation Pattern

Most features follow this pattern:

1. **Add enums** (`utils/Enums.lua`) if needed
2. **Create Feature module** (`Features/[FeatureName]/[FeatureName].lua`):
   - Event registration
   - Event handlers
   - Message building
3. **Create Config module** (`config/Features/[FeatureName]Config.lua`):
   - Defaults
   - Options table
   - Handlers
4. **Update TOC** to include new files in correct order
5. **Update Test Mode** to include sample data

### Main vs. Party Frame

If feature affects loot display:

- Consider if it applies to Main frame only or both
- Check if Party frame needs separate config
- Test in both solo and group contexts

### Styling Consistency

Use existing styling patterns:

- Colors: Use `G_RLF.db.global.[feature].color` pattern
- Icons: Use `enableIcon` toggle pattern
- Text wrapping: Use `textWrapChar` pattern
- Follow `config/common/styling.base.lua` conventions

### Performance Considerations

For high-frequency features:

- Use AceBucket for event bucketing
- Consider throttling for rapid events
- Test with high loot volume
- Profile memory usage if applicable

## Workflow Integration

**Before `/implement`**:

- Optionally run `/plan #123` to create implementation roadmap
- Ensure issue is well-defined with clear acceptance criteria
- Have `make watch` ready for testing

**During `/implement`**:

- Use `/refactor` for complex structural changes
- Keep `make watch` running for rapid WoW client testing
- Check errors frequently with `get_errors()`
- Run `make toc_check` after file additions

**After `/implement`**:

- Test thoroughly with Test Mode and in-game
- Test configuration options
- Update wiki if needed
- Commit with proper issue reference
- Update issue and close if complete

## Issue Format Expectations

This workflow works best with well-structured issues:

**Good issue structure**:

- Clear problem statement or feature request
- Proposed solution or acceptance criteria
- Complexity/priority labels
- Related features or files mentioned
- Screenshots or examples if applicable
- Edge cases or considerations noted

**If issue is unclear**:

- Ask clarifying questions before starting
- Suggest updating issue with answers
- Consider brief planning phase to clarify approach

## Examples

**Simple implementation**:

```
/implement #42
```

→ Loads issue #42, checks for plan, implements directly

**With plan document**:

```
/implement #42
```

→ Finds `.github/plans/issue-42.md`, uses it as roadmap

**Iterative development with watch mode**:

```
[Terminal 1] make watch
[Terminal 2] /implement #42
[work on feature, test in WoW as it auto-rebuilds]
```

## Output Style

- ✅ **Action-oriented**: Focus on making progress
- ✅ **Explain decisions**: Share reasoning for technical choices
- ✅ **Show progress**: Update as you complete each step
- ✅ **Flag blockers early**: Don't struggle silently
- ✅ **Think incrementally**: Validate frequently, build in phases
- ✅ **Reference existing patterns**: "Following Currency.lua pattern..."
- ✅ **Consider both frames**: Main and Party implications
- ✅ **Test comprehensively**: Test Mode + in-game + edge cases

Your goal is to transform the issue requirements into working, tested, documented code that integrates seamlessly with RPGLootFeed's architecture and provides a great user experience.
