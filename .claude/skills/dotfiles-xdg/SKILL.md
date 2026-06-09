```markdown
# dotfiles-xdg Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill teaches development patterns and conventions for the `dotfiles-xdg` repository, a TypeScript-based project for managing dotfiles with XDG compatibility. It covers file organization, code style, commit conventions, and testing patterns to ensure consistency and maintainability across the codebase.

## Coding Conventions

### File Naming
- Use **camelCase** for file names.
  - Example: `userConfig.ts`, `fileManager.ts`

### Import Style
- Use **relative imports** for modules within the project.
  - Example:
    ```typescript
    import { getConfigPath } from './configUtils';
    ```

### Export Style
- Use **named exports** for all modules.
  - Example:
    ```typescript
    // configUtils.ts
    export function getConfigPath() { ... }
    export const DEFAULT_PATH = '/etc/xdg';
    ```

### Commit Messages
- Follow **Conventional Commits** with prefixes like `fix` and `feat`.
  - Example:
    ```
    feat: add support for custom config directory
    fix: resolve path issue on Windows
    ```

## Workflows

### Making a Code Change
**Trigger:** When you need to add a feature or fix a bug  
**Command:** `/code-change`

1. Create a new branch for your change.
2. Make code changes following the coding conventions.
3. Add or update tests as needed.
4. Commit using a conventional commit message.
5. Push your branch and open a pull request.

### Running Tests
**Trigger:** Before pushing or merging changes  
**Command:** `/run-tests`

1. Locate test files matching `*.test.*`.
2. Run the test command (framework unknown; typically `npm test` or similar).
3. Ensure all tests pass before proceeding.

### Reviewing Code Style
**Trigger:** Before submitting a pull request  
**Command:** `/check-style`

1. Check that all file names use camelCase.
2. Ensure imports are relative and exports are named.
3. Review commit messages for conventional format.

## Testing Patterns

- Test files follow the pattern `*.test.*` (e.g., `configUtils.test.ts`).
- The testing framework is not specified; use the project's test runner (e.g., `npm test`).
- Tests should cover new and changed functionality.

## Commands
| Command        | Purpose                                      |
|----------------|----------------------------------------------|
| /code-change   | Guide for making and submitting code changes |
| /run-tests     | Steps to run the test suite                  |
| /check-style   | Checklist for code style and conventions     |
```
