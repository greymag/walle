# WallE

Android development tools

# Commands

## Localization

`l10n` - used for work with localization.

### Transfer strings

`walle l10n transfer -f{FROM_PROJECT_PATH} -t{TO_PROJECT_PATH}` - transfers missed string from one project to another.

### Export for translations

`walle l10n export -p{PROJECT_PATH} -l{LOCALE}` - exports only not translated keys with base values.