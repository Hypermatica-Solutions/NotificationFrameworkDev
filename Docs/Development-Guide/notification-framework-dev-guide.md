# Notification Framework — Development Guide

**Version:** 1.0 (MVP)
**Audience:** Salesforce developers and QA engineers
**Scope:** Email + In-App (Bell) notifications, with extension points for SMS, Slack, Teams, and Webhook channels in later releases.
**Build target:** Managed package (ISV / AppExchange) — also usable internally without a namespace.

---

## Table of contents

1. [Overview](#1-overview)
2. [Architecture summary](#2-architecture-summary)
3. [Data model](#3-data-model)
4. [Project setup](#4-project-setup)
5. [Implementation roadmap](#5-implementation-roadmap)
6. [Component-by-component build guide](#6-component-by-component-build-guide)
7. [Coding standards](#7-coding-standards)
8. [Testing strategy](#8-testing-strategy)
9. [QA test plan](#9-qa-test-plan)
10. [Deployment and packaging](#10-deployment-and-packaging)
11. [Known limitations and edge cases](#11-known-limitations-and-edge-cases)
12. [Appendix](#12-appendix)

---

## 1. Overview

### 1.1 What we are building

A metadata-driven notification framework on the Salesforce platform that allows administrators to:

- Define a rule on any standard or custom object.
- Specify the condition under which a notification should fire (via a pluggable Apex evaluator).
- Specify one or more delivery channels (Email and Bell in v1).
- Specify recipients (Owner, Queue members, Specific Users, Field reference, or a custom Apex resolver).
- Track delivery status, retries, and failures.

### 1.2 Design goals

| Goal | How we achieve it |
|---|---|
| **Extensible** | Strategy-pattern interfaces for condition evaluation and channel delivery |
| **Async by default** | Change Data Capture triggers + Platform Events for delivery |
| **Packageable** | Namespaced, no hard-coded object references, post-install seed data |
| **Auditable** | Every send writes to `NotificationLog__c` |
| **Performant at scale** | Rule caching, `changedFields` filtering, bulk-safe Apex |
| **Secure** | FLS-aware merge fields, `WITH SECURITY_ENFORCED`, `stripInaccessible` |

### 1.3 What is *not* in scope for v1

- SMS, Slack, Teams, Webhook channels (architecture supports them; handlers ship in v2).
- Notification grouping / digests (planned for v2).
- End-user notification preferences (planned for v3).
- Mobile push (planned for v3).

### 1.4 Terminology

| Term | Meaning |
|---|---|
| **Rule** | A `NotificationRule__c` record defining what triggers a notification |
| **Evaluator** | An Apex class implementing `IConditionEvaluator` that decides if a rule matches |
| **Channel** | A delivery mechanism (Email, Bell, SMS, etc.) |
| **Handler** | An Apex class implementing `IChannelHandler` that performs delivery |
| **Resolver** | An Apex class implementing `IRecipientResolver` that returns user IDs |
| **Template** | A reusable subject/body with merge fields |
| **CDC** | Change Data Capture — Salesforce's platform-level change event stream |

---

## 2. Architecture summary

### 2.1 Runtime flow

```
┌─────────────────────────────────────────────────────────┐
│ Tier 1 — Source                                         │
│ Monitored object DML → CDC event (e.g. AccountChangeEvent) │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ Tier 2 — Rule engine                                    │
│ CDC trigger → NotificationRouter                        │
│   1. Load active rules for object (cached)              │
│   2. Filter by changedFields                            │
│   3. For each rule: IConditionEvaluator.evaluate(...)   │
│   4. If true: IRecipientResolver.resolve(...)           │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ Tier 3 — Async bus                                      │
│ Publish Notification_Event__e (Platform Event)          │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ Tier 4 — Channel handlers                               │
│ Trigger on Notification_Event__e                        │
│   - Look up handler from Channel_Registry__mdt          │
│   - IChannelHandler.send(payload)                       │
│     ├── EmailChannelHandler (SingleEmailMessage)        │
│     └── BellChannelHandler (Messaging.CustomNotification)│
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ Tier 5 — Audit                                          │
│ Write NotificationLog__c (Sent / Failed / Retry)        │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Key interfaces

Three Apex interfaces define every extension point:

```apex
global interface IConditionEvaluator {
    Boolean evaluate(EvaluationContext ctx);
}

global interface IRecipientResolver {
    Set<Id> resolve(RecipientContext ctx);
}

global interface IChannelHandler {
    DeliveryResult send(NotificationPayload payload);
}
```

Customers (and internal teams) extend the framework by implementing these interfaces — never by modifying core classes.

### 2.3 Why CDC and not Apex triggers?

| Concern | Apex triggers | CDC + Platform Events |
|---|---|---|
| Per-object setup | Trigger needed on each object | Enable CDC on object, framework subscribes |
| Sync vs async | Synchronous, blocks DML | Async by design, fires after commit |
| Changed fields detection | Manual via `Trigger.old` comparison | Native `changedFields` payload |
| Retry on failure | Manual implementation | Native (up to 4 automatic retries) |
| ISV deployment | Customer must add trigger per object | Framework subscribes centrally |

**Trade-off:** CDC must be enabled per-object in Setup and counts against the org's CDC entity limit (5 standard, more with add-on). Document this clearly in the install guide.

---

## 3. Data model

### 3.1 Object overview

| Object | API name | Purpose | Records owned by |
|---|---|---|---|
| Notification Rule | `NotificationRule__c` | Defines when a notification fires | Admin |
| Notification Channel Config | `NotificationChannel__c` | Links a rule to a channel + template | Admin |
| Notification Template | `NotificationTemplate__c` | Reusable subject + body with merge fields | Admin |
| Notification Log | `NotificationLog__c` | Audit trail of every delivery attempt | System |
| Channel Registry | `Channel_Registry__mdt` (CMDT) | Maps channel type → handler Apex class | Developer (packaged) |

### 3.2 NotificationRule__c

| Field API name | Type | Required | Purpose |
|---|---|---|---|
| `Name` | Auto Number (NR-{0000}) | Yes | Display name |
| `Rule_Label__c` | Text(120) | Yes | Human-readable name |
| `Object_API_Name__c` | Text(80) | Yes | API name of monitored object, e.g. `Account` or `pkg__Grant__c` |
| `Active__c` | Checkbox | Yes | Master on/off switch |
| `Priority__c` | Number(3,0) | No | Lower = evaluated first (default 100) |
| `Trigger_Event__c` | Picklist | Yes | Create / Update / Delete / Undelete |
| `Watched_Fields__c` | Long Text(4000) | No | Comma-separated field API names. Empty = any change. Used to pre-filter CDC events. |
| `Condition_Class__c` | Text(255) | Yes | Apex class name implementing `IConditionEvaluator`. Format: `[namespace.]ClassName` |
| `Condition_Config__c` | Long Text(32000) | No | JSON config passed to the evaluator at runtime |
| `Recipient_Strategy__c` | Picklist | Yes | Owner / Queue / SpecificUsers / FieldReference / ApexResolver |
| `Recipient_Config__c` | Long Text(4000) | No | JSON config for the resolver (user IDs, queue ID, field path, etc.) |
| `Recipient_Resolver_Class__c` | Text(255) | No | Required only when `Recipient_Strategy__c = ApexResolver` |
| `Cooldown_Minutes__c` | Number(5,0) | No | Suppress duplicate notifications for same Rule+Record within this window |
| `Description__c` | Long Text(4000) | No | Admin notes |

**Validation rules:**
- `Object_API_Name__c` must match a real SObject (validated via Apex trigger on the rule object).
- `Condition_Class__c` class must exist and implement the interface (validated on save via `Type.forName(...)`).
- If `Recipient_Strategy__c = ApexResolver`, `Recipient_Resolver_Class__c` must be populated.

### 3.3 NotificationChannel__c

Master-Detail to `NotificationRule__c`. One rule can fan out to multiple channels.

| Field API name | Type | Required | Purpose |
|---|---|---|---|
| `Name` | Auto Number (NC-{0000}) | Yes | Display name |
| `Rule__c` | Master-Detail(NotificationRule__c) | Yes | Parent rule |
| `Channel_Type__c` | Picklist | Yes | Email / Bell (v1). SMS / Slack / Teams / Webhook reserved for v2. |
| `Template__c` | Lookup(NotificationTemplate__c) | Yes | Template to render |
| `Active__c` | Checkbox | Yes | Per-channel toggle (default true) |
| `Channel_Config__c` | Long Text(4000) | No | JSON for channel-specific settings (e.g. `{"fromAddressId": "0D2..."}` for Email, `{"notificationTypeName": "Hypermatica_Alert"}` for Bell) |

### 3.4 NotificationTemplate__c

| Field API name | Type | Required | Purpose |
|---|---|---|---|
| `Name` | Text(120) | Yes | Display name |
| `Template_Key__c` | Text(80, unique) | Yes | Stable key for code references, e.g. `GRANT_AWARDED_EMAIL` |
| `Channel_Type__c` | Picklist | Yes | Must match channel type where used |
| `Subject__c` | Text(255) | No | Email subject / Bell title. Supports merge fields. |
| `Body__c` | Long Text(32000) | Yes | Email body / Bell body. Supports merge fields. |
| `Body_Is_HTML__c` | Checkbox | No | Email only — render as HTML |
| `Language__c` | Picklist | No | Reserved for v2 multi-language |

**Merge field syntax:** `{{Record.FieldApiName}}`, `{{Record.RelatedObject.Field}}`, `{{Recipient.FirstName}}`, `{{Rule.Rule_Label__c}}`. See [Appendix A](#a-merge-field-grammar).

### 3.5 NotificationLog__c

| Field API name | Type | Required | Purpose |
|---|---|---|---|
| `Name` | Auto Number (NL-{000000}) | Yes | Display name |
| `Rule__c` | Lookup(NotificationRule__c) | Yes | Source rule |
| `Channel__c` | Lookup(NotificationChannel__c) | Yes | Source channel config |
| `Record_Id__c` | Text(18, indexed) | Yes | The record that triggered the notification |
| `Recipient_User__c` | Lookup(User) | Yes | One log row per recipient |
| `Channel_Type__c` | Picklist | Yes | Denormalized for reporting |
| `Status__c` | Picklist | Yes | Queued / Sent / Failed / Suppressed |
| `Error_Message__c` | Long Text(4000) | No | Set when Status = Failed |
| `Retry_Count__c` | Number(3,0) | No | Default 0 |
| `Sent_At__c` | DateTime | No | Set when Status = Sent |
| `Suppression_Reason__c` | Picklist | No | Cooldown / FLS / NoRecipients / Inactive |
| `Cooldown_Key__c` | Text(255, indexed) | No | Composite key `RuleId|RecordId|ChannelId` — used by cooldown lookup |

**Retention:** Default 90 days. Provide a scheduled Apex job (`NotificationLogPurgeJob`) configurable via Custom Metadata.

### 3.6 Channel_Registry__mdt (Custom Metadata)

| Field API name | Type | Purpose |
|---|---|---|
| `Label` | Text | Email / Bell / SMS / etc. |
| `Channel_Type__c` | Text(40) | Matches `NotificationChannel__c.Channel_Type__c` picklist value |
| `Handler_Class__c` | Text(255) | Apex class implementing `IChannelHandler` |
| `Active__c` | Checkbox | Allows disabling a channel org-wide without code change |

**Seed records (shipped in package):**
- `Email` → `<namespace>.EmailChannelHandler`
- `Bell` → `<namespace>.BellChannelHandler`

### 3.7 Platform Event: Notification_Event__e

| Field API name | Type | Purpose |
|---|---|---|
| `Rule_Id__c` | Text(18) | NotificationRule__c ID |
| `Channel_Id__c` | Text(18) | NotificationChannel__c ID |
| `Record_Id__c` | Text(18) | Triggering record ID |
| `Recipient_Ids__c` | Long Text(131072) | Comma-separated user IDs (batch capable) |
| `Payload_JSON__c` | Long Text(131072) | Serialized merge context (record snapshot + extras) |
| `Replay_Token__c` | Text(80) | For idempotency / dedupe |

**Publish behavior:** `PublishAfterCommit` — we don't want phantom notifications if the originating transaction rolls back.

### 3.8 Entity relationship

```
NotificationRule__c (1) ───< (N) NotificationChannel__c
                                        │
                                        ▼
                              NotificationTemplate__c (lookup)

NotificationRule__c (1) ───< (N) NotificationLog__c
NotificationChannel__c (1) ──< (N) NotificationLog__c
User (1) ──────────────────< (N) NotificationLog__c

Channel_Registry__mdt — standalone, queried by Channel_Type__c
Notification_Event__e — transient platform event, not a stored record
```

---

## 4. Project setup

### 4.1 Prerequisites

- Salesforce CLI (`sf` v2.x or later)
- Visual Studio Code with Salesforce Extension Pack
- Node.js 18+ (for Jest LWC tests)
- A Developer Edition or Dev Hub org with **CDC enabled**
- For ISV builds: access to the Hypermatica Dev Hub and a packaging org

### 4.2 Repository structure

```
notification-framework/
├── force-app/main/default/
│   ├── classes/
│   │   ├── core/                       # Framework core (do not modify in extensions)
│   │   │   ├── NotificationRouter.cls
│   │   │   ├── NotificationRouter.cls-meta.xml
│   │   │   ├── NotificationDispatcher.cls
│   │   │   ├── RuleCache.cls
│   │   │   ├── TemplateEngine.cls
│   │   │   ├── CooldownManager.cls
│   │   │   ├── LogService.cls
│   │   │   └── ...
│   │   ├── interfaces/
│   │   │   ├── IConditionEvaluator.cls
│   │   │   ├── IRecipientResolver.cls
│   │   │   └── IChannelHandler.cls
│   │   ├── contexts/                   # Context POJOs passed to interfaces
│   │   │   ├── EvaluationContext.cls
│   │   │   ├── RecipientContext.cls
│   │   │   ├── NotificationPayload.cls
│   │   │   └── DeliveryResult.cls
│   │   ├── handlers/                   # Channel handlers
│   │   │   ├── EmailChannelHandler.cls
│   │   │   └── BellChannelHandler.cls
│   │   ├── resolvers/                  # Built-in recipient resolvers
│   │   │   ├── OwnerResolver.cls
│   │   │   ├── QueueResolver.cls
│   │   │   ├── SpecificUsersResolver.cls
│   │   │   └── FieldReferenceResolver.cls
│   │   └── tests/                      # All *Test.cls
│   ├── triggers/
│   │   ├── NotificationEventTrigger.trigger
│   │   └── NotificationRuleTrigger.trigger  # validates on save
│   ├── objects/
│   │   ├── NotificationRule__c/
│   │   ├── NotificationChannel__c/
│   │   ├── NotificationTemplate__c/
│   │   ├── NotificationLog__c/
│   │   └── Notification_Event__e/
│   ├── customMetadata/
│   │   ├── Channel_Registry.Email.md-meta.xml
│   │   └── Channel_Registry.Bell.md-meta.xml
│   ├── notificationTypes/              # Custom Notification Type for Bell
│   │   └── Hypermatica_Alert.notiftype-meta.xml
│   ├── lwc/
│   │   ├── notificationRuleBuilder/    # Admin UI (Phase 4)
│   │   └── notificationLogViewer/
│   └── permissionsets/
│       ├── Notification_Admin.permissionset-meta.xml
│       └── Notification_User.permissionset-meta.xml
├── config/
│   └── project-scratch-def.json
├── scripts/
│   ├── apex/
│   └── soql/
├── sfdx-project.json
└── README.md
```

### 4.3 sfdx-project.json (ISV configuration)

```json
{
  "packageDirectories": [
    {
      "path": "force-app",
      "default": true,
      "package": "Hypermatica Notifications",
      "versionName": "v1.0",
      "versionNumber": "1.0.0.NEXT",
      "definitionFile": "config/project-scratch-def.json"
    }
  ],
  "namespace": "hypnotif",
  "sfdcLoginUrl": "https://login.salesforce.com",
  "sourceApiVersion": "62.0"
}
```

> **Internal builds:** remove the `namespace` field. All API names referenced in this guide should drop the `hypnotif__` prefix accordingly.

### 4.4 Scratch org definition

`config/project-scratch-def.json`:

```json
{
  "orgName": "Notification Framework Dev",
  "edition": "Enterprise",
  "features": ["EnableSetPasswordInApi"],
  "settings": {
    "lightningExperienceSettings": { "enableS1DesktopEnabled": true },
    "mobileSettings": { "enableS1EncryptedStoragePref2": false }
  }
}
```

### 4.5 Branching strategy

- `main` — production-ready, tagged releases (`v1.0.0`, `v1.0.1`, ...)
- `develop` — integration branch
- `feature/<jira-id>-short-name` — per ticket
- `release/v1.x` — release stabilization

PRs require: 1 reviewer approval, all tests passing, 90%+ code coverage on changed lines.

---

## 5. Implementation roadmap

The build is sequenced so each phase produces something testable. Estimated effort assumes 2 mid-level Salesforce developers + 1 senior developer.

### Phase 1 — Foundation (Week 1)
| Ticket | Component | Owner |
|---|---|---|
| NF-001 | Create all custom objects, fields, picklists | Dev A |
| NF-002 | Create platform event `Notification_Event__e` | Dev A |
| NF-003 | Create `Channel_Registry__mdt` + seed records | Dev A |
| NF-004 | Create permission sets | Dev A |
| NF-005 | Define interfaces (`IConditionEvaluator`, `IRecipientResolver`, `IChannelHandler`) | Senior Dev |
| NF-006 | Define context POJOs | Senior Dev |

**Exit criteria:** All metadata deploys cleanly to scratch org. Permission sets assign without errors.

### Phase 2 — Rule engine core (Week 2)
| Ticket | Component | Owner |
|---|---|---|
| NF-010 | `RuleCache` — Platform Cache backed rule loader | Senior Dev |
| NF-011 | `NotificationRouter` — orchestrates evaluation pipeline | Senior Dev |
| NF-012 | `NotificationDispatcher` — invoked by CDC triggers | Dev B |
| NF-013 | `CooldownManager` — suppress duplicates | Dev B |
| NF-014 | `LogService` — wraps `NotificationLog__c` writes | Dev A |

**Exit criteria:** Unit tests cover all branches. Router can be invoked directly in anonymous Apex and writes Log records.

### Phase 3 — Channel handlers (Week 3)
| Ticket | Component | Owner |
|---|---|---|
| NF-020 | `TemplateEngine` — merge field resolution with FLS | Senior Dev |
| NF-021 | `EmailChannelHandler` | Dev A |
| NF-022 | `BellChannelHandler` + Custom Notification Type | Dev B |
| NF-023 | `Notification_Event__e` trigger + routing to handlers | Dev B |
| NF-024 | Built-in recipient resolvers (Owner, Queue, SpecificUsers, FieldReference) | Dev A |

**Exit criteria:** End-to-end test — manually publish a `Notification_Event__e`, confirm Email + Bell delivery and Log records.

### Phase 4 — Integration & polish (Week 4)
| Ticket | Component | Owner |
|---|---|---|
| NF-030 | CDC trigger template + helper utility | Senior Dev |
| NF-031 | Rule validation trigger (`NotificationRuleTrigger`) | Dev A |
| NF-032 | Lightning admin app + tabs | Dev B |
| NF-033 | `notificationRuleBuilder` LWC for rule creation | Dev B |
| NF-034 | `notificationLogViewer` LWC for log inspection | Dev A |
| NF-035 | `NotificationLogPurgeJob` scheduled Apex | Dev A |

**Exit criteria:** Admin can create a rule end-to-end from UI, fire the rule, and view logs.

### Phase 5 — Hardening (Week 5)
| Ticket | Component | Owner |
|---|---|---|
| NF-040 | Bulk testing (200+ records) and performance tuning | All |
| NF-041 | Security review prep (PMD, Checkmarx, FLS audit) | Senior Dev |
| NF-042 | Documentation, install guide, sample rules | All |
| NF-043 | Beta package version, install in test sandbox | Senior Dev |

**Exit criteria:** Package installs in a clean sandbox. ISV security review checklist passes.

---

## 6. Component-by-component build guide

### 6.1 Interfaces

#### IConditionEvaluator

```apex
global interface IConditionEvaluator {
    /**
     * Evaluates whether a rule's condition is met for a given record change.
     *
     * @param ctx EvaluationContext containing the new record, old record,
     *            changed fields, the rule, and parsed condition config.
     * @return true if the notification should fire.
     *
     * Implementations MUST be:
     *   - Stateless (no instance fields holding cross-call data)
     *   - Bulk-safe (called once per record per rule; do not query inside)
     *   - FLS-aware if reading fields not in newRecord
     */
    Boolean evaluate(EvaluationContext ctx);
}
```

#### IRecipientResolver

```apex
global interface IRecipientResolver {
    /**
     * Returns the set of User IDs who should receive the notification.
     *
     * @param ctx RecipientContext with the record, rule, and parsed recipient config.
     * @return Set of User IDs. Empty set is valid (results in Suppressed log).
     *
     * Implementations MUST:
     *   - Return only active User IDs
     *   - Respect any "exclude self" logic if configured
     *   - Be bulk-callable (caller batches; resolver may be invoked per record)
     */
    Set<Id> resolve(RecipientContext ctx);
}
```

#### IChannelHandler

```apex
global interface IChannelHandler {
    /**
     * Delivers a notification through this channel.
     *
     * @param payload NotificationPayload with rendered subject/body, recipients, config.
     * @return DeliveryResult with per-recipient status. The framework writes logs from this.
     *
     * Implementations MUST:
     *   - Be callable from a Platform Event trigger (no @future-only operations)
     *   - Handle partial failure (some recipients succeed, some fail)
     *   - Not throw — return DeliveryResult with errors instead
     *   - Respect governor limits (caller may invoke for multiple events in one transaction)
     */
    DeliveryResult send(NotificationPayload payload);
}
```

### 6.2 Context POJOs

```apex
global class EvaluationContext {
    global SObject newRecord;
    global SObject oldRecord;       // null on insert
    global Set<String> changedFields;
    global NotificationRule__c rule;
    global Map<String, Object> config;  // parsed Condition_Config__c
}

global class RecipientContext {
    global SObject record;
    global NotificationRule__c rule;
    global Map<String, Object> config;  // parsed Recipient_Config__c
}

global class NotificationPayload {
    global Id ruleId;
    global Id channelId;
    global Id recordId;
    global Set<Id> recipientIds;
    global String subject;       // pre-rendered
    global String body;          // pre-rendered
    global Boolean bodyIsHtml;
    global Map<String, Object> channelConfig;
    global Map<String, Object> mergeContext;  // for handler-specific re-rendering if needed
}

global class DeliveryResult {
    global Map<Id, RecipientResult> resultsByRecipient = new Map<Id, RecipientResult>();

    global class RecipientResult {
        global Boolean success;
        global String errorMessage;
        global DateTime sentAt;
    }
}
```

### 6.3 RuleCache

Rules are read every time a CDC event arrives. SOQL per event is unacceptable at scale. Cache in `Cache.OrgPartition`.

**Key responsibilities:**
- Load all active rules grouped by `Object_API_Name__c`.
- Cache for 5 minutes (TTL).
- Invalidate on `NotificationRule__c` insert/update/delete via the rule trigger.

**Skeleton:**

```apex
public with sharing class RuleCache {
    private static final String PARTITION = 'local.NotifFramework';
    private static final String CACHE_KEY = 'ActiveRulesByObject';
    private static final Integer TTL_SECONDS = 300;

    public static List<NotificationRule__c> getRulesForObject(String objectApiName) {
        Map<String, List<NotificationRule__c>> all = getAllRules();
        return all.containsKey(objectApiName) ? all.get(objectApiName) : new List<NotificationRule__c>();
    }

    public static void invalidate() {
        Cache.Org.getPartition(PARTITION).remove(CACHE_KEY);
    }

    private static Map<String, List<NotificationRule__c>> getAllRules() {
        Cache.OrgPartition partition = Cache.Org.getPartition(PARTITION);
        Object cached = partition.get(CACHE_KEY);
        if (cached != null) return (Map<String, List<NotificationRule__c>>) cached;

        Map<String, List<NotificationRule__c>> result = new Map<String, List<NotificationRule__c>>();
        for (NotificationRule__c r : [
            SELECT Id, Rule_Label__c, Object_API_Name__c, Trigger_Event__c, Watched_Fields__c,
                   Condition_Class__c, Condition_Config__c, Recipient_Strategy__c,
                   Recipient_Config__c, Recipient_Resolver_Class__c, Cooldown_Minutes__c, Priority__c,
                   (SELECT Id, Channel_Type__c, Template__c, Channel_Config__c, Active__c
                    FROM NotificationChannels__r WHERE Active__c = true)
            FROM NotificationRule__c
            WHERE Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY Priority__c ASC NULLS LAST
        ]) {
            if (!result.containsKey(r.Object_API_Name__c)) {
                result.put(r.Object_API_Name__c, new List<NotificationRule__c>());
            }
            result.get(r.Object_API_Name__c).add(r);
        }
        partition.put(CACHE_KEY, result, TTL_SECONDS);
        return result;
    }
}
```

**Gotcha:** `Cache.OrgPartition` requires a partition named `NotifFramework` to exist in the org. Ship one in the package and document setup for unmanaged installs.

### 6.4 NotificationDispatcher

Single entry point invoked by CDC triggers. One thin trigger per monitored object:

```apex
// Example CDC trigger on AccountChangeEvent
trigger AccountChangeEventTrigger on AccountChangeEvent (after insert) {
    hypnotif.NotificationDispatcher.dispatch(Trigger.new, 'Account');
}
```

**Dispatcher implementation:**

```apex
global with sharing class NotificationDispatcher {

    global static void dispatch(List<SObject> changeEvents, String objectApiName) {
        if (changeEvents == null || changeEvents.isEmpty()) return;

        List<NotificationRule__c> rules = RuleCache.getRulesForObject(objectApiName);
        if (rules.isEmpty()) return;

        // 1. Collect record IDs we'll need to query for full records
        Set<Id> recordIds = new Set<Id>();
        Map<Id, Set<String>> changedFieldsByRecordId = new Map<Id, Set<String>>();
        Map<Id, String> changeTypeByRecordId = new Map<Id, String>();

        for (SObject evt : changeEvents) {
            EventBus.ChangeEventHeader header =
                (EventBus.ChangeEventHeader) evt.getSObject('ChangeEventHeader');
            String changeType = header.changetype;  // CREATE, UPDATE, DELETE, UNDELETE
            List<String> changedFields = header.changedFields;
            for (String rid : header.recordIds) {
                recordIds.add((Id) rid);
                changedFieldsByRecordId.put((Id) rid, new Set<String>(changedFields));
                changeTypeByRecordId.put((Id) rid, changeType);
            }
        }

        // 2. Bulk re-query the full records (CDC payload is partial)
        Map<Id, SObject> records = RecordQueryService.queryByIds(objectApiName, recordIds);

        // 3. Hand off to the router
        NotificationRouter.route(rules, records, changedFieldsByRecordId, changeTypeByRecordId);
    }
}
```

**Why re-query?** CDC events contain only changed fields. Evaluators almost always need other fields (Owner, status, related parent). Bulk-query once at the top — never inside the rule loop.

### 6.5 NotificationRouter

The orchestrator. For each (rule, record) pair:

1. Check `Trigger_Event__c` matches the change type.
2. Check `Watched_Fields__c` intersects `changedFields` (skip if no overlap).
3. Instantiate and call the `IConditionEvaluator`.
4. If true, call `CooldownManager.isSuppressed(...)` — skip + log if so.
5. Instantiate and call the `IRecipientResolver`.
6. For each channel on the rule: render template via `TemplateEngine`, publish `Notification_Event__e`.

**Skeleton:**

```apex
public with sharing class NotificationRouter {

    public static void route(List<NotificationRule__c> rules,
                             Map<Id, SObject> records,
                             Map<Id, Set<String>> changedFieldsByRecordId,
                             Map<Id, String> changeTypeByRecordId) {

        List<Notification_Event__e> eventsToPublish = new List<Notification_Event__e>();

        for (Id recordId : records.keySet()) {
            SObject record = records.get(recordId);
            String changeType = changeTypeByRecordId.get(recordId);
            Set<String> changedFields = changedFieldsByRecordId.get(recordId);

            for (NotificationRule__c rule : rules) {
                if (!triggerEventMatches(rule.Trigger_Event__c, changeType)) continue;
                if (!watchedFieldsMatch(rule.Watched_Fields__c, changedFields)) continue;

                EvaluationContext evalCtx = buildEvalContext(rule, record, changedFields);
                IConditionEvaluator evaluator = instantiateEvaluator(rule.Condition_Class__c);
                if (evaluator == null) {
                    LogService.logError(rule.Id, null, recordId, null,
                        'Evaluator class not found: ' + rule.Condition_Class__c);
                    continue;
                }

                Boolean matched;
                try {
                    matched = evaluator.evaluate(evalCtx);
                } catch (Exception e) {
                    LogService.logError(rule.Id, null, recordId, null,
                        'Evaluator threw: ' + e.getMessage());
                    continue;
                }
                if (!matched) continue;

                Set<Id> recipients = resolveRecipients(rule, record);
                if (recipients.isEmpty()) {
                    LogService.logSuppressed(rule.Id, null, recordId, 'NoRecipients');
                    continue;
                }

                for (NotificationChannel__c channel : rule.NotificationChannels__r) {
                    if (CooldownManager.isSuppressed(rule.Id, recordId, channel.Id, rule.Cooldown_Minutes__c)) {
                        LogService.logSuppressed(rule.Id, channel.Id, recordId, 'Cooldown');
                        continue;
                    }

                    NotificationPayload payload = TemplateEngine.render(rule, channel, record, recipients);
                    eventsToPublish.add(buildEvent(rule, channel, recordId, recipients, payload));
                }
            }
        }

        if (!eventsToPublish.isEmpty()) {
            publishEvents(eventsToPublish);
        }
    }

    // ... helper methods omitted for brevity — see full source
}
```

**Critical:** `instantiateEvaluator` uses `Type.forName(...)`. Cache `Type` instances in a static map keyed by class name to avoid repeated reflection.

### 6.6 TemplateEngine

Resolves merge fields like `{{Record.Account.Name}}` against the record. Critical to get FLS right — security review will fail otherwise.

**Algorithm:**

1. Parse the template for `{{...}}` tokens once at startup, cache the parsed AST per template ID.
2. For each token, traverse the path on the SObject:
   - `Record.Field` → `record.get('Field')`
   - `Record.Parent.Field` → requires the parent to be on the record (caller is responsible for selecting it; document this).
   - `Recipient.Field` → fetched from a `Map<Id, User>` passed in.
   - `Rule.Field` → from the rule SObject.
3. Wrap field access with `Schema.SObjectField.getDescribe().isAccessible()` check; if the running user lacks FLS, render empty string and log a warning.
4. HTML-escape output by default; allow `{{!RawHtml}}` syntax for trusted fields.

**Do not** use `String.format` with positional placeholders — too fragile for admin-authored templates.

### 6.7 EmailChannelHandler

```apex
global with sharing class EmailChannelHandler implements IChannelHandler {

    global DeliveryResult send(NotificationPayload payload) {
        DeliveryResult result = new DeliveryResult();

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Id userId : payload.recipientIds) {
            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setTargetObjectId(userId);
            msg.setSaveAsActivity(false);
            msg.setSubject(payload.subject);
            if (payload.bodyIsHtml) {
                msg.setHtmlBody(payload.body);
            } else {
                msg.setPlainTextBody(payload.body);
            }
            // Optional: org-wide email address from channel config
            String fromAddressId = (String) payload.channelConfig.get('fromAddressId');
            if (String.isNotBlank(fromAddressId)) {
                msg.setOrgWideEmailAddressId(fromAddressId);
            }
            messages.add(msg);
        }

        if (messages.isEmpty()) return result;

        List<Messaging.SendEmailResult> sendResults = Messaging.sendEmail(messages, false);
        Integer i = 0;
        for (Id userId : payload.recipientIds) {
            Messaging.SendEmailResult ser = sendResults[i++];
            DeliveryResult.RecipientResult rr = new DeliveryResult.RecipientResult();
            rr.success = ser.isSuccess();
            rr.sentAt = DateTime.now();
            if (!ser.isSuccess() && !ser.getErrors().isEmpty()) {
                rr.errorMessage = ser.getErrors()[0].getMessage();
            }
            result.resultsByRecipient.put(userId, rr);
        }
        return result;
    }
}
```

**Gotchas:**
- `Messaging.sendEmail` consumes daily email limit (5,000/day for licensed users; 10/day for non-targeted addresses). Document this in the install guide.
- `setSaveAsActivity(false)` avoids polluting the user's activity history.
- Pass `false` as the second arg to `sendEmail` — partial success mode — so one bad recipient doesn't kill the batch.

### 6.8 BellChannelHandler

Bell notifications use `Messaging.CustomNotification`. The Custom Notification Type must exist in the org — ship one called `Hypermatica_Alert` (or `Notification_Alert` for unmanaged installs) in the package.

```apex
global with sharing class BellChannelHandler implements IChannelHandler {

    global DeliveryResult send(NotificationPayload payload) {
        DeliveryResult result = new DeliveryResult();

        String typeName = (String) payload.channelConfig.get('notificationTypeName');
        if (String.isBlank(typeName)) typeName = 'Hypermatica_Alert';

        Id typeId = getNotificationTypeId(typeName);
        if (typeId == null) {
            for (Id userId : payload.recipientIds) {
                DeliveryResult.RecipientResult rr = new DeliveryResult.RecipientResult();
                rr.success = false;
                rr.errorMessage = 'Custom Notification Type not found: ' + typeName;
                result.resultsByRecipient.put(userId, rr);
            }
            return result;
        }

        Messaging.CustomNotification notif = new Messaging.CustomNotification();
        notif.setNotificationTypeId(typeId);
        notif.setTitle(payload.subject);
        notif.setBody(stripHtml(payload.body));  // Bell doesn't render HTML
        notif.setTargetId(payload.recordId);     // makes the bell clickable to the record

        try {
            notif.send(payload.recipientIds);
            for (Id userId : payload.recipientIds) {
                DeliveryResult.RecipientResult rr = new DeliveryResult.RecipientResult();
                rr.success = true;
                rr.sentAt = DateTime.now();
                result.resultsByRecipient.put(userId, rr);
            }
        } catch (Exception e) {
            for (Id userId : payload.recipientIds) {
                DeliveryResult.RecipientResult rr = new DeliveryResult.RecipientResult();
                rr.success = false;
                rr.errorMessage = e.getMessage();
                result.resultsByRecipient.put(userId, rr);
            }
        }
        return result;
    }

    private Id getNotificationTypeId(String developerName) {
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType
            WHERE DeveloperName = :developerName LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }
}
```

**Gotchas:**
- `Messaging.CustomNotification.send()` has a hard limit of 500 recipients per call. Batch if `recipientIds.size() > 500`.
- The notification type ID lookup costs a SOQL query per send. Cache it in a static map.
- `setTargetId` must be a record the recipient has read access to, or the notification will deliver but the click will 404.

### 6.9 Notification_Event__e trigger

```apex
trigger NotificationEventTrigger on Notification_Event__e (after insert) {
    NotificationEventHandler.handle(Trigger.new);
}
```

The handler reads `Channel_Registry__mdt`, instantiates the right channel handler, and calls it. Logs are written here, not inside handlers — keeps handlers free of DML so they can be unit-tested without `Test.setMock`.

### 6.10 Sample IConditionEvaluator implementations

Ship a few common evaluators in the package as reference implementations:

#### FieldEqualsEvaluator

```apex
/**
 * Fires when a field equals a configured value.
 * Config JSON: {"field": "Status__c", "value": "Awarded"}
 */
global with sharing class FieldEqualsEvaluator implements IConditionEvaluator {
    global Boolean evaluate(EvaluationContext ctx) {
        String field = (String) ctx.config.get('field');
        Object expected = ctx.config.get('value');
        if (String.isBlank(field)) return false;
        Object actual = ctx.newRecord.get(field);
        return actual == expected;
    }
}
```

#### FieldChangedEvaluator

```apex
/**
 * Fires when a field changed to a specific value (or any value if "value" omitted).
 * Config JSON: {"field": "Status__c", "value": "Awarded"}
 */
global with sharing class FieldChangedEvaluator implements IConditionEvaluator {
    global Boolean evaluate(EvaluationContext ctx) {
        String field = (String) ctx.config.get('field');
        if (String.isBlank(field) || !ctx.changedFields.contains(field)) return false;
        if (!ctx.config.containsKey('value')) return true;  // any change
        return ctx.newRecord.get(field) == ctx.config.get('value');
    }
}
```

#### FormulaEvaluator

```apex
/**
 * Fires when a formula field on the record evaluates to true.
 * Config JSON: {"formulaField": "Should_Notify__c"}
 * Lets admins build conditions in formula syntax without writing Apex.
 */
global with sharing class FormulaEvaluator implements IConditionEvaluator {
    global Boolean evaluate(EvaluationContext ctx) {
        String field = (String) ctx.config.get('formulaField');
        if (String.isBlank(field)) return false;
        Object value = ctx.newRecord.get(field);
        return value == true;
    }
}
```

Document these in the admin guide as "out-of-the-box evaluators" so admins can configure most rules without writing code.

---

## 7. Coding standards

### 7.1 Apex conventions

- **Sharing:** `with sharing` by default on every class. Use `without sharing` only when system-context is required (e.g. log writes by an unprivileged user) and document why.
- **Naming:** `PascalCase` for classes, `camelCase` for methods/variables, `SCREAMING_SNAKE_CASE` for constants.
- **Bulk safety:** No SOQL/DML inside `for` loops. Ever. PR will be rejected.
- **No hard-coded IDs.** Use `Schema.SObjectType.X.getKeyPrefix()` or query by DeveloperName.
- **No `System.debug` in committed code** except inside `if (Test.isRunningTest())` blocks or behind a debug flag.
- **One trigger per object.** All logic in handler classes.
- **`Database.X` with allOrNone=false** for any bulk DML where partial success is acceptable. Log all errors.

### 7.2 Security

- Every SOQL must use `WITH SECURITY_ENFORCED` or call `Security.stripInaccessible` on results.
- Every dynamic SOQL must use `String.escapeSingleQuotes()` on any string concatenated into the query.
- Any class exposed via `@AuraEnabled`, `webservice`, or `global` must be reviewed by the senior dev before merge.
- Never store credentials in code or custom settings. Use Named Credentials.
- Never log PII to `NotificationLog__c`. The log captures recipient ID and rule context, not the full notification body.

### 7.3 API design for ISV

- All public classes/methods that customers may extend or invoke = `global`.
- Internal helpers = `public` or `private`.
- Once a `global` member ships in a managed package version, **it cannot be removed**. Be conservative.
- Annotate `global` members with `@deprecated` to remove them in future versions (they remain callable but hidden).

### 7.4 Naming for namespaced builds

| Element | ISV (namespaced) | Internal (unmanaged) |
|---|---|---|
| Object | `hypnotif__NotificationRule__c` | `NotificationRule__c` |
| Class reference | `hypnotif.NotificationRouter` | `NotificationRouter` |
| Evaluator config | `hypnotif.FieldEqualsEvaluator` | `FieldEqualsEvaluator` |

**Rule:** Never hard-code the namespace prefix in Apex. Use `Schema.getGlobalDescribe()` and `Type.forName(namespace, className)` to handle both modes.

---

## 8. Testing strategy

### 8.1 Coverage targets

- Overall: 90%+ (managed package requirement is 75% but we target higher).
- Each new class: 85%+ on lines, 100% on `global` members.
- Every interface implementation must have a test stub that proves the interface contract.

### 8.2 Test layering

| Layer | What it tests | Tooling |
|---|---|---|
| **Unit** | Single class in isolation, mocked dependencies | Apex test framework + `Stub API` |
| **Integration** | Router → handler → log, no external callouts | Apex test framework |
| **End-to-end** | DML → CDC → notification | Manual + scripted scratch org tests |
| **LWC** | Admin UI components | Jest |
| **Bulk** | 200-record DML hits all governor limits | Apex test framework with `Test.startTest`/`stopTest` |

### 8.3 Mocking the channels

Channel handlers do real work (`Messaging.sendEmail`, `Messaging.CustomNotification.send`). In tests we want to verify the framework *invoked them correctly* without actually sending. Use the Stub API:

```apex
@IsTest
static void router_publishesEventForMatchedRule() {
    // Arrange
    NotificationRule__c rule = TestDataFactory.createRule('Account', 'FieldEqualsEvaluator',
        '{"field":"Type","value":"Customer"}');
    Account a = new Account(Name = 'Acme', Type = 'Customer');
    insert a;

    // Act
    Test.startTest();
    NotificationDispatcher.dispatch(
        TestDataFactory.fakeAccountChangeEvent(a.Id, 'CREATE', new List<String>{'Type'}),
        'Account'
    );
    Test.stopTest();

    // Assert
    List<Notification_Event__e> published = TestUtil.capturedEvents();
    System.assertEquals(1, published.size(), 'One event should be published');
    System.assertEquals(rule.Id, published[0].Rule_Id__c);
}
```

### 8.4 CDC in tests

CDC events don't fire in test context by default. Options:

1. **Test the dispatcher directly** — pass in a fake CDC event SObject. Easier and isolates the unit. **Preferred.**
2. **Use `Test.enableChangeDataCapture()`** + actual DML if you must test the trigger wiring end-to-end. Slower.

Provide a `TestDataFactory.fakeChangeEvent(...)` helper that builds a representative `AccountChangeEvent` SObject for testing.

### 8.5 Platform Event delivery in tests

`Test.getEventBus().deliver()` forces synchronous delivery inside a test. Use it before asserting on side effects of the event trigger.

```apex
Test.startTest();
EventBus.publish(new Notification_Event__e(...));
Test.getEventBus().deliver();
Test.stopTest();

List<NotificationLog__c> logs = [SELECT Id, Status__c FROM NotificationLog__c];
System.assertEquals(1, logs.size());
```

---

## 9. QA test plan

### 9.1 Functional test scenarios

| # | Scenario | Steps | Expected |
|---|---|---|---|
| F-01 | Simple field-equals rule fires | Create rule on Account where Type=Customer, channel=Email. Insert Account with Type=Customer. | One Email log row with Status=Sent within 1 minute |
| F-02 | Rule does not fire when condition false | Same rule. Insert Account with Type=Prospect. | No log rows |
| F-03 | Inactive rule does not fire | Deactivate rule F-01. Repeat insert. | No log rows |
| F-04 | Watched fields filter works | Rule with `Watched_Fields__c = Status__c`. Update Account `Name` only. | No log rows |
| F-05 | Multi-channel fan-out | Rule with Email + Bell channel. Trigger condition. | Two log rows (one per channel) |
| F-06 | Cooldown suppresses duplicate | Rule with `Cooldown_Minutes__c = 60`. Trigger same record twice. | First sends, second logs with Suppression_Reason=Cooldown |
| F-07 | Owner resolver returns record owner | Rule with Recipient_Strategy=Owner. Trigger on record owned by User X. | Log row with Recipient_User=X |
| F-08 | Queue resolver returns queue members | Rule with Recipient_Strategy=Queue, config={"queueId":"..."}. Trigger. | One log per active queue member |
| F-09 | Empty recipients suppresses | Rule with SpecificUsers config pointing to inactive user only. | Log with Suppression_Reason=NoRecipients |
| F-10 | Evaluator class missing logs error | Set `Condition_Class__c` to nonexistent class. Trigger. | Log with Error_Message indicating class not found |
| F-11 | Evaluator throws exception | Use an evaluator that throws. Trigger. | Log with error, no notification sent, no transaction failure |
| F-12 | Bell notification appears in bell tray | Trigger Bell rule against User X. | X sees notification in bell icon within 30 seconds |
| F-13 | Email body merge fields render | Template body: `Hello {{Recipient.FirstName}}, account {{Record.Name}} updated.` | Email body shows actual values |
| F-14 | Merge field for missing FLS renders empty | Recipient lacks FLS on a merged field. | Field renders as empty string, no exception |
| F-15 | Multiple rules on same object both fire | Two rules with different conditions both true. | Both fire independently |

### 9.2 Bulk and performance scenarios

| # | Scenario | Steps | Expected |
|---|---|---|---|
| B-01 | 200-record bulk insert | Insert 200 Accounts matching the rule in one DML. | All 200 trigger notifications. No governor limit exceptions. |
| B-02 | 10,000-record async batch | Apex batch updates 10K records matching a rule. | All 10K trigger notifications within reasonable time (depends on email/PE limits). No errors. |
| B-03 | 50 rules on same object | Create 50 active rules on Account. Insert 200 Accounts. | All 200×50 evaluations complete. No CPU timeout. |
| B-04 | Recipient resolver returns 500+ users | Queue with 600 members. Trigger Bell rule. | Two `CustomNotification.send` calls (batched at 500). All recipients receive. |
| B-05 | Cache invalidation on rule update | Update a rule's condition. Trigger within 1 minute. | New condition applies (cache must invalidate). |

### 9.3 Negative and edge cases

| # | Scenario | Expected |
|---|---|---|
| N-01 | Rule on non-CDC-enabled object | Validation error on rule save, OR clear log warning at runtime |
| N-02 | Template references non-existent field | Render empty + log warning, no exception |
| N-03 | Recipient resolver returns same user 5 times | One log row per unique user (dedupe) |
| N-04 | Daily email limit exceeded | Logs failures gracefully, does not throw |
| N-05 | Bell notification with 600 recipients | Batched into 2 sends of 500+100 |
| N-06 | Record deleted before notification sent | Notification still fires with last-known data; Bell may 404 on click |
| N-07 | User who triggered the change is the recipient | Configurable: include or exclude self (default exclude) |
| N-08 | Rule's monitored object renamed in org | Rule logs error, does not crash framework |

### 9.4 Regression test suite

Maintain a `scripts/apex/run-regression.apex` script that:
1. Creates test data covering scenarios F-01 through F-15.
2. Forces CDC and Platform Event delivery.
3. Asserts expected log counts and statuses.
4. Outputs a pass/fail summary.

Run this in every release-candidate sandbox before promoting to production.

---

## 10. Deployment and packaging

### 10.1 ISV packaging workflow

```bash
# 1. Create a package version
sf package version create \
  --package "Hypermatica Notifications" \
  --installation-key-bypass \
  --wait 20 \
  --code-coverage

# 2. Promote to release (only after security review)
sf package version promote --package "Hypermatica Notifications@1.0.0-1"

# 3. Install in a test sandbox
sf package install \
  --package "04t..." \
  --target-org test-sandbox \
  --wait 10
```

### 10.2 Post-install Apex

Provide a `PostInstallScript` implementing `InstallHandler` to:

1. Create the Platform Cache partition `NotifFramework` (if not already created via metadata).
2. Insert seed `NotificationTemplate__c` records (sample templates).
3. Assign permission sets to the installing admin user.

```apex
global class PostInstallScript implements InstallHandler {
    global void onInstall(InstallContext ctx) {
        if (ctx.previousVersion() == null) {
            // First install
            seedTemplates();
            assignDefaultPermSet(ctx.installerId());
        } else {
            // Upgrade — version-specific migrations here
        }
    }
    // ...
}
```

### 10.3 Internal (unmanaged) deployment

For internal Hypermatica builds:

```bash
# Validate
sf project deploy validate --source-dir force-app --target-org production

# Deploy
sf project deploy start --source-dir force-app --target-org production --test-level RunLocalTests
```

### 10.4 Customer setup checklist (post-install)

Document these as a one-page install guide:

1. ☐ Assign `Notification_Admin` permission set to admins.
2. ☐ Enable Change Data Capture on each object you want monitored (Setup → Change Data Capture).
3. ☐ Create one CDC trigger per monitored object (provide a copy-paste template).
4. ☐ Verify the Custom Notification Type appears in Setup → Custom Notifications.
5. ☐ Create at least one `NotificationTemplate__c` record.
6. ☐ Create your first `NotificationRule__c` record.
7. ☐ Test by triggering the condition on a sample record.
8. ☐ Inspect `NotificationLog__c` to confirm delivery.

---

## 11. Known limitations and edge cases

| Limitation | Impact | Mitigation |
|---|---|---|
| CDC must be enabled per object | Customer setup step | Document clearly; provide setup wizard in v2 |
| CDC entity limit (5 free) | Limits how many objects can be monitored without add-on | Document; recommend customers prioritize critical objects |
| Daily email limit (5K mass emails) | High-volume orgs may hit cap | Document; recommend SMTP relay via SendGrid in v2 |
| Bell `CustomNotification.send` 500 recipient cap | Large queues require batching | Framework handles automatically |
| Platform Event daily publish limit | High-volume orgs | Batch multiple notifications per event in v2 |
| CDC payload doesn't include all field changes for some standard objects | Some conditions may not detect | Document per-object CDC field coverage from Salesforce docs |
| `Cache.OrgPartition` not available in all editions | Cache fallback to per-transaction SOQL | Detect at runtime and fall back gracefully |
| Recipient must have read access on record for Bell `setTargetId` | Bell click 404s | Document; provide config option to omit `targetId` |
| Long-running evaluators count against CPU governor | 50+ rules per object risky | Document; recommend keeping evaluator logic simple |

---

## 12. Appendix

### A. Merge field grammar

```
{{ Record.Field }}                    → record's field value
{{ Record.Account.Name }}             → parent lookup field (caller must select it)
{{ Recipient.FirstName }}             → recipient User field
{{ Rule.Rule_Label__c }}              → the rule's field
{{ Context.Now }}                     → DateTime.now() formatted
{{ Context.Today }}                   → Date.today() formatted
{{ !Record.HTML_Body__c }}            → raw HTML, no escaping (use with caution)
```

Tokens are case-sensitive. Unknown tokens render as empty string and emit a warning to the debug log.

### B. Sample rule configurations

**Notify Account Owner when Account becomes a Customer:**
```
Object_API_Name__c:      Account
Trigger_Event__c:        Update
Watched_Fields__c:       Type
Condition_Class__c:      hypnotif.FieldChangedEvaluator
Condition_Config__c:     {"field": "Type", "value": "Customer"}
Recipient_Strategy__c:   Owner
Recipient_Config__c:     {"excludeChangeAuthor": true}
Cooldown_Minutes__c:     1440
```

**Notify Case queue when a high-priority Case is created:**
```
Object_API_Name__c:      Case
Trigger_Event__c:        Create
Watched_Fields__c:       (empty — any insert)
Condition_Class__c:      hypnotif.FieldEqualsEvaluator
Condition_Config__c:     {"field": "Priority", "value": "High"}
Recipient_Strategy__c:   Queue
Recipient_Config__c:     {"queueId": "00G..."}
```

### C. CDC trigger template

Copy this template for each object the customer wants monitored. Replace `Account` with the target object's API name (use `__ChangeEvent` for custom objects, e.g. `Grant__ChangeEvent`).

```apex
trigger AccountChangeEventTrigger on AccountChangeEvent (after insert) {
    hypnotif.NotificationDispatcher.dispatch(Trigger.new, 'Account');
}
```

For namespaced custom objects, the source object reference includes the namespace:

```apex
trigger GrantChangeEventTrigger on hypnotif__Grant__ChangeEvent (after insert) {
    hypnotif.NotificationDispatcher.dispatch(Trigger.new, 'hypnotif__Grant__c');
}
```

### D. Glossary of Salesforce capabilities used

| Capability | Where used | Docs link |
|---|---|---|
| Change Data Capture | Trigger source | Setup → Integrations → Change Data Capture |
| Platform Events | Async dispatch | Setup → Integrations → Platform Events |
| Custom Notification Type | Bell channel | Setup → Notification Builder → Custom Notifications |
| Platform Cache | Rule caching | Setup → Platform Cache |
| Messaging.SingleEmailMessage | Email channel | Apex Reference |
| Messaging.CustomNotification | Bell channel | Apex Reference |
| Custom Metadata Types | Channel registry | Setup → Custom Metadata Types |
| Stub API | Unit testing | Apex Developer Guide |
| `Type.forName()` | Dynamic Apex instantiation | Apex Reference |

### E. Future work tracking

Tickets reserved for v2:

| Ticket | Description |
|---|---|
| NF-V2-001 | SMSChannelHandler with Twilio Named Credential |
| NF-V2-002 | SlackChannelHandler |
| NF-V2-003 | TeamsChannelHandler |
| NF-V2-004 | WebhookChannelHandler |
| NF-V2-005 | Digest / batching mode (rollup notifications) |
| NF-V2-006 | End-user notification preferences |
| NF-V2-007 | Multi-language template support |
| NF-V2-008 | CDC enablement setup wizard |
| NF-V2-009 | Rule builder UI for non-developer condition authoring |

---

**Document owner:** Senior Salesforce Architect
**Last updated:** 2026-05-27
**Next review:** End of Phase 2 (Week 2 of implementation)
