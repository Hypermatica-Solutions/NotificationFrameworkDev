# Notification Framework

A metadata-driven notification framework on the Salesforce platform. Administrators configure rules on any standard or custom object — the framework handles condition evaluation, recipient resolution, and multi-channel delivery (Email + In-App Bell in v1).

## Namespace

`hypnotif` — for internal (unmanaged) builds, remove the `namespace` field from `sfdx-project.json`.

## Prerequisites

- Salesforce CLI (`sf` v2.x or later)
- Visual Studio Code with Salesforce Extension Pack
- Node.js 18+ (for Jest LWC tests)
- A Developer Edition or scratch org with CDC enabled

## Project Structure

```
force-app/main/default/
├── classes/
│   ├── core/          # Framework engine — NotificationRouter, RuleCache, etc.
│   ├── interfaces/    # IConditionEvaluator, IRecipientResolver, IChannelHandler
│   ├── contexts/      # Context POJOs — EvaluationContext, NotificationPayload, etc.
│   ├── handlers/      # EmailChannelHandler, BellChannelHandler
│   ├── resolvers/     # OwnerResolver, QueueResolver, SpecificUsersResolver, etc.
│   └── tests/         # All *Test.cls files
├── triggers/          # NotificationEventTrigger, NotificationRuleTrigger
├── objects/           # Custom objects + Platform Event
├── customMetadata/    # Channel_Registry__mdt records
├── notificationTypes/ # Custom Notification Type for Bell channel
├── lwc/               # notificationRuleBuilder, notificationLogViewer
└── permissionsets/    # Notification_Admin, Notification_User
```

## Scratch Org Setup

```bash
# Create scratch org
sf org create scratch --definition-file config/project-scratch-def.json --alias notif-dev --duration-days 30

# Deploy source
sf project deploy start --source-dir force-app --target-org notif-dev

# Open org
sf org open --target-org notif-dev
```

## Running Tests

```bash
# Run all Apex tests
sf apex run test --target-org notif-dev --code-coverage --result-format human

# Run LWC Jest tests
npm run test:unit
```

## Development Phases

| Phase | Scope | Status |
|---|---|---|
| 1 | Project scaffold | In Progress |
| 2 | Data model (objects, fields, platform event) | Pending |
| 3 | Interfaces + context POJOs | Pending |
| 4 | Rule engine core (Router, Cache, Dispatcher) | Pending |
| 5 | Template engine + channel handlers | Pending |
| 6 | Validation trigger + admin utilities | Pending |
| 7 | LWC admin UI | Pending |
| 8 | Tests (unit, bulk, regression) | Pending |
| 9 | Package build + deployment | Pending |

## Full Development Guide

See [Docs/Development-Guide/notification-framework-dev-guide.md](Docs/Development-Guide/notification-framework-dev-guide.md).
