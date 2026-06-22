# Notification Framework — Team Demo Script
## Duration: 20–25 Minutes (Including Q&A)

**Presenter:** Prajwal Pandgale — Hypermatica  
**Audience:** Development / Product Team  
**Date:** June 2026

---

## BEFORE YOU START — Setup Checklist

- [ ] Open Salesforce org (NotificationsDev) in browser
- [ ] Open VS Code with the project
- [ ] Open Debug Logs monitor in Salesforce (Setup → Debug Logs)
- [ ] Have "CDC Demo Co" Account ready with Type = `Prospect`
- [ ] Open email inbox (prajwal.pandgale@hypermatica.com) in another tab
- [ ] Have Notification Templates, Rules, and Channels tabs bookmarked

---

## TIMING BREAKDOWN

| Section | Time |
|---------|------|
| Part 1 — Introduction | 2 min |
| Part 2 — What is CDC | 3 min |
| Part 3 — Three Configuration Records | 5 min |
| Part 4 — Live Demo | 3 min |
| Part 5 — Code Walkthrough | 5 min |
| Part 6 — Q&A | 7 min |
| **Total** | **25 min** |

> **Tip:** If the team is non-technical, spend more time on Parts 2 and 3 and skip Part 5.
> If the team is developers, skip Part 2 and spend more time on Part 5.

---

## PART 1 — INTRODUCTION (2 minutes)

---

> **YOU SAY:**
>
> *"Hey team, today I'm going to walk you through a notification framework that I've built on Salesforce. By the end of this session, you'll understand exactly how — when someone changes a field on an Account — a professionally formatted email automatically lands in the right person's inbox. No manual steps, no hardcoded logic.*
>
> *The best part? If tomorrow you want to add a completely new notification for a different scenario — say, notify someone when a Case is closed — you don't write a single line of new code. You just create three records in the UI. That's the power of this framework.*
>
> *Let me start from the very beginning — what is CDC?"*

---

## PART 2 — WHAT IS CDC? (3 minutes)

---

> **YOU SAY:**
>
> *"CDC stands for Change Data Capture. Let me explain it with a simple analogy.*
>
> *Imagine you have a newspaper subscription. Every morning, the newspaper is delivered to your door automatically — you don't go to the press and ask for it. Whenever something newsworthy happens, the press prints a copy and delivers it.*
>
> *Salesforce CDC works exactly the same way.*
>
> *When someone saves an Account — changes the Type, updates the Address, anything — Salesforce automatically publishes a platform event called `AccountChangeEvent`. Think of this as the newspaper. This event contains exactly three things:*
> - *Which record changed*
> - *Which fields changed*
> - *Who made the change*
>
> *Our framework is the subscriber — it receives this newspaper the moment it's published.*
>
> *Now, here's a critical point. CDC runs asynchronously — meaning it runs in the background, AFTER the user's save is complete. The user clicks Save, the record saves instantly, and then in the background — usually within a second — CDC fires and our framework kicks in.*
>
> *This is important because it means our framework NEVER slows down the user's experience."*

**[ SHOW ON SCREEN ]** Setup → Change Data Capture → Show Account is checked

> *"You can see here that CDC is enabled for Account. This one checkbox is what makes Salesforce start publishing AccountChangeEvent every time an Account changes."*

---

## PART 3 — THE THREE CONFIGURATION RECORDS (5 minutes)

---

> **YOU SAY:**
>
> *"Now, before I show you the code, I want to show you something more important — the configuration. This framework is metadata-driven, which means its entire behaviour is controlled by three records that you create in the UI. Let me show you all three."*

---

### Record 1 — Notification Template

**[ OPEN ]** Notification Templates tab

> *"Record number one — the Notification Template. This is simply the email design. It stores the subject line and the HTML body of the email.*
>
> *Notice this part — `{{{Account_Name}}}`, `{{{Owner_Name}}}`. These are tokens — placeholders. At the time the email is sent, our framework replaces these with actual values from the record. So `{{{Account_Name}}}` becomes 'CDC Demo Co', `{{{Owner_Name}}}` becomes 'Prajwal Pandgale'.*
>
> *This means one template works for every Account in the org — the tokens make it dynamic."*

---

### Record 2 — Notification Rule

**[ OPEN ]** Notification Rules tab

> *"Record number two — the Notification Rule. This is the brain. It answers the question: WHEN should this notification fire?*
>
> *Look at these fields:*
> - *Object API Name = Account — we're watching the Account object*
> - *Trigger Event = UPDATE — only fire on updates, not creates or deletes*
> - *Watched Fields = Type — only care if the Type field changed*
> - *Condition Class = FieldChangedEvaluator — an Apex class that checks if Type specifically became 'Customer - Direct'*
> - *Condition Config = `{"field": "Type", "value": "Customer - Direct"}` — this is the JSON instruction given to the evaluator*
>
> *Three layers of filtering. All three must pass before anything is sent."*

---

### Record 3 — Notification Channel

**[ OPEN ]** Notification Channels tab

> *"Record number three — the Notification Channel. This is the delivery mechanism. It links the Rule to the Template and says: deliver via Email.*
>
> *One rule can have multiple channels. So the same rule could send an Email AND create an in-app bell notification simultaneously. You just add another channel record.*
>
> *That's it — three records. No code written, no deployment done. The framework figures out the rest."*

---

### How the Three Records Connect

```
NotificationRule__c
    "Notify Owner on Account Type Change"
    Object: Account  |  Event: UPDATE
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

## PART 4 — LIVE DEMO (3 minutes)

---

> **YOU SAY:**
>
> *"Now let me trigger this live. I'm going to change the Account Type on 'CDC Demo Co' from Prospect to Customer - Direct and we'll watch what happens."*

**[ DO ]** Open CDC Demo Co → Edit → Change Type to `Customer - Direct` → Save

> *"Account saved. Now watch the debug logs — CDC is firing in the background."*

**[ OPEN ]** Setup → Debug Logs → Refresh → Open latest "Automated Process" log

> *"See this — 'Automated Process' user. That's the system user that runs CDC. Let me scroll through this log and show you exactly what happened."*

**[ POINT TO ]** These key log lines one by one:

| Log Line | What It Means |
|----------|--------------|
| `=== CDC FIRED ===` | CDC detected the Account change |
| `Changed Fields: (Type, LastModifiedDate)` | It knows exactly which fields changed |
| `FieldChangedEvaluator: field=Type actual=Customer - Direct` | Condition check passed |
| `OwnerResolver: resolved recipient = 005dL...` | Found who to notify |
| `EMAIL_QUEUE ... toAddresses: [prajwal.pandgale@hypermatica.com]` | Email queued for delivery |
| `EmailChannelHandler: sent to prajwal.pandgale@hypermatica.com` | Email delivered successfully |

**[ OPEN ]** Email inbox

> *"There it is. Professionally formatted, all tokens resolved, correct recipient. From trigger to inbox in under 2 seconds."*

---

## PART 5 — CODE WALKTHROUGH (5 minutes)

---

> **YOU SAY:**
>
> *"Now let me quickly walk through the code architecture — how all of this happens under the hood. I'll keep it high level. The framework has four layers."*

---

### Layer 1 — Entry Point

**[ OPEN ]** `AccountChangeEventTrigger.trigger`

> *"This trigger is the entry point. It fires whenever an AccountChangeEvent arrives. Its only job is to pass the events to the Dispatcher. One line of real work."*

```apex
trigger AccountChangeEventTrigger on AccountChangeEvent (after insert) {
    NotificationDispatcher.dispatch(Trigger.new, 'Account');
}
```

---

### Layer 2 — The Dispatcher

**[ OPEN ]** `NotificationDispatcher.cls`

> *"The Dispatcher parses the raw CDC event. CDC events are unusual — you can't read their header directly in Apex due to a Salesforce limitation. So we use a JSON round-trip trick — serialize to JSON, deserialize back as a Map — and now we can read changeType, changedFields, who made the change, which record IDs.*
>
> *Then it calls RecordQueryService to fetch the complete Account record — because CDC only gives you the fields that changed, not the whole record."*

---

### Layer 3 — The Router

**[ OPEN ]** `NotificationRouter.cls`

> *"The Router is the brain. For each record, it asks RuleCache for all matching rules, runs three filters — watched field, condition evaluator, recipient resolver — and if everything passes, it calls the channel handler.*
>
> *Notice this pattern:*"

```apex
IConditionEvaluator evaluator =
    (IConditionEvaluator) Type.forName(rule.Condition_Class__c).newInstance();
```

> *"This is Apex reflection. The class name 'FieldChangedEvaluator' is just a string stored in the database. At runtime, Apex loads that class dynamically. This is how the framework calls ANY evaluator without knowing about it at compile time."*

---

### Layer 4 — The Handler

**[ OPEN ]** `EmailChannelHandler.cls`

> *"Finally, the Email Handler. It queries the recipient's email address, builds a SingleEmailMessage, uses the Org-Wide Email Address as the From — important for avoiding spam rejection — and sends.*
>
> *After sending, LogService writes a NotificationLog record — your permanent proof of what was sent, to whom, and when."*

---

### Full Architecture Flow

```
USER SAVES ACCOUNT
       │
       ▼
AccountChangeEventTrigger  →  NotificationDispatcher
                                      │
                                      ▼
                              RecordQueryService
                              (re-query full record)
                                      │
                                      ▼
                              NotificationRouter
                              ┌───────────────────┐
                              │ Filter 1: Object  │
                              │ Filter 2: Field   │
                              │ Filter 3: Condition│
                              └────────┬──────────┘
                                       │
                              FieldChangedEvaluator
                              OwnerResolver
                              TemplateEngine
                                       │
                                       ▼
                              EmailChannelHandler
                                       │
                                       ▼
                              LogService → NotificationLog__c
                                       │
                                       ▼
                              📧 EMAIL IN INBOX
```

---

## PART 6 — Q&A (7 minutes)

---

### Q1. What is CDC and why not use a normal trigger?

**Answer:**

> *"CDC stands for Change Data Capture. It's a Salesforce feature that publishes a background event when a record changes.*
>
> *A normal trigger runs during the user's save transaction — if your trigger sends an email and it takes 500 milliseconds, the user waits 500 milliseconds every time they save any Account.*
>
> *CDC runs asynchronously — after the save is complete, in the background. The user sees instant save confirmation. The email goes out a second later without them knowing. Zero performance impact on the UI."*

---

### Q2. What is the "Automated Process" user we saw in the logs?

**Answer:**

> *"When CDC fires, it runs as a special Salesforce system user called 'Automated Process'. This user has no profile, no sharing rules, and no real email address.*
>
> *This is why we use `without sharing` on most framework classes — the Automated Process user would see zero records if we enforced sharing rules. And it's why we need an Org-Wide Email Address — the Automated Process user's email is `noreply@orgId`, which no mail server will accept as a valid From address."*

---

### Q3. What are those `{{{tokens}}}` in the template?

**Answer:**

> *"Those are merge tokens — placeholders that get replaced with real values at the time the email is sent.*
>
> *The TemplateEngine class scans the template for anything wrapped in triple curly braces. It then looks up that token name in a merge context map — a dictionary of field names to their values — and does a simple text replacement.*
>
> - `{{{Account_Name}}}` → `CDC Demo Co`
> - `{{{Owner_Name}}}` → `Prajwal Pandgale`
>
> *The lookup is case-insensitive, so `{{{owner_name}}}` and `{{{Owner_Name}}}` both work. If a token has no matching value, it stays as `{{{token}}}` so you can spot missing data during development."*

---

### Q4. What is `with sharing` and `without sharing`?

**Answer:**

> *"Salesforce has a record-level security model. Sharing rules control which records each user can see based on their role and profile.*
>
> *`with sharing` means the class respects these rules — if you can only see your own records, the class only sees your records too.*
>
> *`without sharing` means the class bypasses sharing rules and can see everything — system context.*
>
> *Most framework classes use `without sharing` because CDC runs as the Automated Process user which has no sharing configuration. If we used `with sharing`, the framework would query zero records and silently fail every time.*
>
> *The one exception is `RecordQueryService` which uses `with sharing` to respect Field-Level Security — ensuring sensitive fields are never accidentally included in notification emails."*

---

### Q5. What is an Interface? Why is it used here?

**Answer:**

> *"An interface is a contract in Apex. It says: any class that implements me MUST have these specific methods.*
>
> *We have three interfaces:*
> - *`IConditionEvaluator` — must have an `evaluate()` method*
> - *`IRecipientResolver` — must have a `resolve()` method*
> - *`IChannelHandler` — must have a `send()` method*
>
> *The Router only knows about these interfaces — it doesn't know `FieldChangedEvaluator` or `OwnerResolver` exist. It just calls `evaluate()` and `resolve()` on whatever class is configured.*
>
> *This means you can write your own evaluator — say, `PriceThresholdEvaluator` — deploy it to the org, put its name in the `Condition_Class__c` field, and the framework calls it automatically. No framework code touched."*

---

### Q6. How does the framework know WHO to send the email to?

**Answer:**

> *"That's handled by the Recipient Resolver — a class that implements `IRecipientResolver`.*
>
> *In our case, `OwnerResolver` is configured. It simply reads the `OwnerId` field from the Account record and returns that User ID as the recipient.*
>
> *The Router then queries that User's email address from the User object and passes it to the email handler.*
>
> *There's also an optional config called `excludeChangeAuthor`. If set to true, it suppresses the notification when the account owner changes their own record — to avoid notifying someone about a change they just made themselves.*
>
> *You could write a completely different resolver — one that notifies everyone in a Territory, or all users who follow the record. Just implement the interface, deploy it, configure the class name. Done."*

---

### Q7. What if two different rules both match the same Account change?

**Answer:**

> *"The framework handles multiple rules correctly. `RuleCache` loads ALL active rules ordered by `Priority__c` — lower number means higher priority.*
>
> *For each changed record, the Router loops through every matching rule and processes them all. So if Rule 1 sends an email and Rule 2 creates a bell notification, both fire for the same change.*
>
> *There is also a `Cooldown_Minutes__c` field on each rule. If configured, the framework won't fire the same rule for the same record within that cooldown window — preventing duplicate notifications if someone clicks save multiple times quickly."*

---

### Q8. Where can I see proof that emails were sent?

**Answer:**

> *"Two places.*
>
> *First — the Debug Logs in Setup. Filter by 'Automated Process' user and look for lines containing `EMAIL_QUEUE` and `EmailChannelHandler: sent to`.*
>
> *Second — and more useful — the `NotificationLog__c` object. Every notification attempt writes a record there with the rule name, recipient, status (Sent or Failed), and exact timestamp.*
>
> *Run this SOQL in Developer Console:*"

```sql
SELECT Rule__r.Rule_Label__c,
       Recipient_User__r.Name,
       Recipient_User__r.Email,
       Record_Id__c,
       Status__c,
       Sent_At__c,
       Error_Message__c
FROM NotificationLog__c
ORDER BY CreatedDate DESC
LIMIT 50
```

> *"This is your permanent audit trail."*

---

### Q9. What if I want to add a notification for a completely different object — like Cases?

**Answer:**

> *"Four steps, no framework code changes:*
>
> *Step 1 — Enable CDC for Case in Setup → Change Data Capture*
>
> *Step 2 — Create a new Apex trigger (literally 2 lines):*"

```apex
trigger CaseChangeEventTrigger on CaseChangeEvent (after insert) {
    NotificationDispatcher.dispatch(Trigger.new, 'Case');
}
```

> *"Step 3 — Create your three records — Template, Rule, Channel — pointing to Case.*
>
> *Step 4 — Done.*
>
> *The Dispatcher, Router, Evaluator, Resolver, and Handler — none of them need changes. They all work on any SObject generically."*

---

### Q10. Why does the email come from `sfcustomeremail.com` and not our domain?

**Answer:**

> *"That's Salesforce's substitute email sending domain. When Salesforce sends emails on your behalf, it routes them through its own mail infrastructure for reliable delivery.*
>
> *The `sfcustomeremail.com` domain has proper SPF records — these are DNS entries that tell the world: emails from this IP address are legitimate. Without this, Gmail and Outlook would reject the emails as spam.*
>
> *The display name 'Notifications' and the Org-Wide Email Address `prajwal.pandgale@hypermatica.com` are the identity the recipient sees. The routing through sfcustomeremail.com is just the plumbing underneath — it's what makes the email actually arrive."*

---

## CLOSING (1 minute)

---

> **YOU SAY:**
>
> *"To summarise what we covered today:*
>
> *The framework has one entry point — a CDC trigger — that wakes up when any Account changes. From there, a Dispatcher parses the event, a Router applies three layers of filtering using pluggable evaluators and resolvers, a TemplateEngine resolves tokens into real values, and a Handler delivers the email. Everything is logged.*
>
> *The key architectural decision — and the one I'm most proud of — is that none of this behaviour is hardcoded. It's all driven by three records in the UI. Adding a new notification is a configuration task, not a development task.*
>
> *Any final questions?"*

---

## QUICK REFERENCE CARD

| Component | File | Role |
|-----------|------|------|
| Entry Point | `AccountChangeEventTrigger.trigger` | Catches CDC event, calls Dispatcher |
| Dispatcher | `NotificationDispatcher.cls` | Parses event, re-queries record |
| Query Service | `RecordQueryService.cls` | Fetches full SObject with all fields |
| Cache | `RuleCache.cls` | Loads rules once per transaction |
| Router | `NotificationRouter.cls` | Orchestrates filters and delivery |
| Evaluator | `FieldChangedEvaluator.cls` | Checks if condition is met |
| Resolver | `OwnerResolver.cls` | Finds who to notify |
| Template Engine | `TemplateEngine.cls` | Resolves `{{{tokens}}}` |
| Email Handler | `EmailChannelHandler.cls` | Sends the email |
| Logger | `LogService.cls` | Writes NotificationLog__c |

---

*Demo script prepared by Prajwal Pandgale — Hypermatica, June 2026*
