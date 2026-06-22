# Notification Framework — Team Demo Script
**Presenter:** Prajwal Pandgale
**Audience:** Internal team / stakeholders
**Duration:** ~15–20 minutes
**Status:** Work In Progress demo — showing architecture and configuration, not live triggering

---

## Before You Start — Quick Checklist

- [ ] Salesforce org open in browser, logged in
- [ ] Custom Objects tab visible in Setup
- [ ] Three sample config records created: one NotificationTemplate__c, one NotificationRule__c, one NotificationChannel__c
- [ ] A simple architecture diagram ready (whiteboard or slide — optional but helpful)
- [ ] Mute notifications on your machine

---

## Section 1 — Greeting and Framing

**[FACE THE ROOM / CAMERA]**

> "Hey everyone, thanks for joining. I'll keep this focused and leave time for questions at the end.
>
> So — what I'm going to walk you through today is something I've been building over the last few weeks: a **Notification Framework** for Salesforce.
>
> Just to set expectations upfront — this is a **work in progress**. What I'm showing you today is the core design: the data model, the configuration layer, and how the pieces fit together architecturally. Some parts are fully built, and some parts are **still in implementation** — I'll be clear about which is which as we go.
>
> The goal of today isn't to show a fully live system firing emails. The goal is to show you the **foundation** — and more importantly, to show you *why* I built it this way."

---

## Section 2 — The Problem We're Solving

**[STAY AT CAMERA / WHITEBOARD — no screen share yet]**

> "Let me start with the problem.
>
> Right now, whenever we need a new notification — say, 'send an email when an Account's status changes' — what happens? Someone has to write Apex. They have to write a trigger, maybe a handler class, maybe a template, wire up the email logic, write tests. That's probably a few hours of dev work minimum, just to send one email.
>
> And then the next notification request comes in, and we do it all again. From scratch. Every time.
>
> What I'm building is a system where **adding a new notification requires zero new code**. You just go into the Salesforce UI, create three configuration records, and the framework handles everything else automatically.
>
> That's the core idea. Let me show you how."

---

## Section 3 — The Data Model

**[SHARE SCREEN — navigate to Setup > Object Manager]**

> "Alright, let me pull up Setup."

**[OPEN Setup, go to Object Manager, filter or scroll to show custom objects]**

> "So I've created three custom objects that form the backbone of this framework. Let me walk through each one."

---

### 3.1 — NotificationTemplate__c

**[CLICK into NotificationTemplate__c, show Fields]**

> "First one is **NotificationTemplate__c**. Think of this as the email blueprint — it holds the subject line and the body of the email.
>
> The interesting part here is how the body works."

**[POINT TO the Body__c or TemplateBody__c field]**

> "The body field supports **tokens** — placeholders wrapped in triple curly braces, like `{{{AccountName}}}` or `{{{OwnerEmail}}}`. At runtime, the framework replaces those tokens with actual record data. So the template itself is completely dynamic — you write it once, and it works for any account.
>
> The person setting this up doesn't need to know Apex or Visualforce. They just write the email like they normally would, drop in the tokens where they want dynamic values, and they're done."

**[SHOW a sample template record if one is created]**

> "Here's a sample template I created. You can see the subject line, and the body has a couple of tokens in it. This is exactly what the end user would set up."

---

### 3.2 — NotificationRule__c

**[NAVIGATE to NotificationRule__c, show Fields]**

> "Second object is **NotificationRule__c**. This is where you define *when* a notification should fire.
>
> It has a few key fields."

**[POINT TO each field as you mention it]**

> "**Object Name** — which Salesforce object are we watching? In our current implementation, that's Account.
>
> **Event Type** — what kind of change triggers this? For now, we're focused on field changes detected through CDC — Change Data Capture. I'll explain what CDC is in a second.
>
> **Condition Class** — this is the name of an Apex class that decides *whether* the notification should actually fire. For example, 'did the Account's status change to Closed?' The class implements a known interface, so the framework can call it without knowing anything specific about the business logic inside.
>
> **Recipient Resolver Class** — this is another Apex class name, and it answers the question: *who gets the email?* Is it the Account owner? The sales team? Someone else? Again, it's just a class name stored as text — the framework looks it up and calls it at runtime.
>
> This design is important — the Rule record doesn't hardcode logic. It just **points to** the logic by class name. That means if you ever need different condition logic, you swap the class name. No code changes to the framework itself."

**[SHOW a sample rule record if one is created]**

---

### 3.3 — NotificationChannel__c

**[NAVIGATE to NotificationChannel__c, show Fields]**

> "Third object is **NotificationChannel__c**. This is the glue record — it connects a Rule to a Template and says *how* to deliver the notification.
>
> It has a **Channel Type** — right now that's Email or Bell notification. It has a **lookup to the Rule** and a **lookup to the Template**. And it has an Active flag so you can turn channels on or off without deleting anything.
>
> So when you're setting up a new notification, you create all three records and link them through the Channel. That's it — that's your configuration."

**[SHOW a sample channel record if one is created, pointing out the lookups]**

> "You can see here — the Channel is pointing to our Rule, pointing to our Template, Channel Type is Email, and it's Active. This is everything the framework needs to know to send that notification."

---

## Section 4 — The Architecture: How It All Fits Together

**[SWITCH TO whiteboard / architecture diagram slide, OR stay on screen and draw conceptually]**

> "Now let me explain what happens behind the scenes when a change actually occurs. Walk with me through the flow.
>
> Step one — someone updates a field on an Account record. Let's say the Account status changes.
>
> **Change Data Capture** — or CDC — detects that change. CDC is a Salesforce platform feature that essentially publishes an event every time a record is created, updated, or deleted. It's like a change log that we can subscribe to. We have a **CDC trigger** that's listening for Account change events."

**[POINT TO or write: "CDC Trigger"]**

> "That trigger hands off to the **NotificationDispatcher**. The Dispatcher is the entry point into our framework. Its job is to receive the event and orchestrate what happens next."

**[ADD: "NotificationDispatcher"]**

> "The Dispatcher calls the **RecordQueryService** to go fetch the full Account record — because the CDC event only tells us *what changed*, not the full record details. We need the full record to populate our template tokens later."

**[ADD: "RecordQueryService"]**

> "Then we hit the **NotificationRouter**. This is where the framework looks up all active Channel records related to Account change events. It's essentially asking: 'Are there any configured notifications that care about this event?' If the answer is yes, it proceeds for each matching Channel."

**[ADD: "NotificationRouter"]**

> "For each Channel, we invoke the **FieldChangedEvaluator** — or whichever Condition Class is specified in the Rule. This class runs the business logic check. 'Did the status change to what we care about?' If the condition doesn't pass, we stop here for that channel. No notification sent."

**[ADD: "FieldChangedEvaluator (Condition Class)"]**

> "If the condition passes, we call the **OwnerResolver** — or whichever Recipient Resolver Class is specified. It returns the list of people who should receive the notification."

**[ADD: "OwnerResolver (Recipient Resolver Class)"]**

> "Then the **TemplateEngine** takes over. It fetches the template from our NotificationTemplate__c record, finds all the tokens like `{{{AccountName}}}`, replaces them with actual values from the record, and produces the final email content."

**[ADD: "TemplateEngine"]**

> "That rendered content goes to the **EmailChannelHandler**, which is responsible for actually sending the email using Salesforce's messaging APIs."

**[ADD: "EmailChannelHandler"]**

> "And finally, every step along the way, the **LogService** records what happened — success, failure, what was sent, to whom, when. So we have full auditability."

**[ADD: "LogService"]**

**[PAUSE — let diagram sink in]**

> "The key thing I want you to take away from this diagram is that each of these components has one job. They don't know about each other directly — they communicate through well-defined interfaces. That's what makes the framework extensible. If you want to add Slack notifications tomorrow, you write a SlackChannelHandler and add a new Channel Type. Nothing else changes."

---

## Section 5 — The Zero-Code Promise

**[COME BACK TO SCREEN — or stay at diagram]**

> "Let me make this concrete with an example.
>
> Imagine tomorrow the business comes to you and says: 'We need an email notification whenever an Account's annual revenue crosses a million dollars.'
>
> With the old approach, you'd write a trigger, a handler, an email template, wire it up, write tests — probably a half-day of work.
>
> With this framework? You go into Salesforce, create a NotificationTemplate__c record with the email subject and body you want, create a NotificationRule__c pointing to the condition class that checks revenue, create a NotificationChannel__c linking them — and you're done.
>
> If the condition class for that revenue check already exists, that's maybe **five minutes of configuration work**. If you need a new condition class, you write that one class — no framework changes, no new triggers, no new wiring.
>
> That's the value proposition."

---

## Section 6 — What Is Currently In Implementation

**[FACE THE ROOM / CAMERA — be direct and confident]**

> "Now — and I want to be transparent about this — here's where we are in terms of what's actually running end-to-end.
>
> The data model you just saw? Fully built and deployed. The three custom objects, all the fields, the relationships — that's live in the org.
>
> The configuration UI — creating Template, Rule, and Channel records — that works exactly as I showed you.
>
> The core architecture I walked you through — the Dispatcher, the Router, the Template Engine — the class structure and interfaces for all of these are built and in progress.
>
> **What is currently in implementation** is the end-to-end live execution path — meaning: a field actually changes on an Account, CDC fires, and an email physically lands in someone's inbox. That full chain is what I'm actively working on right now. The individual pieces are there; I'm connecting and testing them together.
>
> I didn't want to wait until everything was 100% wired to show you this, because the architecture and the configuration model are the important parts to align on now. If there's feedback on the design, it's much easier to incorporate it before the execution layer is fully baked.
>
> So — this is a 'here's where we're headed and here's the foundation' demo, not a 'watch the email arrive in real time' demo. I'll have that part ready for the next checkpoint."

---

## Section 7 — Why This Approach

**[OPTIONAL — include if time allows or if stakeholders seem engaged]**

> "Quick note on some of the design decisions, in case anyone's wondering.
>
> **Why CDC instead of a regular trigger?** CDC is more reliable for this use case because it fires asynchronously — it doesn't block the original save transaction. If something goes wrong in our notification logic, it doesn't roll back the Account update. The business record stays safe.
>
> **Why store class names as text in the Rule record?** This is the Strategy pattern — it keeps the framework generic. The framework doesn't need to know about the specifics of any business condition. It just knows how to call any class that implements the right interface. New conditions = new classes, not framework changes.
>
> **Why three separate objects instead of one?** Separation of concerns. The template is reusable — the same email design could be used by multiple rules. The rule defines the trigger logic independently of the delivery method. The channel is where they come together. It also makes it easy to, say, deactivate a specific channel without touching the template or rule."

---

## Section 8 — Closing

**[FACE THE ROOM / CAMERA]**

> "So to wrap up — what I've built is a **metadata-driven notification framework** that takes the repetitive work out of setting up Salesforce notifications.
>
> The core principle is: your business rules live in configuration records, not in code. That means faster delivery, less developer time per notification, and a system that the right people can maintain without needing to open a code editor.
>
> The data model is solid, the architecture is designed to be clean and extensible, and I'm in the process of completing the execution layer.
>
> I'm planning to have the full end-to-end path — including live email triggering — ready to show in the next demo.
>
> Thanks for the time. Happy to dig into any of this."

---

## Section 9 — Q&A Prompts

*These are questions that might come up — think through your answers ahead of time.*

**"Why not just use Salesforce Flow for this?"**
> Flow is great for simple notifications, but it doesn't scale well for complex conditional logic or dynamic recipient resolution. And once you need custom conditions, you end up writing Apex anyway — just in a harder-to-test context. This framework gives you full testability and flexibility while keeping the configuration in the UI.

**"What objects does this support beyond Account?"**
> Right now the CDC subscription is on Account because that's the primary use case we're building for. But the framework is object-agnostic by design — the Rule record has an Object Name field for exactly this reason. Extending to Opportunity or Contact is a configuration change, not a code change — just needs a new CDC event subscription.

**"What if the condition class throws an error?"**
> The LogService captures failures. The framework is designed so that a failure in one channel's processing doesn't break processing for other channels or affect the originating record transaction. Exception handling and retry logic is part of what's in implementation right now.

**"Can we send to people outside Salesforce users?"**
> The Recipient Resolver class controls this. If your resolver returns an external email address, the Email Channel Handler will send to it. The framework doesn't restrict to Salesforce users — it just needs an email address.

**"How do we test a new notification without going to production?"**
> Because everything is driven by configuration records, you test in a sandbox. Create your records, trigger a test update, verify the log. No code to deploy for the notification itself — just the config records, and those can be exported and deployed as metadata.

---

*End of script.*
