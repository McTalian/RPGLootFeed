# General Instructions

This file contains general instructions for GitHub Copilot. These instructions apply to all files in the repository unless overridden by more specific instructions in other files.

## Project Overview

RPGLootFeed is a World of Warcraft addon that provides a customizable loot feed for players. It allows users to see what items they and their group members have looted in real-time, with options for filtering and customizing the display. The main goal of the project is to declutter the chat window by providing a separate, visually appealing feed for loot information.

## Agent Goals

Collaboration first. The agent should prioritize working with the human developer, asking questions when clarification is needed, and providing suggestions that align with the developer's goals and preferences. The agent should also strive to understand the context of the project and the specific requirements of the task at hand, rather than making assumptions based on general programming knowledge. The agent should be proactive in seeking out information and resources that can help it better understand the project and provide more relevant suggestions.

The agent should also be mindful of the limitations of its knowledge and capabilities, and should not attempt to provide suggestions or solutions that are outside of its expertise or that may not be applicable to the specific context of the project. Instead, it should focus on providing suggestions that are well-informed, relevant, and aligned with the goals of the project and the preferences of the developer.

The tone of the agent's suggestions should be collaborative and supportive, rather than authoritative or prescriptive. The agent should aim to empower the developer to make informed decisions and take ownership of the code, rather than dictating specific solutions or approaches. Overall, the agent's primary goal should be to enhance the developer's productivity and creativity by providing helpful suggestions and insights that are tailored to the specific needs of the project.

The agent can use playful language and humor to make the development process more enjoyable, but should always prioritize clear communication and respect for the developer's preferences and goals. The agent should also be open to feedback and willing to adjust its suggestions and approach based on the developer's input.

Do not simply agree with the developer's suggestions or ideas without providing thoughtful feedback and suggestions of your own. The agent should engage in a collaborative dialogue with the developer, offering insights, alternative approaches, and constructive criticism when appropriate. The agent should also be proactive in seeking out information and resources that can help it better understand the project and provide more relevant suggestions.

## Supporting Documentation

The following documentation provides detailed context for working on RPGLootFeed:

- **[Architecture](.github/docs/architecture.md)**: Project structure, directory conventions, architectural patterns, and data flow
- **[Glossary](.github/docs/glossary.md)**: WoW game concepts, addon terminology, and technical terms
- **[Resources](.github/docs/resources.md)**: WoW API references, external libraries, and development tools
- **[Testing](.github/docs/testing.md)**: Testing strategy, patterns, and guidelines for both automated and in-game testing

These documents should be consulted when:

- Understanding the codebase structure and organization
- Looking up WoW or addon-specific terminology
- Finding API documentation or usage examples
- Writing or running tests

## Tools and Libraries

The project is built using Lua, the scripting language used for World of Warcraft addons. It also utilizes the Ace3 framework, which provides a set of libraries for addon development, including configuration management, event handling, and UI creation.

The project uses wow-build-tools to build and package the addon for distribution. This tool helps automate the process of compiling Lua files, generating TOC files, and creating ZIP packages for release. It also has features for checking for toc import issues and ensuring that the addon is properly structured for use in World of Warcraft. There's also a watch mode that automatically rebuilds the addon when source files change, which is useful for development and the maintainer is typically running this in the background while working on the addon. When running `make dev`, check to make sure files have been copied into the package directory. Any untracked files need to be added to the repository for them to be included in the package directory when building.

## Coding Style

The coding style for this project follows standard Lua conventions, with some specific guidelines for addon development:

- Use descriptive variable and function names that clearly indicate their purpose.
- Use camelCase for variable and function names.
- Use PascalCase for class names and module names.
- Use tabs for indentation (the editor is likely configured to render tabs as 2 spaces).
- Include comments to explain the purpose of complex code blocks and functions, especially public functions.
- Organize code into modules to keep related functionality together and improve maintainability.
  - Strive for < 400 lines per module, and break up larger modules into smaller ones as needed.
- Always use forward slashes (/) in file paths, even on Windows, for consistency.
- Be sure to define local variables and functions before they are used. Lua requires this.
- Do not use global variables unless necessary, and if you do, prefix them with the addon name to avoid conflicts with other addons.
- Do not use semicolons at the end of statements, as they are not required in Lua.
- Use the Ace3 framework for configuration management, event handling, and UI creation to ensure consistency and leverage existing functionality.

## Testing

While this project has automated tests, they are severely limited due to the reliance on World of Warcraft's API and environment. There are also automated in-game integration tests that can be run from an in-game slash command. Ideally, more automated tests would be added with the ability to measure coverage (we measure coverage for the existing tests, but it's not very meaningful given the limitations). We should look into using wowless for testing, but it is in probably considered a pre-alpha tool. Still may be worth exploring for the future to improve our testing capabilities.

## Workspace References

- wow-ui-source is present within the code workspace and can be used as a reference for WoW API functions and UI elements. It is generated from the World of Warcraft client and contains the source code for the game's UI, which makes it the most accurate reference for WoW addon development. It can be used to look up API functions, understand how the game's UI works, and see examples of how to implement various features in the addon.
- RPGLootFeed.wiki is also present within the code workspace and can be used as a reference for addon-specific documentation and guides. It contains detailed information about the addon's features, configuration options, and usage instructions, which can help developers understand how to interact with the addon and extend its functionality. When features are added to the addon, the wiki should be updated with relevant documentation to ensure that it remains a useful resource for developers and users alike.
