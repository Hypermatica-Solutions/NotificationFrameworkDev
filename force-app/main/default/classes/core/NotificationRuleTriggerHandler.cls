public with sharing class NotificationRuleTriggerHandler {

    // ── Entry points called by the trigger ────────────────────────────────────

    public static void onBeforeInsert(List<NotificationRule__c> newRules) {
        validate(newRules);
    }

    public static void onBeforeUpdate(
        List<NotificationRule__c>    newRules,
        Map<Id, NotificationRule__c> oldMap
    ) {
        // Only re-validate records where a validation-relevant field actually changed.
        // Bulk updates touching unrelated fields (e.g. Active__c) skip validation entirely.
        List<NotificationRule__c> changed = new List<NotificationRule__c>();
        for (NotificationRule__c rule : newRules) {
            NotificationRule__c old = oldMap.get(rule.Id);
            if (rule.Condition_Class__c       != old.Condition_Class__c
             || rule.Recipient_Strategy__c    != old.Recipient_Strategy__c
             || rule.Recipient_Resolver_Class__c != old.Recipient_Resolver_Class__c) {
                changed.add(rule);
            }
        }
        if (!changed.isEmpty()) {
            validate(changed);
        }
    }

    // ── Core validation — zero SOQL, pure class reflection ───────────────────

    private static void validate(List<NotificationRule__c> rules) {
        for (NotificationRule__c rule : rules) {
            validateConditionClass(rule);
            validateRecipientResolver(rule);
        }
    }

    private static void validateConditionClass(NotificationRule__c rule) {
        // Condition_Class__c is a required field, so it is always non-blank here.
        Type conditionType = Type.forName(rule.Condition_Class__c);
        if (conditionType == null) {
            rule.Condition_Class__c.addError(
                '"' + rule.Condition_Class__c + '" class not found. Check the class name spelling.'
            );
            return;
        }

        Object instance;
        try {
            instance = conditionType.newInstance();
        } catch (Exception e) {
            rule.Condition_Class__c.addError(
                '"' + rule.Condition_Class__c + '" could not be instantiated. Ensure it has a public no-arg constructor.'
            );
            return;
        }

        if (!(instance instanceof IConditionEvaluator)) {
            rule.Condition_Class__c.addError(
                '"' + rule.Condition_Class__c + '" must implement IConditionEvaluator.'
            );
        }
    }

    private static void validateRecipientResolver(NotificationRule__c rule) {
        if (rule.Recipient_Strategy__c != 'ApexResolver') return;
        if (String.isBlank(rule.Recipient_Resolver_Class__c)) {
            rule.Recipient_Resolver_Class__c.addError(
                'Recipient Resolver Class is required when Strategy is ApexResolver.'
            );
        }
    }
}
