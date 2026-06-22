// Runs as system context — CDC fires under "Automated Process" user which has no sharing rules.
// without sharing ensures all called classes that inherit context can access records correctly.
public without sharing class NotificationRouter {

    /**
     * Entry point called by NotificationDispatcher for every batch of CDC events.
     *
     * @param records               recordId → full SObject (re-queried by Dispatcher)
     * @param changedFieldsByRecord recordId → set of field API names that changed
     * @param changeTypeByRecord    recordId → CDC changeType (CREATE / UPDATE / DELETE)
     * @param commitUserByRecord    recordId → Id of the user who made the change
     */
    public static void route(
        Map<Id, SObject>     records,
        Map<Id, Set<String>> changedFieldsByRecord,
        Map<Id, String>      changeTypeByRecord,
        Map<Id, Id>          commitUserByRecord
    ) {
        if (records == null || records.isEmpty()) return;

        String objectApiName = records.values()[0].getSObjectType().getDescribe().getName();

        // ── Pre-query 1: Load all relevant rule bundles upfront ───────────────
        // Collect all unique trigger events in this CDC batch
        Set<String> triggerEvents = new Set<String>(changeTypeByRecord.values());
        List<RuleCache.RuleBundle> allBundles = new List<RuleCache.RuleBundle>();
        for (String evt : triggerEvents) {
            allBundles.addAll(RuleCache.getRules(objectApiName, evt));
        }

        // ── Pre-query 2: Email Templates ──────────────────────────────────────
        // Collect all Email Template developer names from every channel in every bundle
        Set<String> templateNames = new Set<String>();
        for (RuleCache.RuleBundle bundle : allBundles) {
            for (NotificationChannel__c ch : bundle.channels) {
                if (String.isNotBlank(ch.Template__r.Email_Template_Name__c)) {
                    templateNames.add(ch.Template__r.Email_Template_Name__c);
                }
            }
        }
        // One SOQL for all templates — no query inside loops
        Map<String, EmailTemplate> emailTemplatesByName = new Map<String, EmailTemplate>();
        if (!templateNames.isEmpty()) {
            for (EmailTemplate t : [
                SELECT DeveloperName, Subject, HtmlValue, Body
                FROM   EmailTemplate
                WHERE  DeveloperName IN :templateNames
            ]) {
                emailTemplatesByName.put(t.DeveloperName, t);
            }
        }

        // ── Pre-query 3: User names (Owner + commit user for merge tokens) ────
        // Collect all owner IDs and commit user IDs across all records
        Set<Id> allUserIds = new Set<Id>();
        for (Id recordId : records.keySet()) {
            Object ownerId = records.get(recordId).get('OwnerId');
            if (ownerId != null) allUserIds.add((Id) ownerId);
            Id commitUserId = commitUserByRecord.get(recordId);
            if (commitUserId != null) allUserIds.add(commitUserId);
        }
        // One SOQL for all users — no query inside loops
        Map<Id, String> userNamesById = new Map<Id, String>();
        if (!allUserIds.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :allUserIds]) {
                userNamesById.put(u.Id, u.Name);
            }
        }

        // ── Pre-query 4: Active cooldown keys ────────────────────────────────
        // Build every possible (rule|record|channel) key for this batch upfront.
        // One SOQL here means isOnCooldown() in the per-channel loop is zero-SOQL.
        Decimal maxCooldownMinutes = 0;
        Set<String> cooldownKeysToCheck = new Set<String>();
        for (RuleCache.RuleBundle bundle : allBundles) {
            if (bundle.rule.Cooldown_Minutes__c != null && bundle.rule.Cooldown_Minutes__c > maxCooldownMinutes) {
                maxCooldownMinutes = bundle.rule.Cooldown_Minutes__c;
            }
            for (Id recId : records.keySet()) {
                for (NotificationChannel__c ch : bundle.channels) {
                    cooldownKeysToCheck.add(CooldownManager.buildKey(bundle.rule.Id, recId, ch.Id));
                }
            }
        }
        Map<String, DateTime> lastSentByKey = CooldownManager.getLastSentTimes(cooldownKeysToCheck, maxCooldownMinutes);

        // ── Main processing loop — zero SOQL from here down ──────────────────
        for (Id recordId : records.keySet()) {
            SObject     record        = records.get(recordId);
            Set<String> changedFields = changedFieldsByRecord.get(recordId);
            String      triggerEvent  = changeTypeByRecord.get(recordId);
            Id          commitUserId  = commitUserByRecord.get(recordId);

            List<RuleCache.RuleBundle> bundles = RuleCache.getRules(objectApiName, triggerEvent);

            for (RuleCache.RuleBundle bundle : bundles) {
                processRule(bundle, record, changedFields, recordId, commitUserId,
                            emailTemplatesByName, userNamesById, lastSentByKey);
            }
        }
    }

    // ─── per-rule orchestration ──────────────────────────────────────────────

    private static void processRule(
        RuleCache.RuleBundle       bundle,
        SObject                    record,
        Set<String>                changedFields,
        Id                         recordId,
        Id                         commitUserId,
        Map<String, EmailTemplate> emailTemplatesByName,
        Map<Id, String>            userNamesById,
        Map<String, DateTime>      lastSentByKey
    ) {
        NotificationRule__c rule = bundle.rule;

        // Filter 2 — at least one watched field must have changed
        if (!watchedFieldChanged(rule.Watched_Fields__c, changedFields)) {
            System.debug('Router: skip rule "' + rule.Rule_Label__c + '" — no watched field changed');
            return;
        }

        // Filter 3 — optional custom condition evaluator
        if (!evaluateCondition(rule, record, changedFields)) {
            System.debug('Router: skip rule "' + rule.Rule_Label__c + '" — condition evaluated false');
            return;
        }

        // Resolve recipients
        Set<Id> recipientIds = resolveRecipients(rule, record, commitUserId);
        if (recipientIds == null || recipientIds.isEmpty()) {
            System.debug('Router: skip rule "' + rule.Rule_Label__c + '" — no recipients resolved');
            return;
        }

        // Deliver through every active channel attached to this rule
        for (NotificationChannel__c channel : bundle.channels) {
            deliverChannel(rule, channel, record, recordId, recipientIds, commitUserId,
                           emailTemplatesByName, userNamesById, lastSentByKey);
        }
    }

    // ─── per-channel delivery ────────────────────────────────────────────────

    private static void deliverChannel(
        NotificationRule__c        rule,
        NotificationChannel__c     channel,
        SObject                    record,
        Id                         recordId,
        Set<Id>                    recipientIds,
        Id                         commitUserId,
        Map<String, EmailTemplate> emailTemplatesByName,
        Map<Id, String>            userNamesById,
        Map<String, DateTime>      lastSentByKey
    ) {
        // Cooldown check
        if (CooldownManager.isOnCooldown(lastSentByKey, rule.Id, recordId, channel.Id, rule.Cooldown_Minutes__c)) {
            System.debug('Router: on cooldown — rule=' + rule.Rule_Label__c + ' record=' + recordId);
            return;
        }

        // Build merge context using pre-queried user names — no SOQL
        Map<String, Object> mergeContext  = buildMergeContext(record, commitUserId, userNamesById);
        Map<String, Object> channelConfig = parseJson(channel.Channel_Config__c);

        // Resolve raw subject and body based on channel type
        String rawSubject  = channel.Template__r.Subject__c;
        String rawBody     = '';
        Boolean bodyIsHtml = false;

        if (channel.Channel_Type__c == 'Bell') {
            // Bell — always plain text, body from Bell_Body__c
            rawBody    = channel.Template__r.Bell_Body__c;
            bodyIsHtml = false;

        } else {
            // Email — fetch HTML body from Lightning Email Template, fall back to Body__c
            bodyIsHtml = channel.Template__r.Body_Is_HTML__c;
            rawBody    = channel.Template__r.Body__c;

            String sfTemplateName = channel.Template__r.Email_Template_Name__c;
            if (String.isNotBlank(sfTemplateName)) {
                EmailTemplate sfTpl = emailTemplatesByName.get(sfTemplateName);
                if (sfTpl != null) {
                    if (String.isNotBlank(sfTpl.Subject)) rawSubject = sfTpl.Subject;
                    rawBody    = String.isNotBlank(sfTpl.HtmlValue) ? sfTpl.HtmlValue : sfTpl.Body;
                    bodyIsHtml = String.isNotBlank(sfTpl.HtmlValue);
                } else {
                    System.debug('Router: EmailTemplate not found for DeveloperName=' + sfTemplateName);
                }
            }
        }

        // Render {{{token}}} placeholders with actual record values
        String renderedSubject = TemplateEngine.render(rawSubject, mergeContext);
        String renderedBody    = TemplateEngine.render(rawBody,    mergeContext);

        NotificationPayload payload = new NotificationPayload(
            rule.Id,
            channel.Id,
            recordId,
            recipientIds,
            renderedSubject,
            renderedBody,
            bodyIsHtml,
            channelConfig,
            mergeContext
        );

        IChannelHandler handler = getChannelHandler(channel.Channel_Type__c);
        if (handler == null) return;

        DeliveryResult result = handler.send(payload);

        LogService.log(rule, channel, recordId, recipientIds, result);
    }

    // ─── Filter 2: watched fields ────────────────────────────────────────────

    private static Boolean watchedFieldChanged(String watchedCsv, Set<String> changedFields) {
        if (String.isBlank(watchedCsv)) return true;
        if (changedFields == null || changedFields.isEmpty()) return false;

        Set<String> lowerChanged = new Set<String>();
        for (String f : changedFields) lowerChanged.add(f.toLowerCase());

        for (String watched : watchedCsv.split(',')) {
            if (lowerChanged.contains(watched.trim().toLowerCase())) return true;
        }
        return false;
    }

    // ─── Filter 3: condition evaluator (dynamic) ─────────────────────────────

    private static Boolean evaluateCondition(
        NotificationRule__c rule,
        SObject             record,
        Set<String>         changedFields
    ) {
        if (String.isBlank(rule.Condition_Class__c)) return true;

        Map<String, Object> config = parseJson(rule.Condition_Config__c);
        EvaluationContext ctx = new EvaluationContext(record, null, changedFields, rule, config);

        try {
            IConditionEvaluator evaluator =
                (IConditionEvaluator) Type.forName(rule.Condition_Class__c).newInstance();
            return evaluator.evaluate(ctx);
        } catch (Exception e) {
            System.debug('Router: condition evaluator error [' + rule.Condition_Class__c + ']: ' + e.getMessage());
            return false;
        }
    }

    // ─── Recipient resolver (dynamic) ────────────────────────────────────────

    private static Set<Id> resolveRecipients(NotificationRule__c rule, SObject record, Id commitUserId) {
        // Built-in strategies map directly to their resolver class.
        // ApexResolver delegates to the admin-specified Recipient_Resolver_Class__c.
        Map<String, String> strategyMap = new Map<String, String>{
            'Owner'          => 'OwnerResolver',
            'Queue'          => 'QueueResolver',
            'SpecificUsers'  => 'SpecificUsersResolver',
            'FieldReference' => 'FieldReferenceResolver'
        };

        String resolverClass = strategyMap.containsKey(rule.Recipient_Strategy__c)
            ? strategyMap.get(rule.Recipient_Strategy__c)
            : rule.Recipient_Resolver_Class__c;

        if (String.isBlank(resolverClass)) return new Set<Id>();

        Map<String, Object> config = parseJson(rule.Recipient_Config__c);
        if (commitUserId != null) config.put('commitUserId', (Object) String.valueOf(commitUserId));
        RecipientContext ctx = new RecipientContext(record, rule, config);

        try {
            IRecipientResolver resolver =
                (IRecipientResolver) Type.forName(resolverClass).newInstance();
            return resolver.resolve(ctx);
        } catch (Exception e) {
            System.debug('Router: recipient resolver error [' + resolverClass + ']: ' + e.getMessage());
            return new Set<Id>();
        }
    }

    // ─── Channel handler lookup ───────────────────────────────────────────────

    private static IChannelHandler getChannelHandler(String channelType) {
        Map<String, String> handlerMap = new Map<String, String>{
            'Email' => 'EmailChannelHandler',
            'Bell'  => 'BellChannelHandler'
        };

        String className = handlerMap.get(channelType);
        if (String.isBlank(className)) {
            System.debug('Router: no handler registered for channel type: ' + channelType);
            return null;
        }

        try {
            return (IChannelHandler) Type.forName(className).newInstance();
        } catch (Exception e) {
            System.debug('Router: could not load handler [' + className + ']: ' + e.getMessage());
            return null;
        }
    }

    // ─── Merge context builder — uses pre-queried user names, zero SOQL ──────

    private static Map<String, Object> buildMergeContext(
        SObject         record,
        Id              commitUserId,
        Map<Id, String> userNamesById
    ) {
        Map<String, Object> ctx = new Map<String, Object>(record.getPopulatedFieldsAsMap());

        String objApiName = record.getSObjectType().getDescribe().getName();
        if (ctx.containsKey('Name')) {
            ctx.put(objApiName + '_Name', ctx.get('Name'));
        }

        // Resolve Owner name from pre-queried map
        if (ctx.containsKey('OwnerId') && ctx.get('OwnerId') != null) {
            String ownerName = userNamesById.get((Id) ctx.get('OwnerId'));
            if (ownerName != null) ctx.put('Owner_Name', ownerName);
        }

        // Resolve commit user name from pre-queried map
        if (commitUserId != null) {
            String changedByName = userNamesById.get(commitUserId);
            if (changedByName != null) ctx.put('Changed_By', changedByName);
        }

        return ctx;
    }

    private static Map<String, Object> parseJson(String rawJson) {
        if (String.isBlank(rawJson)) return new Map<String, Object>();
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(rawJson);
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }
}
