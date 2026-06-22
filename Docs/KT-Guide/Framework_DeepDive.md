# Notification Framework — Deep Dive Explanation
## From CDC Basics to Email Delivery — Everything Explained Simply

**Project:** notification-framework-salesforce  
**Author:** Prajwal Pandgale — Hypermatica  

---

## How to Use This Document

Read this document from top to bottom. Each section builds on the previous one. By the end, you will understand exactly what happens — step by step — from the moment a user saves an Account record in Salesforce to the moment a formatted email lands in someone's inbox.

No prior Salesforce experience is required. Every concept is explained from scratch before it is used.

---

## Chapter 1 — The Problem This Framework Solves

Imagine you work at a company that uses Salesforce. Your sales team updates Account records constantly — changing the Type, updating the Address, closing deals. And every time a specific change happens, someone needs to be notified.

For example:
- When an Account's Type changes to "Customer - Direct" → the Account Owner should receive a welcome email
- When an Opportunity is Closed Won → the Sales Manager should be notified
- When a Case is escalated → the support lead should get an alert

The traditional way to build this in Salesforce is to write an Apex trigger for each scenario. Every new requirement means a developer writes code, gets it reviewed, tested, and deployed. This takes days.

**This framework solves that.** Once the framework is built and deployed, adding a brand new notification takes 5 minutes — no code, no deployment. An admin creates three records in the Salesforce UI and it works.

That is the core promise of this framework.

---

## Chapter 2 — What Is Salesforce and Why Does Any of This Matter?

Salesforce is a cloud-based CRM (Customer Relationship Management) platform. Businesses store their customers (Accounts), deals (Opportunities), support tickets (Cases), and more in Salesforce.

Salesforce allows developers to write **Apex** — a Java-like programming language — to add custom business logic. When a record is saved, Apex can run automatically to do things like send emails, update other records, or call external systems.

This framework is entirely built in Apex and runs on the Salesforce platform.

---

## Chapter 3 — What Is a Trigger?

Before understanding CDC, you need to understand a regular Salesforce trigger.

A **trigger** is a piece of Apex code that runs automatically when a record is created, updated, or deleted.

```
User saves an Account
        ↓
Salesforce saves the record to the database
        ↓
Trigger fires automatically
        ↓
Your Apex code runs
```

Think of it like a motion sensor light. The motion sensor does not know or care who walks in — it just detects movement and turns the light on. Similarly, a trigger does not know who saved the record — it just fires when a save happens.

**The problem with regular triggers for notifications:**

When a trigger sends an email, that email is sent during the same transaction as the user's save. This means:

```
User clicks Save
        ↓
Salesforce runs trigger
        ↓
Trigger sends email (takes 300-500 milliseconds)
        ↓
User sees "Record saved" ← user waited 500ms extra
```

For one user this is barely noticeable. But if 50 users are saving Accounts simultaneously, every one of them waits. The system slows down.

There is a better way — **CDC**.

---

## Chapter 4 — What Is CDC (Change Data Capture)?

**CDC stands for Change Data Capture.**

CDC is a Salesforce feature that publishes a special background message — called a **Platform Event** — whenever a record changes. Your code subscribes to this message and processes it in a separate background transaction.

Here is the key difference:

```
WITHOUT CDC (regular trigger):
User clicks Save → Save + Trigger + Email → User waits

WITH CDC:
User clicks Save → Save → User sees success instantly
                        ↓ (background, milliseconds later)
                   CDC event fires → Framework processes → Email sent
```

The user's experience is completely unaffected. The email goes out in the background.

### How CDC Works — The Newspaper Analogy

Think of it like a newspaper subscription:

- The **newspaper press** = Salesforce (publishes the event)
- The **newspaper** = `AccountChangeEvent` (the event itself)
- The **subscriber** = our `AccountChangeEventTrigger` (receives the event)
- The **delivery time** = after the user's save completes

When you change an Account, Salesforce "prints" an `AccountChangeEvent` and "delivers" it to our trigger automatically.

### What Is Inside an AccountChangeEvent?

The `AccountChangeEvent` does NOT contain the full Account record. It only contains:

```
ChangeEventHeader:
  changeType:    "UPDATE"           ← What kind of change happened
  changedFields: ["Type", "LastModifiedDate"]  ← Which fields changed
  recordIds:     ["001dL00002C1LiR"] ← Which record changed
  commitUser:    "005dL00001mJWmP"  ← Who made the change
```

Notice: it only tells you WHAT changed, not the full record values. This is why the framework must re-query the full Account record separately.

### How to Enable CDC

In Salesforce Setup → Change Data Capture → tick the checkbox next to "Account". That single action makes Salesforce start publishing `AccountChangeEvent` for every Account change.

---

## Chapter 5 — The Three Configuration Records

The entire behaviour of this framework is driven by three custom Salesforce objects. An admin creates one record in each object to set up a notification rule.

---

### Object 1: NotificationTemplate__c — The Email Design

This object stores the visual design of the email — the subject line and the HTML body.

**Key concept — Tokens:**

The template does not store hardcoded values. Instead, it uses tokens — placeholders wrapped in triple curly braces:

```
Subject: {{{Account_Name}}} is now a Customer — Welcome!
Body:    Hi {{{Owner_Name}}}, The account {{{Account_Name}}} 
         has been updated...
```

When the email is sent, the framework replaces:
- `{{{Account_Name}}}` with the actual account name: `CDC Demo Co`
- `{{{Owner_Name}}}` with the owner's name: `Prajwal Pandgale`

One template serves every Account in the org. The tokens make it dynamic.

**Available tokens:**

| Token | Resolves To |
|-------|------------|
| `{{{Account_Name}}}` | The Account's Name field |
| `{{{Owner_Name}}}` | Full name of the Account owner |
| `{{{Industry}}}` | The Industry field |
| `{{{AnnualRevenue}}}` | The Annual Revenue field |
| `{{{Changed_By}}}` | Name of the user who made the change |
| `{{{Type}}}` | The Type field |

Any field on the Account object can be used as a token.

---

### Object 2: NotificationRule__c — When to Fire

This object defines the conditions under which a notification should be sent.

Think of it as the rulebook: "Send a notification WHEN these conditions are all true."

**Key fields:**

| Field | Example | Meaning |
|-------|---------|---------|
| Object API Name | `Account` | Watch the Account object |
| Trigger Event | `UPDATE` | Only fire on updates |
| Watched Fields | `Type` | Only care if the Type field changed |
| Active | `true` | This rule is currently enabled |
| Condition Class | `FieldChangedEvaluator` | Apex class that checks advanced conditions |
| Condition Config | `{"field":"Type","value":"Customer - Direct"}` | Config passed to the condition class |
| Recipient Resolver Class | `OwnerResolver` | Apex class that finds who to notify |
| Cooldown Minutes | `60` | Don't re-fire for the same record within 60 minutes |

**Three layers of filtering:**

Before any notification fires, the rule must pass all three of these checks:

```
Check 1: Does the object and event match?
         Account + UPDATE → YES ✅

Check 2: Did at least one watched field change?
         "Type" is in changedFields → YES ✅

Check 3: Does the condition evaluator pass?
         Did Type specifically become "Customer - Direct"? → YES ✅

All three passed → SEND NOTIFICATION
Any one fails → SKIP, do nothing
```

---

### Object 3: NotificationChannel__c — How to Deliver

This object is the bridge. It connects a Rule to a Template and specifies the delivery method.

**Key fields:**

| Field | Example | Meaning |
|-------|---------|---------|
| Rule | (lookup to NR-0000) | Which rule triggers this channel |
| Template | (lookup to template) | Which template to use |
| Channel Type | `Email` | Deliver via email |
| Active | `true` | This channel is currently enabled |
| Channel Config | `{"senderDisplayName":"Notifications"}` | Channel-specific settings |

**One Rule, Multiple Channels:**

A single rule can have multiple channel records:

```
Rule: "Notify on Account Type Change"
    ├── Channel: Email → sends email to owner
    └── Channel: Bell → creates in-app notification
```

Both channels fire for the same rule trigger. You add more channels by creating more NotificationChannel__c records — no code changes needed.

---

### How the Three Records Connect

```
NotificationRule__c
"Notify Owner on Account Type Change"
(watches Account TYPE field for "Customer - Direct")
         │
         │ Rule__c lookup
         ▼
NotificationChannel__c
"NC-0000" — Type: Email
         │
         │ Template__c lookup
         ▼
NotificationTemplate__c
"Account Customer Welcome Email"
Subject: {{{Account_Name}}} is now a Customer — Welcome!
Body: Full HTML email design
```

---

## Chapter 6 — The Complete Code Flow

Now let's trace exactly what happens step by step when a user changes an Account's Type to "Customer - Direct" and clicks Save.

---

### Step 1: User Saves the Account

A Salesforce user edits the "CDC Demo Co" account:
- Changes **Type** from `Prospect` to `Customer - Direct`
- Clicks **Save**

The Account record is immediately saved to the Salesforce database. The user sees success. So far, the notification framework has not run at all.

---

### Step 2: Salesforce Publishes AccountChangeEvent

Milliseconds after the save, Salesforce's CDC system publishes an `AccountChangeEvent` to the event bus:

```
AccountChangeEvent published:
  changeType:    UPDATE
  changedFields: [Type, LastModifiedDate]
  recordIds:     [001dL00002C1LiR]
  commitUser:    005dL00001mJWmP   ← Prajwal Pandgale's User ID
```

This event sits in Salesforce's event bus — a message queue — waiting to be processed.

---

### Step 3: AccountChangeEventTrigger Fires

Our Apex trigger is subscribed to `AccountChangeEvent`. Salesforce delivers the event and fires the trigger automatically:

```apex
trigger AccountChangeEventTrigger on AccountChangeEvent (after insert) {
    NotificationDispatcher.dispatch(Trigger.new, 'Account');
}
```

The trigger's entire job is one line: pass the events to `NotificationDispatcher`. It has no business logic of its own.

**Important:** This trigger runs as the "Automated Process" system user — not as Prajwal Pandgale. The Automated Process user is Salesforce's internal background worker. It has no profile, no sharing rules, and no real email address.

---

### Step 4: NotificationDispatcher Parses the Event

`NotificationDispatcher` receives the raw CDC events and extracts the useful information.

**The Challenge — ChangeEventHeader:**

The event header cannot be read directly in Apex due to a Salesforce platform limitation. The solution is a JSON round-trip:

```
Step 1: Convert the entire event to a JSON string
        JSON.serialize(evt) 
        → '{"ChangeEventHeader":{"changeType":"UPDATE","changedFields":["Type"],...}}'

Step 2: Convert JSON string back to a plain Map
        JSON.deserializeUntyped(jsonString)
        → Map { "ChangeEventHeader" → Map { "changeType" → "UPDATE", ... } }

Step 3: Read values safely from the map
        header.get("changeType")    → "UPDATE"
        header.get("changedFields") → ["Type", "LastModifiedDate"]
        header.get("commitUser")    → "005dL00001mJWmP"
```

After parsing, the Dispatcher calls `RecordQueryService` to fetch the full Account record.

---

### Step 5: RecordQueryService Fetches the Full Record

CDC only tells us WHAT changed — not what the current values are. `RecordQueryService` dynamically builds and runs a SOQL query to get the complete Account:

```sql
SELECT id, name, type, industry, annualrevenue, ownerid, ...all fields...
FROM Account
WHERE Id = '001dL00002C1LiR'
```

**Why dynamic SOQL?**  
Instead of hardcoding field names, the class uses Salesforce's Schema API to get every accessible field on the Account object automatically. This means the query always includes all fields, even custom ones added later.

**Why "accessible" fields?**  
The class uses `with sharing` to respect Salesforce's Field-Level Security. Only fields the running context can read are included — protecting sensitive data.

---

### Step 6: NotificationRouter — The Brain

The Router is the most important class. It receives the full Account record and orchestrates all the filtering and delivery logic.

**First, it asks RuleCache for matching rules:**

`RuleCache` holds all active notification rules in a static in-memory map. On the first call in a transaction, it loads all rules from the database in two queries:

```
Query 1: All active NotificationRule__c records
Query 2: All active NotificationChannel__c records with their templates
```

These are stored in a Map like this:
```
"account|update" → [RuleBundle for "Notify Owner on Account Type Change"]
```

The lowercase key `"account|update"` is built from the object name and event type. If 50 Accounts change in one batch, the cache loads rules once and reuses the result 50 times — saving 98 database queries.

**Then the Router runs three filters for each rule:**

---

#### Filter 1: Object + Event Match

The Router looks up rules by the key `"account|update"`. If no rules match this combination, nothing happens. Our rule matches — proceed.

---

#### Filter 2: Watched Field Changed

The rule has `Watched_Fields__c = "Type"`. The Router checks if "Type" is in the list of changed fields reported by CDC:

```
CDC reported changedFields: ["Type", "LastModifiedDate"]
Rule watchedFields: "Type"

Is "Type" in changedFields? → YES ✅ Proceed
```

If only `LastModifiedDate` had changed and not `Type`, the rule would stop here and no notification would be sent.

---

#### Filter 3: Condition Evaluator

This is the advanced filter. The Router reads `Condition_Class__c = "FieldChangedEvaluator"` and loads that class dynamically:

```apex
IConditionEvaluator evaluator = 
    (IConditionEvaluator) Type.forName("FieldChangedEvaluator").newInstance();
Boolean passed = evaluator.evaluate(context);
```

`Type.forName()` is Apex's way of loading a class by its name stored as text. This is called **reflection** — the code doesn't know which evaluator class it's calling until the exact moment it runs. The class name comes from the database record.

**Inside FieldChangedEvaluator:**

The evaluator receives:
- `config = {"field": "Type", "value": "Customer - Direct"}`
- `changedFields = {"Type", "LastModifiedDate"}`
- `newRecord = Account with Type = "Customer - Direct"`

It checks three things in order:

```
Step 1: Is "Type" in changedFields?
        YES → continue

Step 2: Is there an expected value configured?
        YES ("Customer - Direct") → continue

Step 3: Does the actual field value match?
        Account.Type = "Customer - Direct"
        Expected     = "Customer - Direct"
        Match? → YES ✅
```

All three pass. Condition evaluator returns `true`. Proceed to recipient resolution.

---

### Step 7: OwnerResolver Finds the Recipient

The Router reads `Recipient_Resolver_Class__c = "OwnerResolver"` and loads it the same way:

```apex
IRecipientResolver resolver = 
    (IRecipientResolver) Type.forName("OwnerResolver").newInstance();
Set<Id> recipientIds = resolver.resolve(context);
```

**Inside OwnerResolver:**

The resolver reads the `OwnerId` field from the Account record:
```
Account.OwnerId = "005dL00001mJWmP" (Prajwal Pandgale)
```

It also checks the optional `excludeChangeAuthor` config. If this is `true` AND the owner is the same person who made the change, the notification is suppressed. Why? To avoid notifying someone about a change they just made themselves.

In our case, the config is empty so no suppression occurs.

Result: `recipientIds = { "005dL00001mJWmP" }` — Prajwal Pandgale will be notified.

---

### Step 8: Building the Merge Context

Before rendering the template, the Router builds the **merge context** — a dictionary of all available token values:

```
Step 1: Copy all Account field values
        { "Id" → "001dL...", "Name" → "CDC Demo Co", "Type" → "Customer - Direct",
          "Industry" → "Technology", "AnnualRevenue" → "1500000", ... }

Step 2: Add a friendly alias for the Account name
        { "Account_Name" → "CDC Demo Co" }
        (so {{{Account_Name}}} works instead of {{{Name}}})

Step 3: Query User records for human-readable names
        Owner → "Prajwal Pandgale"     → add "Owner_Name" → "Prajwal Pandgale"
        CommitUser → "Prajwal Pandgale" → add "Changed_By" → "Prajwal Pandgale"
```

The final merge context looks like:
```
{
  "Account_Name":  "CDC Demo Co",
  "Owner_Name":    "Prajwal Pandgale",
  "Industry":      "Technology",
  "AnnualRevenue": "1500000",
  "Changed_By":    "Prajwal Pandgale",
  "Type":          "Customer - Direct",
  ... all other Account fields ...
}
```

---

### Step 9: TemplateEngine Resolves the Tokens

`TemplateEngine.render()` takes the template body and the merge context and replaces every `{{{token}}}`:

```
Template Subject:
"{{{Account_Name}}} is now a Customer — Welcome!"

After render:
"CDC Demo Co is now a Customer — Welcome!"
```

```
Template Body (simplified):
"Hi {{{Owner_Name}}},
Great news! {{{Account_Name}}} updated.
Industry: {{{Industry}}}
Updated by: {{{Changed_By}}}"

After render:
"Hi Prajwal Pandgale,
Great news! CDC Demo Co updated.
Industry: Technology
Updated by: Prajwal Pandgale"
```

**How it works technically:**

The engine uses a **regex pattern** to find every `{{{...}}}` in the template. For each match, it looks up the token name in the merge context (case-insensitive) and does a text replacement.

If a token has no matching value in the context, it stays as `{{{tokenName}}}` — making it immediately visible that something is missing.

---

### Step 10: EmailChannelHandler Sends the Email

Now everything is assembled. The Router calls `EmailChannelHandler.send()` with the fully rendered subject and body.

**Step 1 — Find the recipient's email address:**
```sql
SELECT Id, Email FROM User WHERE Id = '005dL00001mJWmP' AND IsActive = true
```
Result: `prajwal.pandgale@hypermatica.com`

**Step 2 — Find the Org-Wide Email Address:**
```sql
SELECT Id FROM OrgWideEmailAddress WHERE IsVerified = true LIMIT 1
```

This is critical. The CDC trigger runs as "Automated Process" whose email is `noreply@<orgId>` — a fake internal address. If an email is sent FROM this address, Gmail and other providers reject it because the address doesn't exist on any real mail server.

The Org-Wide Email Address (`prajwal.pandgale@hypermatica.com`) is a verified real address. Using it ensures the email passes SPF authentication checks and actually arrives.

**Step 3 — Build the email message:**
```apex
Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
msg.setToAddresses(['prajwal.pandgale@hypermatica.com']);
msg.setSubject('CDC Demo Co is now a Customer — Welcome!');
msg.setHtmlBody('<html>...full professional HTML...</html>');
msg.setOrgWideEmailAddressId(owea.Id);  // verified From address
msg.setSaveAsActivity(false);  // don't create Activity on the Account
msg.setUseSignature(false);    // don't append user's email signature
```

**Why `setSaveAsActivity(false)`?**  
By default, Salesforce logs every sent email as an Activity (Task) on the related record. For automated framework notifications, this would create hundreds of Task records on Accounts — cluttering the Activity feed.

**Why `setSaveAsActivity(false)`?**  
Every Salesforce user can set a personal email signature. Without this flag, the Automated Process user's signature (which may contain system text or be empty) gets appended to every notification email.

**Step 4 — Send in one batch:**
```apex
List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
// false = allow partial failures, don't throw exception if one fails
```

Salesforce processes the email, authenticates it through sfcustomeremail.com (its sending domain with proper SPF records), and delivers it to `prajwal.pandgale@hypermatica.com`.

---

### Step 11: LogService Records the Result

After sending, the Router calls `LogService.log()` which writes a `NotificationLog__c` record:

```
NotificationLog__c {
  Rule:           "Notify Owner on Account Type Change"
  Channel:        "NC-0000"
  Record ID:      "001dL00002C1LiR"  (CDC Demo Co)
  Channel Type:   "Email"
  Recipient:      Prajwal Pandgale
  Status:         "Sent"
  Sent At:        2026-05-30 10:16:00
}
```

This record is permanent proof that the notification was sent, to whom, through which channel, at what exact time.

---

## Chapter 7 — The Complete Picture

Here is the full flow in one diagram:

```
USER CHANGES Account Type → "Customer - Direct"
            │
            │ (instant — user sees success)
            ▼
SALESFORCE SAVES RECORD
            │
            │ (milliseconds later, background)
            ▼
CDC PUBLISHES AccountChangeEvent
  changeType: UPDATE
  changedFields: [Type, LastModifiedDate]
  recordId: 001dL...
  commitUser: 005dL...
            │
            ▼
AccountChangeEventTrigger
  → NotificationDispatcher.dispatch()
            │
            ▼
NotificationDispatcher
  → Parse event via JSON round-trip
  → Extract: changeType, changedFields, commitUserId, recordId
  → RecordQueryService.queryByIds("Account", {recordId})
            │
            ▼
RecordQueryService
  → Dynamic SOQL: SELECT all fields FROM Account WHERE Id = recordId
  → Returns full Account record
            │
            ▼
NotificationRouter.route()
  → RuleCache.getRules("Account", "UPDATE")
     → loads all active rules (2 SOQL, cached for transaction)
  → Found: "Notify Owner on Account Type Change"
            │
            ├─ Filter 2: watchedFieldChanged("Type", changedFields) → TRUE ✅
            │
            ├─ Filter 3: FieldChangedEvaluator.evaluate()
            │   config: {"field":"Type","value":"Customer - Direct"}
            │   actual: Account.Type = "Customer - Direct"
            │   → TRUE ✅
            │
            ├─ OwnerResolver.resolve()
            │   reads Account.OwnerId → 005dL... (Prajwal Pandgale)
            │   → recipientIds = {005dL...}
            │
            ├─ buildMergeContext(record, commitUserId)
            │   → {Account_Name, Owner_Name, Industry, AnnualRevenue, Changed_By, ...}
            │
            ├─ TemplateEngine.render(subject, mergeContext)
            │   → "CDC Demo Co is now a Customer — Welcome!"
            │
            ├─ TemplateEngine.render(body, mergeContext)
            │   → Full resolved HTML
            │
            └─ EmailChannelHandler.send(payload)
                → Query User email: prajwal.pandgale@hypermatica.com
                → Query OWEA: verified From address
                → Build SingleEmailMessage
                → Messaging.sendEmail([msg], false)
                → Map results back to recipients
                      │
                      ▼
               LogService.log()
               → Insert NotificationLog__c {Status: "Sent", Sent_At: now()}
                      │
                      ▼
               📧 EMAIL ARRIVES IN INBOX
```

---

## Chapter 8 — Key Concepts Summary

### Why `without sharing`?

Most framework classes use `without sharing`. This means they bypass Salesforce's record-level security and can see all records.

This is necessary because CDC runs as the "Automated Process" system user. This user has zero sharing rules configured. If classes used `with sharing`, they would see no records at all and the framework would silently fail every time.

### Why `global` keyword?

The `global` keyword (instead of `public`) means the class or interface is accessible from any Salesforce package — including packages installed by customers.

This framework is built as an ISV (Independent Software Vendor) product. Customers who install it as a managed package need to write their own custom evaluators and resolvers. Making interfaces `global` allows customers to implement them in their own code.

### Why Interfaces?

Interfaces enforce a contract. Any class that implements `IConditionEvaluator` MUST have an `evaluate()` method. Any class that implements `IRecipientResolver` MUST have a `resolve()` method.

The Router only knows about these interfaces — it doesn't know `FieldChangedEvaluator` or `OwnerResolver` exist. It calls `evaluate()` and `resolve()` on whatever class is stored in the database record.

This means anyone can write a new evaluator (e.g., `RevenueThresholdEvaluator`) or a new resolver (e.g., `TerritoryResolver`), deploy it to Salesforce, put its name in the rule record, and the framework calls it automatically. Zero framework code changes.

### Why `Type.forName()`?

`Type.forName("FieldChangedEvaluator").newInstance()` is Apex reflection — loading a class by its name stored as a String.

Without this, the Router would need a hardcoded `if/else` for every possible evaluator:
```apex
// Without reflection — bad approach
if (className == 'FieldChangedEvaluator') {
    evaluator = new FieldChangedEvaluator();
} else if (className == 'RevenueThresholdEvaluator') {
    evaluator = new RevenueThresholdEvaluator();
}
// ... new code needed for every new class
```

With reflection, the Router works with any class that implements the interface — past, present, or future — without ever being modified.

---

## Chapter 9 — The Email Design

The final email uses a professional HTML design built with table-based layout and inline CSS. This approach is necessary because:

- **Table layout** — Email clients like Outlook do not support modern CSS flexbox or grid. Tables are the universal layout method for email.
- **Inline CSS** — Gmail strips `<style>` tags from email HTML. All styling must be directly on each element as `style="..."` attributes.
- **600px max width** — The standard email width that works across all email clients.

### Email Structure

```
┌──────────────────────────────────────────────┐
│  Notification Framework    [ACCOUNT UPDATE]  │  ← Blue header (#0070D2)
├──────────────────────────────────────────────┤
│  ✓  Account status updated successfully      │  ← Blue banner
├──────────────────────────────────────────────┤
│                                              │
│  Hi Prajwal Pandgale,                        │  ← Greeting (token resolved)
│                                              │
│  Great news! CDC Demo Co has been updated    │  ← Main message (token resolved)
│  to Customer status...                       │
│                                              │
│  ┌─ ACCOUNT DETAILS ──────────────────────┐  │
│  │ Account Name  │  CDC Demo Co           │  │  ← Details table
│  │ Industry      │  Technology            │  │
│  │ Annual Revenue│  1500000               │  │
│  │ Updated By    │  Prajwal Pandgale      │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  ⚠ Action Required: Follow up within 24hrs  │  ← Amber action banner
│                                              │
├──────────────────────────────────────────────┤
│  Sent by Notification Framework © 2026 Hyp  │  ← Footer
└──────────────────────────────────────────────┘
```

---

## Chapter 10 — Audit Trail

Every notification attempt — whether it succeeds or fails — creates a permanent `NotificationLog__c` record.

### To Query All Sent Notifications:

```sql
SELECT
    Rule__r.Rule_Label__c,
    Recipient_User__r.Name,
    Recipient_User__r.Email,
    Record_Id__c,
    Channel_Type__c,
    Status__c,
    Sent_At__c,
    Error_Message__c,
    CreatedDate
FROM NotificationLog__c
ORDER BY CreatedDate DESC
LIMIT 50
```

### To Count Notifications by Rule:

```sql
SELECT Rule__r.Rule_Label__c, COUNT(Id) total
FROM NotificationLog__c
GROUP BY Rule__r.Rule_Label__c
ORDER BY COUNT(Id) DESC
```

### To Check How Many Emails Were Sent Today:

Run this in Developer Console → Execute Anonymous:

```apex
for (System.OrgLimit lim : OrgLimits.getAll()) {
    if (lim.getName().containsIgnoreCase('Email')) {
        System.debug(lim.getName()
            + ' — Used: ' + lim.getValue()
            + ' / Max: ' + lim.getLimit()
            + ' / Remaining: ' + (lim.getLimit() - lim.getValue()));
    }
}
```

---

## Chapter 11 — How to Add a New Notification (No Code Required)

To add a notification for any new scenario:

### Step 1: Enable CDC for the Object
Setup → Change Data Capture → tick the checkbox for your object (e.g., Case, Opportunity)

### Step 2: Create a Trigger (2 lines of code — one time only per object)
```apex
trigger CaseChangeEventTrigger on CaseChangeEvent (after insert) {
    NotificationDispatcher.dispatch(Trigger.new, 'Case');
}
```

### Step 3: Create the Template Record
- Go to Notification Templates tab
- Create new record with subject, HTML body, and `{{{tokens}}}`

### Step 4: Create the Rule Record
- Object API Name: `Case`
- Trigger Event: `UPDATE`
- Watched Fields: `Status`
- Condition Class: `FieldChangedEvaluator`
- Condition Config: `{"field": "Status", "value": "Closed"}`
- Recipient Resolver Class: `OwnerResolver`

### Step 5: Create the Channel Record
- Link to the rule and template
- Channel Type: `Email`

Done. No Apex deployment beyond the 2-line trigger.

---

*End of Deep Dive Document*

*Written by Prajwal Pandgale — Hypermatica, June 2026*
