# Notification Framework — Development Rules

These are mandatory practices to follow every time a change is made to this project.
Failure to follow these causes issues in deployment, permissions, and org configuration.

---

## Rule 1 — Every new custom field MUST get field-level security in permission sets

**When:** Any time a new `__c` field is added to any custom object in this project.

**What to do:**
- Open `force-app/main/default/permissionsets/Notification_Admin.permissionset-meta.xml`
- Add a `<fieldPermissions>` block for the new field with `editable: true` and `readable: true`
- If the field is also relevant to end users, add it to `Notification_User.permissionset-meta.xml` as well
- Deploy the permission set in the same deployment as the field

**Why:** Without FLS, the field is invisible and non-editable in the UI even if it's on the layout and FlexiPage. This has caused repeated issues where layout changes appear correct but fields show blank in the org.

**Example block to add:**
```xml
<fieldPermissions>
    <editable>true</editable>
    <field>NotificationTemplate__c.YourNewField__c</field>
    <readable>true</readable>
</fieldPermissions>
```

---

## Rule 2 — Every new custom field MUST be added to the layout AND FlexiPage

**When:** Any time a new field is added that needs to be visible or editable on a record page.

**What to do:**
- Open the layout file: `force-app/main/default/layouts/<ObjectName>-<LayoutName>.layout-meta.xml`
- Add the field to the appropriate section
- Check the FlexiPage: `force-app/main/default/flexipages/<Name>_Record_Page.flexipage-meta.xml`
- Deploy field + layout + FlexiPage + permission set all together in one deployment

**Why:** Fields added to the object but not the layout are invisible in the UI. Fields on the layout but without FLS are visible but blank and non-editable.

---

## Rule 3 — Never deploy field + layout separately from permission set

**When:** Always.

**What to do:** Group field, layout, and permission set into a single `sf project deploy start` command.

**Why:** Salesforce rolls back a deployment entirely if any component fails (`rollbackOnError: true`). Deploying in separate transactions means a failure in one leaves the org in a broken half-state.

---

## Rule 4 — No SOQL queries inside loops — Query first, store in Map/List, then loop

**When:** Any time a for loop processes records or collections.

**What to do:**
- Collect all IDs/keys needed before the loop starts
- Run one SOQL query outside the loop using `IN :idSet`
- Store results in a `Map<Id, SObject>` or `List<SObject>`
- Inside the loop, read from the Map/List — zero SOQL

**Correct pattern:**
```apex
// Step 1 — collect all IDs before any loop
Set<Id> userIds = new Set<Id>();
for (Id recordId : records.keySet()) {
    userIds.add((Id) records.get(recordId).get('OwnerId'));
}

// Step 2 — one SOQL outside the loop
Map<Id, String> userNamesById = new Map<Id, String>();
for (User u : [SELECT Id, Name FROM User WHERE Id IN :userIds]) {
    userNamesById.put(u.Id, u.Name);
}

// Step 3 — loop reads from map, zero SOQL inside
for (Id recordId : records.keySet()) {
    String ownerName = userNamesById.get(ownerId); // map lookup only
}
```

**Wrong pattern — never do this:**
```apex
for (Id recordId : records.keySet()) {
    User u = [SELECT Name FROM User WHERE Id = :ownerId]; // SOQL inside loop — WRONG
}
```

**Why:** Salesforce governor limit is 100 SOQL queries per transaction. SOQL inside a loop multiplies by the number of records — 50 records = 50 queries. This hits the limit fast during bulk CDC events and causes the entire transaction to fail.

---

## Rule 5 — Every new email template deployment requires field + permission + layout together

**When:** Any time a new `Email_Template_Name__c` value is configured or a new template reference is added.

**What to do:**
- Add field to permission set first
- Deploy permission set
- Then set the field value on the record via UI

**Why:** Without permission set access, the field shows on layout but the user cannot edit it — leading to confusion about whether the deployment worked.

---

## Rule 6 — Always verify deployment before testing end-to-end

**When:** After every deployment.

**What to do:**
1. Confirm deploy status = `Succeeded` in terminal output
2. Open the record in the org and verify the field/layout change is visible
3. Only then trigger a CDC event to test

**Why:** Testing on a partially deployed or rolled-back org leads to false failures and wastes debugging time.

---

## Rule 7 — Always use Lightning Email Templates only (never Classic)

**When:** When creating any new email template for this framework.

**What to do:**
- Go to App Launcher → Email Templates → New Email Template
- This creates a Lightning Email Template (SFX type)
- Put the Developer Name in `Email_Template_Name__c` on the `NotificationTemplate__c` record
- Do NOT use Setup → Classic Email Templates
- Do NOT deploy email templates as metadata (causes folder/type deployment errors)

**Why:** This is a managed package. The package ships code only. Email templates are org-specific content — clients configure their own branding in their org.

---

## Rule 8 — When pasting HTML into Lightning Email Template, never include the outer html/body tags

**When:** Any time you paste custom HTML into the Lightning Email Template Source editor.

**What to do:**
- Click **Source** button in the HTML Value editor
- Delete all existing content in the Source view
- Paste ONLY from the first `<table>` tag to the last `</table>` tag
- Do NOT include `<html>`, `<head>`, `<body>` wrapper tags
- Click Source again to switch back to WYSIWYG and verify it renders correctly
- Save

**Why:** The Lightning Email Template rich text editor already provides its own HTML wrapper. If you paste `<html><body>` tags inside the Source editor, the editor stores them as literal escaped text (`&lt;html&gt;`) instead of actual HTML markup. This causes the email to deliver raw HTML code as visible text instead of a rendered design.

**Correct paste content starts at:**
```html
<table width="100%" cellpadding="0" ...>
    ...
</table>
```

**Wrong — do NOT paste:**
```html
<html>
<body>
<table ...>
```

---

## Rule 9 — Class names in rule config fields must exactly match a deployed Apex class

**When:** Any time you set `Condition_Class__c` or `Recipient_Resolver_Class__c` on a Notification Rule record.

**What to do:**
- Before saving the rule record, verify the Apex class actually exists in the org
- The class name must be spelled exactly as the Apex class is named — case-sensitive
- After saving, trigger a test CDC event and check the debug log for `Type.forName` errors

**Why:** `Type.forName('ClassName')` returns `null` silently if the class does not exist — it does not throw an error. The crash only happens one line later when `.newInstance()` is called on the null, showing as "Attempt to de-reference a null object". This makes it hard to trace back to a wrong class name. Examples of this failure: setting `Recipient_Resolver_Class__c = "AccountOwnerResolver"` when the deployed class is named `OwnerResolver`.

**How to verify a class exists before saving:**
- Check the class list in Setup → Apex Classes
- Or grep the project: search for `class ClassName` in the resolvers/evaluators folders
