# skills-bank — public Claude Code plugins from 49x.ai

A [Claude Code marketplace](https://docs.claude.com/en/docs/claude-code/plugin-marketplaces)
that bundles plugins built and used at [49x.ai](https://49x.ai).

## Install

```
/plugin marketplace add 49x-ai/skills-bank
```

## Plugins

- **[cos-bot](plugins/cos-bot/)** — guided Telegram bot creation
  (drives BotFather, hands the token to `/telegram:configure`, walks
  the user to pairing) plus a one-shot installer for five
  Chief-of-Staff recipe commands (`/prep`, `/inbox-triage`,
  `/awaiting`, `/who`, `/catchup`).

  ```
  /plugin install cos-bot@49x-skills
  ```

More coming soon.
