global with sharing class RecipientContext {
    global SObject record;
    global NotificationRule__c rule;
    global Map<String, Object> config;

    global RecipientContext(
        SObject record,
        NotificationRule__c rule,
        Map<String, Object> config
    ) {
        this.record = record;
        this.rule = rule;
        this.config = config != null ? config : new Map<String, Object>();
    }
}
