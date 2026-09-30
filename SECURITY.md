# Security policy

## Supported versions

Only the latest release gets fixes.

## Reporting a vulnerability

Report it privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Please do not open a public issue.

Include the macOS version, the Mole version (`mo --version`), the plugin version, and the steps that led to data being removed, a protected path being touched, or a command running without its yes.

You should get a first answer within 7 days.

## Scope

In scope: the skill asking too little or skipping a stage's yes, `scripts/guard.sh` letting a protected path through, the scripts writing outside `~/Library/Logs/diskdiet/`, the run folder and `~/.config/mole/`, and personal data in the repository.

Out of scope: bugs in Mole itself; report those to [Mole](https://github.com/tw93/Mole).
