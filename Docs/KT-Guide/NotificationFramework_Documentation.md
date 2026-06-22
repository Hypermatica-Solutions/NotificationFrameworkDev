# Salesforce Metadata-Driven Notification Framework
## Complete Technical Documentation

**Project:** notification-framework-salesforce  
**Org Alias:** NotificationsDev  
**Author:** Prajwal Pandgale — Hypermatica  
**Date:** May 2026  

---

## Table of Contents

1. [What Is This Framework?](#1-what-is-this-framework)
2. [Why Was It Built This Way?](#2-why-was-it-built-this-way)
3. [High-Level Architecture](#3-high-level-architecture)
4. [The Three Configuration Records](#4-the-three-configuration-records)
5. [Step-by-Step: What Happens When an Account Changes](#5-step-by-step-what-happens-when-an-account-changes)
6. [Deep Dive: Every Class Explained](#6-deep-dive-every-class-explained)
7. [Key Salesforce Concepts Explained](#7-key-salesforce-concepts-explained)
8. [Interfaces — The Extensibility Engine](#8-interfaces--the-extensibility-engine)
9. [How Recipients Are Found](#9-how-recipients-are-found)
10. [How the Email Is Built and Sent](#10-how-the-email-is-built-and-sent)
11. [The Final Email — What It Looks Like](#11-the-final-email--what-it-looks-like)
12. [Audit Trail — NotificationLog__c](#12-audit-trail--notificationlog__c)
13. [Troubleshooting Guide](#13-troubleshooting-guide)
14. [How to Add a New Rule (Configuration Guide)](#14-how-to-add-a-new-rule-configuration-guide)
15. [Glossary of Terms](#15-glossary-of-terms)

---

## 1. What Is This Framework?

The **Notification Framework** is a metadata-driven, event-based email and in-app notification system built on Salesforce. It automatically sends notifications to users when specific records change — without requiring any code changes for new use cases.

**In plain English:** When someone in your Salesforce org changes an Account's Type to "Customer - Direct", this framework automatically emails the Account Owner with a professionally formatted notification containing all relevant details from the record.

### What Makes It "Metadata-Driven"?

The word *metadata-driven* means the behaviour of the system is controlled entirely by **configuration records** stored in Salesforce custom objects — not by hardcoded logic in Apex classes. 

To add a brand-new notification rule (e.g., "notify the owner when a Case is closed"), an admin creates three records in the UI. No developer writes a single line of new Apex code.

---

## 2. Why Was It Built This Way?

### The Problem With Traditional Approaches

Most Salesforce developers write notification logic directly inside triggers:

```apex
// Traditional (bad) approach
trigger AccountTrigger on Account (after update) {
    for (Account acc : Trigger.new) {
        if (acc.Type == 'Customer - Direct') {
            // hardcoded email logic here...
        }
    }
}
```

This approach has serious problems:
- Every new rule requires a code deployment
- Logic is scattered across many triggers
- No audit trail of what was sent to whom
- Cannot be extended by customers without modifying core code

### The Solution: A Framework Pattern

This framework separates **what to do** (configuration) from **how to do it** (code). The code is written once and never changes. The configuration records drive everything.

---

## 3. High-Level Architecture

```
USER SAVES ACCOUNT IN SALESFORCE
           │
           ▼
┌─────────────────────────────────┐
│  Salesforce CDC                 │
│  (Change Data Capture)          │
│  Detects: Type field changed    │
└─────────────────┬───────────────┘
                  │ fires AccountChangeEvent
                  ▼
┌─────────────────────────────────┐
│  AccountChangeEventTrigger      │  ← Entry point (trigger)
│  .trigger                       │
└─────────────────┬───────────────┘
                  │
                  ▼
┌─────────────────────────────────┐
│  NotificationDispatcher         │  ← Parses CDC event metadata
│  .cls                           │    Extracts: which fields changed,
└─────────────────┬───────────────┘    who changed it, which record
                  │
                  ▼
┌─────────────────────────────────┐
│  RecordQueryService             │  ← Re-queries the full Account
│  .cls                           │    record with ALL fields
└─────────────────┬───────────────┘
                  │
                  ▼
┌─────────────────────────────────┐
│  NotificationRouter             │  ← The brain: orchestrates
│  .cls                           │    all filters and delivery
└──────┬──────────┬───────────────┘
       │          │
       ▼          ▼
 ┌─────────┐  ┌──────────────────────┐
 │RuleCache│  │  For each active Rule │
 │.cls     │  │                      │
 └─────────┘  │  Filter 1: Object +  │
               │  Event matches?      │
               │  Filter 2: Watched   │
               │  field changed?      │
               │  Filter 3: Condition │
               │  evaluator passes?   │
               └──────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  FieldChangedEvaluator│  ← "Did Type become
              │  (IConditionEvaluator)│     Customer - Direct?"
              └───────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  OwnerResolver        │  ← "Who should receive
              │  (IRecipientResolver) │     this notification?"
              └───────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  TemplateEngine       │  ← Replaces {{{tokens}}}
              │  .cls                 │    with real values
              └───────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  EmailChannelHandler  │  ← Sends the email via
              │  (IChannelHandler)    │    Salesforce Messaging API
              └───────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  LogService           │  ← Writes NotificationLog__c
              │  .cls                 │    record for audit trail
              └───────────────────────┘
                          │
                          ▼
              📧 EMAIL ARRIVES IN INBOX
```

---

## 4. The Three Configuration Records

Before the framework can send any notification, an admin must create exactly **three records** in Salesforce. Think of them as the "settings" that tell the framework what to watch, how to format the message, and how to deliver it.

---

### Record 1: NotificationTemplate__c

**What it is:** The email template — the HTML content and subject line of the notification email.

**Purpose:** Stores the visual design of the email. Uses `{{{token}}}` placeholders that get replaced with real data at send time.

**Key Fields:**

| Field | What It Stores | Example Value |
|-------|---------------|---------------|
| `Name` | Unique template identifier | `Account Customer Welcome Email` |
| `Subject__c` | Email subject line (can contain tokens) | `{{{Account_Name}}} is now a Customer — Welcome!` |
| `Body__c` | Full HTML body of the email | (full HTML with `{{{Owner_Name}}}` etc.) |
| `Body_Is_HTML__c` | Whether body is HTML or plain text | `true` |
| `Language__c` | Language of this template | `English` |
| `Template_Key__c` | Unique key for programmatic lookup | `account-customer-welcome` |

**Available Template Tokens:**

Any field from the Account record can be used as a token using triple curly braces:

```
{{{Account_Name}}}    → The Account's Name field value
{{{Owner_Name}}}      → Human-readable name of the Account owner
{{{Industry}}}        → Industry field value
{{{AnnualRevenue}}}   → Annual Revenue field value
{{{Changed_By}}}      → Name of the user who made the change
```

---

### Record 2: NotificationRule__c

**What it is:** The rule that defines WHEN to fire a notification and under what conditions.

**Purpose:** Acts as the trigger definition — which object to watch, which event type, which fields to monitor, and what conditions must be true.

**Key Fields:**

| Field | What It Stores | Example Value |
|-------|---------------|---------------|
| `Rule_Label__c` | Human-readable rule name | `Notify Owner on Account Type Change` |
| `Object_API_Name__c` | Which Salesforce object to watch | `Account` |
| `Trigger_Event__c` | Which DML operation triggers this | `UPDATE` |
| `Watched_Fields__c` | Comma-separated list of fields to watch | `Type` |
| `Active__c` | Whether this rule is enabled | `true` |
| `Priority__c` | Order of evaluation (lower = higher priority) | `1` |
| `Condition_Class__c` | Apex class that evaluates advanced conditions | `FieldChangedEvaluator` |
| `Condition_Config__c` | JSON config passed to the condition evaluator | `{"field":"Type","value":"Customer - Direct"}` |
| `Recipient_Resolver_Class__c` | Apex class that determines who to notify | `OwnerResolver` |
| `Recipient_Config__c` | JSON config for the recipient resolver | `{"excludeChangeAuthor": true}` |
| `Cooldown_Minutes__c` | Minimum minutes between repeat notifications | `60` |

**How the Rule Acts as a Filter:**

The rule provides three layers of filtering before any notification is sent:

```
Layer 1: Object + Event match?
         Object_API_Name__c = "Account" AND Trigger_Event__c = "UPDATE"

Layer 2: At least one Watched Field changed?
         Watched_Fields__c = "Type" → was Type in the list of changed fields?

Layer 3: Condition evaluator passes?
         Condition_Class__c = "FieldChangedEvaluator"
         Condition_Config__c = {"field":"Type","value":"Customer - Direct"}
         → Did Type specifically become "Customer - Direct"?
```

Only when ALL three layers pass does the framework proceed to send a notification.

---

### Record 3: NotificationChannel__c

**What it is:** The delivery channel — how the notification gets delivered (Email, Bell notification, etc.) and which template to use.

**Purpose:** Links a Rule to a Template and specifies the delivery mechanism.

**Key Fields:**

| Field | What It Stores | Example Value |
|-------|---------------|---------------|
| `Name` | Channel identifier | `NC-0000` |
| `Rule__c` | Lookup to NotificationRule__c | (ID of the rule) |
| `Template__c` | Lookup to NotificationTemplate__c | (ID of the template) |
| `Channel_Type__c` | Delivery mechanism | `Email` |
| `Active__c` | Whether this channel is enabled | `true` |
| `Channel_Config__c` | JSON config for this channel | `{"senderDisplayName":"Notifications"}` |

**One Rule Can Have Multiple Channels:**

```
NotificationRule__c  →  NotificationChannel__c (Email)
                     →  NotificationChannel__c (Bell / In-App)
                     →  NotificationChannel__c (Slack) ← future
```

When a rule fires, the framework delivers through ALL active channels attached to it simultaneously.

---

### How the Three Records Connect

```
NotificationRule__c
    "Notify Owner on Account Type Change"
    Object: Account | Event: UPDATE
    Condition: FieldChangedEvaluator
    Resolver: OwnerResolver
           │
           │ (linked via Rule__c lookup)
           ▼
NotificationChannel__c
    "NC-0000"
    Type: Email
           │
           │ (linked via Template__c lookup)
           ▼
NotificationTemplate__c
    "Account Customer Welcome Email"
    Subject: {{{Account_Name}}} is now a Customer — Welcome!
    Body: <html>...</html>
```

---

## 5. Step-by-Step: What Happens When an Account Changes

Let's trace exactly what happens when a Salesforce user changes the **Type** field on the "CDC Demo Co" account from `Prospect` to `Customer - Direct` and clicks Save.

---

### Step 1: User Saves the Account

The user edits the Account record in Salesforce UI and changes:
- **Type**: `Prospect` → `Customer - Direct`

Salesforce performs the DML (Data Manipulation Language) update operation on the Account record.

---

### Step 2: CDC Detects the Change

**CDC (Change Data Capture)** is a Salesforce feature that publishes a platform event called `AccountChangeEvent` whenever an Account record is created, updated, or deleted.

This event is published **asynchronously** — meaning it fires in a separate background transaction after the user's save is complete. It runs under the **"Automated Process"** system user, not the user who made the change.

The `AccountChangeEvent` platform event contains:
```
ChangeEventHeader:
  changeType:    "UPDATE"
  changedFields: ["Type", "LastModifiedDate"]
  recordIds:     ["001dL00002C1LiRQAV"]
  commitUser:    "005dL00001mJWmPQAW"   ← ID of Prajwal Pandgale
```

Note: CDC only carries the fields that **changed**, not the entire record. This is why we need to re-query the full record later.

---

### Step 3: AccountChangeEventTrigger Fires

The CDC event fires our Apex trigger:

```apex
trigger AccountChangeEventTrigger on AccountChangeEvent (after insert) {
    // Debug logging — confirms CDC fired in logs
    for (AccountChangeEvent event : Trigger.new) {
        EventBus.ChangeEventHeader header = event.ChangeEventHeader;
        System.debug('Change Type:    ' + header.changeType);    // UPDATE
        System.debug('Changed Fields: ' + header.changedFields); // [Type, LastModifiedDate]
        System.debug('Record IDs:     ' + header.recordIds);     // [001dL...]
        System.debug('Changed By:     ' + header.commitUser);    // 005dL...
    }

    // Hand off to the framework
    NotificationDispatcher.dispatch(Trigger.new, 'Account');
}
```

**Why "after insert" for a CDC trigger?**  
CDC platform events are always "inserted" into the event bus — it's a publish/subscribe mechanism. The word "insert" here means "a new event was published", not that the Account was inserted. It's confusing terminology but correct Apex syntax for platform event triggers.

---

### Step 4: NotificationDispatcher Parses the Event

The `NotificationDispatcher` class receives the raw CDC events and extracts the important metadata.

**The Challenge:** The `ChangeEventHeader` is a special Salesforce object that **cannot be directly cast** from a generic SObject. Trying to cast it directly causes a compile error:
```apex
// THIS FAILS — cannot cast SObject to ChangeEventHeader
EventBus.ChangeEventHeader h = (EventBus.ChangeEventHeader) evt.get('ChangeEventHeader');
```

**The Solution:** Serialize the entire event to JSON and then deserialize it back as a generic Map:
```apex
Map<String, Object> evtMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(evt));
Map<String, Object> header = (Map<String, Object>) evtMap.get('ChangeEventHeader');
```

This JSON round-trip trick converts the complex event object into a simple key-value map that Apex can safely navigate.

After parsing, the Dispatcher has:
```
recordIds             = { 001dL00002C1LiRQAV }
changedFieldsByRecord = { 001dL... → {"Type", "LastModifiedDate"} }
changeTypeByRecord    = { 001dL... → "UPDATE" }
commitUserByRecord    = { 001dL... → 005dL00001mJWmPQAW }
```

---

### Step 5: RecordQueryService Re-Queries the Full Record

Since CDC only provides the changed fields, we need the complete Account record to:
- Access unchanged fields like `Name`, `Industry`, `OwnerId`
- Populate template tokens like `{{{Account_Name}}}`, `{{{Industry}}}`

```apex
Map<Id, SObject> records = RecordQueryService.queryByIds('Account', recordIds);
```

The `RecordQueryService` dynamically builds a SOQL query with **all accessible fields**:
```sql
SELECT id, name, type, industry, annualrevenue, ownerid, ... 
FROM Account 
WHERE Id IN :recordIds
```

It uses `Schema.getGlobalDescribe()` to get the object's field map and `isAccessible()` to respect FLS (Field-Level Security).

---

### Step 6: NotificationRouter Orchestrates Everything

The Router is the brain of the framework. For each changed record, it:

1. Asks `RuleCache` for all active rules matching `Account` + `UPDATE`
2. For each rule, runs three filters
3. If all filters pass, delivers through all active channels

#### Sub-step 6a: RuleCache Loads Rules

The `RuleCache` checks its static in-memory map. If empty (first call in this transaction), it loads ALL active rules from the database in just **two SOQL queries**:

**Query 1:** All active NotificationRule__c records
```sql
SELECT Id, Rule_Label__c, Object_API_Name__c, Trigger_Event__c, 
       Watched_Fields__c, Condition_Class__c, Condition_Config__c,
       Recipient_Resolver_Class__c, Cooldown_Minutes__c, Priority__c
FROM NotificationRule__c 
WHERE Active__c = true 
ORDER BY Priority__c ASC NULLS LAST
```

**Query 2:** All active channels for those rules (with template inline)
```sql
SELECT Id, Rule__c, Channel_Type__c, Channel_Config__c,
       Template__r.Subject__c, Template__r.Body__c, Template__r.Body_Is_HTML__c
FROM NotificationChannel__c 
WHERE Rule__c IN :ruleIds 
AND Active__c = true
```

The result is stored in a static Map: `"account|update"` → `[RuleBundle, ...]`

**Why static cache?** If 50 Account records change in one batch, the cache loads rules once and reuses them for all 50 records. Without caching, that would be 100 SOQL queries (2 per record) — hitting Salesforce's 100 SOQL limit.

#### Sub-step 6b: Filter 2 — Watched Field Check

```apex
// Rule has: Watched_Fields__c = "Type"
// CDC reports: changedFields = {"Type", "LastModifiedDate"}
watchedFieldChanged("Type", {"Type", "LastModifiedDate"})  → true ✅
```

The check is case-insensitive. If `Watched_Fields__c` is blank, any change qualifies.

#### Sub-step 6c: Filter 3 — Condition Evaluator

The Router reads `Condition_Class__c = "FieldChangedEvaluator"` and dynamically instantiates it:

```apex
IConditionEvaluator evaluator = 
    (IConditionEvaluator) Type.forName("FieldChangedEvaluator").newInstance();
return evaluator.evaluate(ctx);
```

`Type.forName()` is Apex's reflection mechanism — it looks up a class by its name as a String and creates a new instance at runtime. This is how the framework can call ANY evaluator class without knowing about it at compile time.

The `FieldChangedEvaluator` receives:
- `ctx.changedFields` = `{"Type", "LastModifiedDate"}`
- `ctx.config` = `{"field": "Type", "value": "Customer - Direct"}`
- `ctx.newRecord` = the full Account with `Type = "Customer - Direct"`

It checks:
1. Is "Type" in changedFields? → YES
2. Is there an expected value configured? → YES ("Customer - Direct")
3. Does the actual new value match? → `"Customer - Direct".equalsIgnoreCase("Customer - Direct")` → YES ✅

---

### Step 7: OwnerResolver Finds the Recipient

The Router reads `Recipient_Resolver_Class__c = "OwnerResolver"` and dynamically instantiates it the same way:

```apex
IRecipientResolver resolver = 
    (IRecipientResolver) Type.forName("OwnerResolver").newInstance();
return resolver.resolve(ctx);
```

The `OwnerResolver` receives:
- `ctx.record` = the Account record
- `ctx.config` = `{}` (or `{"excludeChangeAuthor": true}` if configured)
- `ctx.config` also has `commitUserId` injected by the Router

It reads `record.get("OwnerId")` → `005dL00001mJWmPQAW` (Prajwal Pandgale's ID)

Optional: If `excludeChangeAuthor: true` is in config AND the owner is the same person who made the change, the notification is suppressed (to avoid notifying someone about their own changes).

Result: `recipientIds = { 005dL00001mJWmPQAW }` ✅

---

### Step 8: TemplateEngine Resolves Tokens

Before sending, the Router builds a **merge context** — a map of token names to their values:

```
mergeContext = {
  "Id"             → "001dL00002C1LiRQAV",
  "Name"           → "CDC Demo Co",
  "Account_Name"   → "CDC Demo Co",       ← alias added by buildMergeContext
  "Type"           → "Customer - Direct",
  "Industry"       → "Technology",
  "AnnualRevenue"  → "1500000",
  "OwnerId"        → "005dL00001mJWmPQAW",
  "Owner_Name"     → "Prajwal Pandgale",  ← queried from User object
  "Changed_By"     → "Prajwal Pandgale"   ← queried from User object
}
```

The `TemplateEngine.render()` method uses Java regex to find every `{{{token}}}` in the template and replaces it:

```
Template: "Hi {{{Owner_Name}}}, The account {{{Account_Name}}} is now a Customer."
Result:   "Hi Prajwal Pandgale, The account CDC Demo Co is now a Customer."
```

**Token resolution is case-insensitive:** `{{{owner_name}}}` and `{{{Owner_Name}}}` both resolve correctly.

**Unresolved tokens stay visible:** If `{{{AnnualRevenue}}}` has no matching value in the context map, it remains as `{{{AnnualRevenue}}}` in the output — making it obvious during development that a token is unresolved.

---

### Step 9: EmailChannelHandler Sends the Email

The Router looks up the handler for `Channel_Type__c = "Email"`:

```apex
Map<String, String> handlerMap = new Map<String, String>{
    'Email' => 'EmailChannelHandler',
    'Bell'  => 'BellChannelHandler'
};
IChannelHandler handler = (IChannelHandler) Type.forName('EmailChannelHandler').newInstance();
```

The `EmailChannelHandler` receives the fully assembled `NotificationPayload` containing:
- `recipientIds` = { 005dL00001mJWmPQAW }
- `subject` = "CDC Demo Co is now a Customer — Welcome!"  (tokens already resolved)
- `body` = full rendered HTML  (tokens already resolved)
- `bodyIsHtml` = true
- `channelConfig` = { "senderDisplayName": "Notifications" }

The handler then:

1. **Queries email addresses** for all recipient IDs:
   ```sql
   SELECT Id, Email FROM User 
   WHERE Id IN :recipientIds AND IsActive = true
   ```
   Result: `prajwal.pandgale@hypermatica.com`

2. **Queries Org-Wide Email Address** (ensures consistent From address even in automated context):
   ```sql
   SELECT Id FROM OrgWideEmailAddress WHERE IsVerified = true LIMIT 1
   ```

3. **Builds a SingleEmailMessage** for each recipient:
   ```apex
   Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
   msg.setToAddresses(['prajwal.pandgale@hypermatica.com']);
   msg.setSubject('CDC Demo Co is now a Customer — Welcome!');
   msg.setHtmlBody('<html>..rendered HTML..</html>');
   msg.setOrgWideEmailAddressId(orgWideEmailId);  // verified From address
   msg.setSaveAsActivity(false);   // don't create Activity record
   msg.setUseSignature(false);     // don't append org email signature
   ```

4. **Sends all emails in a single call:**
   ```apex
   List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
   // false = allow partial failures (don't throw exception if one fails)
   ```

5. **Builds DeliveryResult** with success/failure per recipient

---

### Step 10: LogService Records the Outcome

After the handler returns, the Router calls:

```apex
LogService.log(rule, channel, recordId, recipientIds, result);
```

`LogService` inserts one `NotificationLog__c` record per recipient:

```
NotificationLog__c {
    Rule__c:           [ID of "Notify Owner on Account Type Change"]
    Channel__c:        [ID of "NC-0000"]
    Record_Id__c:      "001dL00002C1LiRQAV"
    Channel_Type__c:   "Email"
    Recipient_User__c: [ID of Prajwal Pandgale]
    Status__c:         "Sent"
    Sent_At__c:        2026-05-30T10:16:00Z
}
```

This record is the permanent audit trail proving that the notification was sent, to whom, when, and through which channel.

---

## 6. Deep Dive: Every Class Explained

### AccountChangeEventTrigger

**File:** `force-app/main/default/triggers/AccountChangeEventTrigger.trigger`  
**Type:** Apex Trigger on `AccountChangeEvent`  
**When it runs:** After any AccountChangeEvent is published (after insert)

This is the entry point of the entire framework. It has only one job: pass the raw events to `NotificationDispatcher`. The debug logging at the top is intentionally kept so developers can verify in debug logs that CDC is firing correctly.

**Key technical point:** CDC triggers always use `after insert` syntax. The "insert" refers to a new event being published to the event bus, not an Account insert operation.

---

### NotificationDispatcher

**File:** `force-app/main/default/classes/core/NotificationDispatcher.cls`  
**Access Modifier:** `global without sharing`  
**Purpose:** Parses raw CDC events and hands structured data to the Router

**Why `global`?** The `global` keyword means this class is accessible from any Salesforce package. As an ISV product, customers must be able to call `NotificationDispatcher.dispatch()` from their own CDC triggers for any object (not just Account).

**Why `without sharing`?** CDC events fire under the "Automated Process" system user, which has no sharing rules and cannot see records through normal sharing visibility. `without sharing` bypasses Salesforce's record-level security to ensure the framework always has access to the data it needs.

**The JSON Round-Trip Pattern:**

```apex
// ChangeEventHeader cannot be directly cast — this is a Salesforce platform limitation
Map<String, Object> evtMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(evt));
Map<String, Object> header = (Map<String, Object>) evtMap.get('ChangeEventHeader');
```

`JSON.serialize(evt)` converts the complex event SObject to a JSON string.  
`JSON.deserializeUntyped(...)` converts it back to a plain `Map<String, Object>`.  
Now we can safely call `.get('changeType')`, `.get('changedFields')`, etc.

---

### RecordQueryService

**File:** `force-app/main/default/classes/core/RecordQueryService.cls`  
**Access Modifier:** `public with sharing`  
**Purpose:** Re-queries complete SObject records using dynamic SOQL

**Why `with sharing`?** This class queries records on behalf of the system. Using `with sharing` respects Salesforce's Field-Level Security — only fields the running user can read are included in the query. This protects sensitive data from being inadvertently included in notification emails.

**Dynamic SOQL Construction:**

```apex
Schema.SObjectType sObjType = Schema.getGlobalDescribe().get('Account');
// Gets the list of all fields on Account
// Filters to only accessible fields
// Builds: "SELECT id, name, type, industry, ... FROM Account WHERE Id IN :recordIds"
```

This approach works for ANY Salesforce object without modification — the same code queries Accounts, Cases, Opportunities, or custom objects equally.

---

### RuleCache

**File:** `force-app/main/default/classes/core/RuleCache.cls`  
**Access Modifier:** `public without sharing`  
**Purpose:** Loads and caches all active notification rules in memory

**The Static Map Pattern:**

```apex
private static Map<String, List<RuleBundle>> cache;
```

The `static` keyword in Apex means this variable lives for the entire duration of a transaction (not just one method call). Once loaded, the cache is reused by every subsequent call to `getRules()` within the same Apex transaction.

**Why this matters:** In a CDC batch where 20 Accounts change simultaneously, `RuleCache.getRules()` is called 20 times — but it hits the database only once. Without this pattern, you'd run 40 SOQL queries (2 per record × 20 records), potentially hitting Salesforce's governor limit of 100 SOQL queries per transaction.

**The RuleBundle Inner Class:**

```apex
public class RuleBundle {
    public NotificationRule__c rule;
    public List<NotificationChannel__c> channels;
}
```

A `RuleBundle` groups one rule with all its channels. This pre-joining of data means the Router never needs to do additional SOQL lookups to find a rule's channels.

**The Cache Key:**

```apex
// "Account" + "UPDATE" → "account|update"
String key = objectApiName.toLowerCase() + '|' + triggerEvent.toLowerCase();
```

Lowercase normalization ensures `"Account"` and `"account"` return the same result.

---

### NotificationRouter

**File:** `force-app/main/default/classes/core/NotificationRouter.cls`  
**Access Modifier:** `public without sharing`  
**Purpose:** Orchestrates all filters, recipient resolution, template rendering, and delivery

This is the most important class in the framework. It coordinates all other components.

**The `buildMergeContext` Method — Important Bug That Was Fixed:**

```apex
// WRONG — returns a read-only map, calling .put() throws FinalException
Map<String, Object> ctx = record.getPopulatedFieldsAsMap();

// CORRECT — wraps in a new map, making it writable
Map<String, Object> ctx = new Map<String, Object>(record.getPopulatedFieldsAsMap());
```

`SObject.getPopulatedFieldsAsMap()` returns an **unmodifiable** map. The framework needs to add extra entries (`Account_Name`, `Owner_Name`, `Changed_By`) so it must copy it into a new writable map first.

**The `parseJson` Method — Naming Caution:**

```apex
// WRONG — parameter named "json" shadows the built-in JSON class
private static Map<String, Object> parseJson(String json) {
    return (Map<String, Object>) JSON.deserializeUntyped(json); // FAILS — JSON is shadowed
}

// CORRECT — use a different parameter name
private static Map<String, Object> parseJson(String rawJson) {
    return (Map<String, Object>) JSON.deserializeUntyped(rawJson); // WORKS
}
```

In Apex, if a local variable or parameter has the same name as a system class (`JSON`, `System`, `Trigger`), the local name wins and you lose access to the system class. This caused a compilation error that was fixed by renaming the parameter to `rawJson`.

---

### TemplateEngine

**File:** `force-app/main/default/classes/core/TemplateEngine.cls`  
**Access Modifier:** `public with sharing`  
**Purpose:** Resolves `{{{token}}}` placeholders in template strings

**The Regex Pattern:**

```apex
Pattern.compile('\\{\\{\\{([^}]+)\\}\\}\\}').matcher(template)
```

Breaking down the regex (each `\\` is an escaped backslash in Apex strings):
- `\{\{\{` — matches the literal `{{{` opening
- `([^}]+)` — capture group: one or more characters that are NOT `}`
- `\}\}\}` — matches the literal `}}}` closing

**Why triple curly braces `{{{` instead of single `{`?**  
Single `{` conflicts with Salesforce's own merge field syntax in Visualforce and Lightning. Double `{{` is used by Handlebars/Mustache templates. Triple `{{{` is unique and unambiguous in Salesforce context.

**Case-Insensitive Token Lookup:**

```apex
Map<String, String> lowerCtx = new Map<String, String>();
for (String key : context.keySet()) {
    lowerCtx.put(key.toLowerCase(), String.valueOf(context.get(key)));
}
// Now {{{owner_name}}} and {{{Owner_Name}}} both resolve correctly
```

---

### FieldChangedEvaluator

**File:** `force-app/main/default/classes/evaluators/FieldChangedEvaluator.cls`  
**Access Modifier:** `global with sharing`  
**Implements:** `IConditionEvaluator`  
**Purpose:** Evaluates whether a specific field changed to a specific value

**Supported Operators:**

| Operator | Behaviour | Example Config |
|----------|-----------|----------------|
| `equals` (default) | Field value exactly matches | `{"field":"Type","value":"Customer - Direct"}` |
| `not_equals` | Field value does NOT match | `{"field":"Type","value":"Prospect","operator":"not_equals"}` |
| `contains` | Field value contains the substring | `{"field":"Name","value":"Corp","operator":"contains"}` |

**Three-Step Evaluation:**

```
Step 1: Was this field reported as changed by CDC?
        → If not, skip immediately (fast exit)

Step 2: Is an expected value configured?
        → If no value configured, any change to the field qualifies

Step 3: Does the actual new value match the expected value?
        → Comparison is case-insensitive
```

**Why `global`?** Customers can reference this class in their `Condition_Class__c` field. Making it `global` ensures it's accessible across managed package boundaries.

---

### OwnerResolver

**File:** `force-app/main/default/classes/resolvers/OwnerResolver.cls`  
**Access Modifier:** `global with sharing`  
**Implements:** `IRecipientResolver`  
**Purpose:** Returns the record's owner as the notification recipient

**The `excludeChangeAuthor` Feature:**

```apex
// Config: {"excludeChangeAuthor": true}
// If the owner changed their own record, don't notify them
Boolean excludeAuthor = ctx.config.containsKey('excludeChangeAuthor')
                        && ctx.config.get('excludeChangeAuthor') == true;

if (excludeAuthor && ctx.config.containsKey('commitUserId')) {
    Id commitUserId = (Id)(String) ctx.config.get('commitUserId');
    if (ownerId == commitUserId) {
        System.debug('OwnerResolver: owner is the change author — suppressed');
        return new Set<Id>();  // empty set = no recipients = no notification
    }
}
```

This is injected by the Router:
```apex
if (commitUserId != null) config.put('commitUserId', (Object) String.valueOf(commitUserId));
```

The `commitUserId` (who made the change) is passed to every resolver so they can implement suppression logic.

**The `ownerField` Override:**

```apex
String ownerField = ctx.config.containsKey('ownerField')
                    ? (String) ctx.config.get('ownerField')
                    : 'OwnerId';  // default
```

This allows the same OwnerResolver to work on custom objects that have a different ownership field, e.g., `{"ownerField": "Account_Manager__c"}`.

---

### EmailChannelHandler

**File:** `force-app/main/default/classes/handlers/EmailChannelHandler.cls`  
**Access Modifier:** `global without sharing`  
**Implements:** `IChannelHandler`  
**Purpose:** Sends HTML or plain-text emails using Salesforce's Messaging API

**Why `without sharing`?** The handler queries `User` records and `OrgWideEmailAddress` records. In CDC async context (Automated Process user), sharing rules don't apply and `without sharing` ensures these lookups always succeed.

**Why NOT use `setTemplateId()`?**

Salesforce has two modes for sending single emails:
- **Mode 1:** `setTemplateId()` — uses a Salesforce Classic email template stored in Setup
- **Mode 2:** `setHtmlBody()` / `setPlainTextBody()` — uses a custom string body

CDC triggers run in an **asynchronous platform event context**. Salesforce does **not allow** template-based emails (`setTemplateId`) in this context. The framework uses Mode 2 exclusively — the template HTML is rendered by `TemplateEngine` and passed as a string.

**Why `setUseSignature(false)`?**

Every Salesforce user can configure a personal email signature in their profile. Without this flag, Salesforce appends the running user's signature to every notification email. In CDC context the running user is "Automated Process" whose signature might be empty or contain internal system text — either way it shouldn't appear in customer-facing notification emails.

**Why `setSaveAsActivity(false)`?**

By default, Salesforce tries to log every sent email as an Activity (a Task record) on the related record. For notification emails sent to account owners, this would create dozens of Task records on every Account that fires a rule — polluting the Activity timeline. Setting this to `false` keeps the Activity feed clean.

**The Org-Wide Email Address Requirement:**

```apex
List<OrgWideEmailAddress> oweas = [SELECT Id FROM OrgWideEmailAddress WHERE IsVerified = true LIMIT 1];
if (!oweas.isEmpty()) {
    msg.setOrgWideEmailAddressId(oweas[0].Id);
}
```

When an email is sent from an interactive user session, Salesforce uses that user's email address as the `From`. But in CDC async context, the running user is "Automated Process" with email `noreply@<orgId>` — a fake internal address. Sending from this address causes SPF/DKIM authentication failure at the receiving mail server, resulting in the email being silently dropped.

By using a verified Org-Wide Email Address, every notification email always goes out from `prajwal.pandgale@hypermatica.com` — a real, authenticated address — regardless of which user context triggered it.

**Ordered Recipients for Result Mapping:**

```apex
List<Id> orderedRecipients = new List<Id>();
// ...build emails list in same order...
List<Messaging.SendEmailResult> sendResults = Messaging.sendEmail(emails, false);

// Results are returned in the SAME ORDER as the emails list
for (Integer i = 0; i < orderedRecipients.size(); i++) {
    Id recipientId = orderedRecipients[i];
    Messaging.SendEmailResult r = sendResults[i];
    // Map result back to recipient
}
```

`Messaging.sendEmail()` returns results in the same positional order as the input list. Using an ordered `List<Id>` (not a `Set<Id>`) preserves this alignment so each result maps back to the correct recipient.

---

### LogService

**File:** `force-app/main/default/classes/core/LogService.cls`  
**Access Modifier:** `public without sharing`  
**Purpose:** Writes `NotificationLog__c` records as a permanent audit trail

```apex
NotificationLog__c log = new NotificationLog__c();
log.Rule__c           = rule.Id;       // which rule fired
log.Channel__c        = channel.Id;    // which channel delivered
log.Record_Id__c      = recordId;      // which record triggered it
log.Channel_Type__c   = 'Email';       // delivery mechanism
log.Recipient_User__c = recipientId;   // who received it
log.Status__c         = 'Sent';        // or 'Failed'
log.Sent_At__c        = DateTime.now();
```

**SOQL Query to See All Logs:**

```sql
SELECT 
    Rule__r.Rule_Label__c,
    Channel__r.Name,
    Channel_Type__c,
    Recipient_User__r.Name,
    Recipient_User__r.Email,
    Record_Id__c,
    Status__c,
    Sent_At__c,
    Error_Message__c,
    CreatedDate
FROM NotificationLog__c
ORDER BY CreatedDate DESC
LIMIT 50
```

---

## 7. Key Salesforce Concepts Explained

### `with sharing` vs `without sharing`

Salesforce has a security model called **Record-Level Security** (also called "Sharing Rules"). It controls which records a user can see based on their role, profile, and sharing configurations.

**`with sharing`** — The class respects the running user's sharing rules. If the user can only see their own records, the class will only see those records too.

**`without sharing`** — The class bypasses sharing rules entirely and can access all records. This is sometimes called "system context."

In this framework, most classes use `without sharing` because:

```
AccountChangeEventTrigger fires as "Automated Process" user
    ↓
Automated Process has no sharing rules
    ↓
If classes used "with sharing", they'd see ZERO records
    ↓
Framework would silently fail every time
```

`RecordQueryService` is the exception — it uses `with sharing` to respect FLS (Field-Level Security) when querying field lists, ensuring sensitive fields are never accidentally exposed.

---

### `global` vs `public`

**`public`** — Accessible within the same Salesforce org.

**`global`** — Accessible from anywhere, including managed packages installed in customer orgs.

As an ISV (Independent Software Vendor) building a product, we use `global` on:
- Interfaces (`IChannelHandler`, `IConditionEvaluator`, `IRecipientResolver`)
- Context classes (`EvaluationContext`, `RecipientContext`, `NotificationPayload`)
- Handler/Evaluator/Resolver implementations

This means a customer who installs this as a managed package can:
1. Write their own `IConditionEvaluator` in their org
2. Reference it by class name in `Condition_Class__c`
3. The framework will call their custom code without any package modification

---

### Interfaces and `Type.forName()`

An **interface** in Apex (and most object-oriented languages) is a contract — it defines what methods a class MUST have, without defining how those methods work.

```apex
// The contract
global interface IConditionEvaluator {
    Boolean evaluate(EvaluationContext ctx);
}

// One implementation
global class FieldChangedEvaluator implements IConditionEvaluator {
    global Boolean evaluate(EvaluationContext ctx) {
        // checks if a specific field changed to a specific value
    }
}

// Another possible implementation
global class PriceThresholdEvaluator implements IConditionEvaluator {
    global Boolean evaluate(EvaluationContext ctx) {
        // checks if Amount > 100000
    }
}
```

The Router only knows about `IConditionEvaluator`. It doesn't know (or care) which specific class it's calling:

```apex
// The magic line — loads ANY class that implements IConditionEvaluator
IConditionEvaluator evaluator = 
    (IConditionEvaluator) Type.forName(rule.Condition_Class__c).newInstance();
```

`Type.forName("FieldChangedEvaluator")` looks up the class named "FieldChangedEvaluator" at runtime and returns a `Type` object. `.newInstance()` creates a new instance of it. Casting to `IConditionEvaluator` works because `FieldChangedEvaluator implements IConditionEvaluator`.

**The power:** The `Condition_Class__c` field in the rule record is just a String. Change the String from `"FieldChangedEvaluator"` to `"PriceThresholdEvaluator"` and the framework calls completely different logic — no code deployment required.

---

### CDC (Change Data Capture) vs Traditional Triggers

| Feature | Traditional Trigger | CDC Trigger |
|---------|-------------------|-------------|
| Runs when | Immediately during the user's transaction | Asynchronously, in a separate background transaction |
| Running user | The actual user who made the change | "Automated Process" system user |
| Performance impact | Slows down the user's save operation | Zero impact on user's experience |
| Changed field access | `Trigger.new` vs `Trigger.old` | `ChangeEventHeader.changedFields` |
| Full record | `Trigger.new` has the full record | Must re-query — only changed fields in the event |
| Bulk support | Up to 200 records per transaction | Up to 2,000 events per batch |
| Context | Synchronous — can DML in same transaction | Asynchronous — separate transaction |

**Why CDC for notifications?**

Notifications should never slow down a user's ability to save a record. If an email takes 500ms to send, a traditional trigger would make the user wait 500ms on every save. CDC moves this work to the background — the user's save completes instantly and the email arrives seconds later.

---

## 8. Interfaces — The Extensibility Engine

The framework has three core interfaces. Together they make the system infinitely extensible.

### IConditionEvaluator

```apex
global interface IConditionEvaluator {
    Boolean evaluate(EvaluationContext ctx);
}
```

**What it does:** Decides whether the business condition for firing a notification is met.

**Built-in implementation:** `FieldChangedEvaluator`

**Custom implementation example:** 
```
"Only fire if the Account's Annual Revenue > $1M"
→ Write RevenueThresholdEvaluator implements IConditionEvaluator
→ Set Condition_Class__c = "RevenueThresholdEvaluator" on the rule
→ No framework code changes needed
```

**EvaluationContext contains:**
- `newRecord` — the full SObject after the change
- `oldRecord` — null (not available in CDC context; use changedFields instead)
- `changedFields` — Set of field API names that changed
- `rule` — the NotificationRule__c record
- `config` — parsed JSON from `Condition_Config__c`

---

### IRecipientResolver

```apex
global interface IRecipientResolver {
    Set<Id> resolve(RecipientContext ctx);
}
```

**What it does:** Determines which Salesforce User IDs should receive the notification.

**Built-in implementation:** `OwnerResolver`

**Custom implementation examples:**
```
"Notify all users in the Account's Territory"
→ Write TerritoryResolver implements IRecipientResolver

"Notify users who are watching/following this record"  
→ Write FollowerResolver implements IRecipientResolver

"Notify a specific named user"
→ Write StaticUserResolver implements IRecipientResolver
```

**RecipientContext contains:**
- `record` — the full SObject
- `rule` — the NotificationRule__c record
- `config` — parsed JSON from `Recipient_Config__c` (plus injected `commitUserId`)

**Returning an empty set** means "no recipients" — the notification is silently skipped.

---

### IChannelHandler

```apex
global interface IChannelHandler {
    DeliveryResult send(NotificationPayload payload);
}
```

**What it does:** Delivers the notification through a specific channel.

**Built-in implementation:** `EmailChannelHandler`

**Planned implementations:**
```
BellChannelHandler  → Salesforce in-app bell notification
SlackChannelHandler → Slack message via Salesforce Flow or HTTP callout
TeamsChannelHandler → Microsoft Teams webhook
SMSChannelHandler   → SMS via Twilio callout
```

**NotificationPayload contains:**
- `ruleId` / `channelId` / `recordId` — IDs for reference
- `recipientIds` — Set of User IDs to notify
- `subject` — rendered subject line (tokens already resolved)
- `body` — rendered body (tokens already resolved)
- `bodyIsHtml` — whether body is HTML
- `channelConfig` — parsed JSON from `Channel_Config__c`
- `mergeContext` — full token map (for handlers that need raw values)

---

## 9. How Recipients Are Found

This is one of the most important parts of the framework. Understanding recipient resolution prevents common configuration mistakes.

### The Resolution Chain

```
NotificationRouter.resolveRecipients()
    │
    │ reads rule.Recipient_Resolver_Class__c = "OwnerResolver"
    │ reads rule.Recipient_Config__c = {} 
    │ injects commitUserId into config
    │
    ▼
Type.forName("OwnerResolver").newInstance()
    │
    ▼
OwnerResolver.resolve(RecipientContext ctx)
    │
    │ reads ctx.record.get("OwnerId")
    │ checks excludeChangeAuthor config
    │
    ▼
Returns Set<Id> { 005dL00001mJWmPQAW }  ← User ID of Prajwal Pandgale
    │
    ▼
Back in Router: queries User.Email for each recipient ID
    │
    ▼
EmailChannelHandler: sends to prajwal.pandgale@hypermatica.com
```

### What "No Recipients" Means

If `OwnerResolver` returns an empty `Set<Id>`, the Router logs a debug message and **skips** delivery:

```apex
if (recipientIds == null || recipientIds.isEmpty()) {
    System.debug('Router: skip rule — no recipients resolved');
    return;  // exit — no email sent
}
```

Common reasons for empty recipients:
1. `excludeChangeAuthor: true` is set AND the owner changed their own record
2. The `OwnerId` field is null on the record
3. The owner User is inactive (`IsActive = false`)
4. The owner has no email address configured

### The `excludeChangeAuthor` Scenario

```
Config: {"excludeChangeAuthor": true}

Scenario A: Different user changes the Account
  - Owner: Prajwal (005dL...)
  - Changed By: Sujal (006dL...)
  - ownerId ≠ commitUserId → notification IS sent to Prajwal ✅

Scenario B: Owner changes their own Account  
  - Owner: Prajwal (005dL...)
  - Changed By: Prajwal (005dL...)
  - ownerId == commitUserId → notification is SUPPRESSED ❌
```

This prevents the awkward scenario where a user receives a notification about a change they just made themselves.

---

## 10. How the Email Is Built and Sent

### Complete Token Resolution Flow

```
Template Body (stored in NotificationTemplate__c):
─────────────────────────────────────────────────
<p>Hi {{{Owner_Name}}},</p>
<p>The account <strong>{{{Account_Name}}}</strong> is a Customer.</p>
<p>Industry: {{{Industry}}}</p>
<p>Updated by: {{{Changed_By}}}</p>

                    ↓  TemplateEngine.render()

Merge Context (built by NotificationRouter.buildMergeContext()):
────────────────────────────────────────────────────────────────
{
  "Owner_Name":    "Prajwal Pandgale",
  "Account_Name":  "CDC Demo Co",
  "Industry":      "Technology",
  "Changed_By":    "Prajwal Pandgale"
}

                    ↓  token replacement

Rendered Body (sent to EmailChannelHandler):
────────────────────────────────────────────
<p>Hi Prajwal Pandgale,</p>
<p>The account <strong>CDC Demo Co</strong> is a Customer.</p>
<p>Industry: Technology</p>
<p>Updated by: Prajwal Pandgale</p>
```

### Email Authentication — Why It Matters

Salesforce sends emails from its own IP addresses. For these emails to be accepted by Gmail, Outlook, and other providers, the sending domain must be authenticated:

**SPF (Sender Policy Framework):** A DNS record that lists which IP addresses are allowed to send email for a domain. Salesforce's `sfcustomeremail.com` substitute domain has proper SPF records, so emails sent through Salesforce pass SPF checks.

**DKIM (DomainKeys Identified Mail):** A cryptographic signature on the email that proves it wasn't tampered with in transit.

**What failed before the fix:** The email was being sent FROM `pandgale.prajwal11@gmail.com` (the org owner's Gmail address) through Salesforce's servers. Gmail's servers refused it because: "An email claiming to be from @gmail.com must come from Gmail's servers, not from IP 15.207.96.24 (Salesforce)."

**The fix:** 
1. Changed user email in Salesforce to `prajwal.pandgale@hypermatica.com`
2. Created a verified Org-Wide Email Address for the same address
3. The framework uses `msg.setOrgWideEmailAddressId(owea.Id)` to ensure emails always go out from this verified address, regardless of which system user is executing the code

---

## 11. The Final Email — What It Looks Like

After all processing, the recipient receives a professionally formatted HTML email:

```
FROM:    Notifications <email@00ddl00000wwozzuas.sfcustomeremail.com>
TO:      Prajwal Pandgale <prajwal.pandgale@hypermatica.com>
SUBJECT: CDC Demo Co is now a Customer — Welcome!
```

**Visual Layout:**

```
┌──────────────────────────────────────────────────────┐
│  Notification Framework              [ACCOUNT UPDATE] │  
│  (Blue header, white text)                            │
├──────────────────────────────────────────────────────┤
│  ✓  Account status updated successfully               │
│  (Light blue banner with blue left border)            │
├──────────────────────────────────────────────────────┤
│                                                      │
│  Hi Prajwal Pandgale,                                │
│                                                      │
│  Great news! The account CDC Demo Co has been        │
│  updated to Customer status. Please review the       │
│  details below and take the necessary follow-up      │
│  action.                                             │
│                                                      │
│  ┌─ ACCOUNT DETAILS ──────────────────────────────┐  │
│  │  Account Name  │  CDC Demo Co                  │  │
│  │  Industry      │  Technology                   │  │
│  │  Annual Revenue│  1500000                      │  │
│  │  Updated By    │  Prajwal Pandgale              │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  ⚠ Action Required: Please follow up within          │
│    24 hours to schedule an onboarding call.          │
│  (Amber banner with left border)                     │
│                                                      │
├──────────────────────────────────────────────────────┤
│  Sent by Notification Framework      © 2026 Hypermatica│
└──────────────────────────────────────────────────────┘
```

**Design Decisions:**
- Table-based layout (not CSS flexbox/grid) — required for Outlook compatibility
- All CSS is inline — Gmail strips `<style>` block tags
- Max width 600px — standard email width for all clients
- Salesforce blue `#0070D2` — consistent with the platform brand
- Amber action banner — draws attention to the call-to-action without being alarming

---

## 12. Audit Trail — NotificationLog__c

Every notification attempt — success or failure — creates a permanent record.

### Fields

| Field | API Name | Description |
|-------|----------|-------------|
| Rule | `Rule__c` | Which rule triggered this notification |
| Channel | `Channel__c` | Which delivery channel was used |
| Source Record ID | `Record_Id__c` | ID of the Account (or other object) that changed |
| Channel Type | `Channel_Type__c` | Email, Bell, etc. |
| Recipient | `Recipient_User__c` | The User who was notified |
| Status | `Status__c` | "Sent" or "Failed" |
| Sent At | `Sent_At__c` | Exact timestamp of successful delivery |
| Error Message | `Error_Message__c` | Details of failure if Status = "Failed" |

### Audit Query — All Sent Emails

```sql
SELECT 
    Rule__r.Rule_Label__c,
    Recipient_User__r.Name,
    Recipient_User__r.Email,
    Record_Id__c,
    Status__c,
    Sent_At__c,
    CreatedDate
FROM NotificationLog__c
WHERE Channel_Type__c = 'Email'
AND Status__c = 'Sent'
ORDER BY Sent_At__c DESC
```

### Count Notifications by Rule

```sql
SELECT Rule__r.Rule_Label__c, COUNT(Id) total
FROM NotificationLog__c
GROUP BY Rule__r.Rule_Label__c
ORDER BY COUNT(Id) DESC
```

### Check Daily Email Usage (Apex)

```apex
for (System.OrgLimit lim : OrgLimits.getAll()) {
    if (lim.getName().containsIgnoreCase('Email')) {
        System.debug(lim.getName() 
            + ' Used: ' + lim.getValue() 
            + ' / Max: ' + lim.getLimit());
    }
}
// SingleEmail — Used: 1 / Max: 15 (Developer Edition)
```

---

## 13. Troubleshooting Guide

### Email Not Arriving

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `EMAIL_QUEUE` in debug log but no email received | Gmail blocking `@gmail.com` from non-Gmail servers | Change user email to a non-Gmail address |
| `Email limit exceeded` error | Hit daily org email limit (15/day on Developer Edition) | Wait for midnight GMT reset |
| No `EMAIL_QUEUE` in debug log | CDC didn't fire or rule filtered out | Check rule Active__c, field names, condition config |
| `useSignature: true` in EMAIL_QUEUE | Handler not calling `setUseSignature(false)` | Already fixed — redeploy EmailChannelHandler |
| Bounce: `550-5.7.26 unauthenticated` | Sending from unverified domain | Configure Org-Wide Email Address |

### CDC Not Firing

1. Verify CDC is enabled: Setup → Change Data Capture → ensure Account is checked
2. Check trigger is deployed: Setup → Apex Triggers → `AccountChangeEventTrigger` is Active
3. Look for logs from user "Automated Process" in Setup → Debug Logs
4. Ensure the Account field you changed is in the CDC tracked fields

### Rule Not Matching

Check in this order:
1. Is the rule `Active__c = true`?
2. Does `Object_API_Name__c` exactly match "Account" (case matters)?
3. Does `Trigger_Event__c` match "UPDATE"?
4. Is the changed field in `Watched_Fields__c`?
5. Does `Condition_Config__c` contain valid JSON?
6. Does the evaluator class name in `Condition_Class__c` match exactly?

### Tokens Not Resolving

If `{{{Owner_Name}}}` appears in the email body unresolved:
1. Check the field `OwnerId` is populated on the Account
2. Check the Owner User has a `Name` field populated
3. Verify `buildMergeContext` is adding the `Owner_Name` key
4. Token lookup is case-insensitive — `{{{owner_name}}}` also works

---

## 14. How to Add a New Rule (Configuration Guide)

To add a notification for a **different scenario** (e.g., "Notify team when Opportunity Stage = Closed Won"):

### Step 1: Create the Template

1. Go to **Notification Templates** tab
2. Click **New**
3. Fill in:
   - Name: `Opportunity Closed Won Alert`
   - Subject: `{{{Name}}} closed — Congratulations!`
   - Body: `<p>Hi {{{Owner_Name}}},<br/>Great news! Opportunity {{{Name}}} worth {{{Amount}}} was closed successfully.</p>`
   - Body Is HTML: checked
   - Language: English

### Step 2: Create the Rule

1. Go to **Notification Rules** tab
2. Click **New**
3. Fill in:
   - Rule Label: `Notify Owner on Opp Closed Won`
   - Object API Name: `Opportunity`
   - Trigger Event: `UPDATE`
   - Watched Fields: `StageName`
   - Condition Class: `FieldChangedEvaluator`
   - Condition Config: `{"field": "StageName", "value": "Closed Won"}`
   - Recipient Resolver Class: `OwnerResolver`
   - Active: checked

### Step 3: Create the Channel

1. Go to **Notification Channels** tab
2. Click **New**
3. Fill in:
   - Name: `Opp Closed Won Email`
   - Rule: (select the rule you just created)
   - Template: (select the template you just created)
   - Channel Type: `Email`
   - Active: checked

### Step 4: Enable CDC for Opportunity

1. Setup → Change Data Capture → check **Opportunity**
2. Create a CDC trigger:

```apex
trigger OpportunityChangeEventTrigger on OpportunityChangeEvent (after insert) {
    NotificationDispatcher.dispatch(Trigger.new, 'Opportunity');
}
```

That's it — no other code changes needed.

---

## 15. Glossary of Terms

| Term | Definition |
|------|-----------|
| **CDC** | Change Data Capture — Salesforce feature that publishes events when records change |
| **Platform Event** | A Salesforce messaging mechanism for publishing/subscribing to events |
| **Automated Process** | The system user that runs CDC triggers — has no sharing rules or real email address |
| **DML** | Data Manipulation Language — INSERT, UPDATE, DELETE operations on Salesforce records |
| **SOQL** | Salesforce Object Query Language — like SQL but for Salesforce objects |
| **Governor Limits** | Salesforce resource limits per transaction (100 SOQL, 150 DML, 10 emails, etc.) |
| **SObject** | Generic Salesforce object type — parent class of Account, Contact, any custom object |
| **with sharing** | Enforces record-level security for the running user |
| **without sharing** | Bypasses record-level security — runs in system context |
| **global** | Accessible across managed package boundaries — required for ISV extensibility |
| **public** | Accessible within the same org/namespace only |
| **Interface** | A contract specifying which methods a class must implement |
| **Type.forName()** | Apex reflection — instantiates a class by its name stored as a String |
| **Merge Context** | Map of token names to values used by TemplateEngine to resolve `{{{tokens}}}` |
| **OWEA** | Org-Wide Email Address — a verified From address usable in any user context |
| **SPF** | Sender Policy Framework — DNS record authorizing which IPs can send for a domain |
| **DKIM** | DomainKeys Identified Mail — cryptographic email signature for anti-spoofing |
| **FLS** | Field-Level Security — Salesforce permission controlling which fields a user can read/edit |
| **ISV** | Independent Software Vendor — company building apps for the Salesforce AppExchange |
| **RuleBundle** | Inner class in RuleCache grouping one rule with all its active channels |
| **Token** | A `{{{placeholder}}}` in a template that gets replaced with a real value at send time |
| **Cooldown** | Minimum time between repeat notifications for the same rule+record+channel combination |
| **SEM Mode 2** | Salesforce email mode using setHtmlBody/setPlainTextBody instead of setTemplateId |
| **Commit User** | The Salesforce User whose save action triggered the CDC event |

---

*End of Documentation*

*Framework built by Prajwal Pandgale — Hypermatica, May 2026*  
*Org: NotificationsDev (prajwal.pandgale.platform@agentforce.com)*
