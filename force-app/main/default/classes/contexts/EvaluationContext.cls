global with sharing class EvaluationContext {
    global SObject newRecord;
    global SObject oldRecord;
    global Set<String> changedFields;
    global NotificationRule__c rule;
    global Map<String, Object> config;

    global EvaluationContext(
        SObject newRecord,
        SObject oldRecord,
        Set<String> changedFields,
        NotificationRule__c rule,
        Map<String, Object> config
    ) {
        this.newRecord = newRecord;
        this.oldRecord = oldRecord;
        this.changedFields = changedFields != null ? changedFields : new Set<String>();
        this.rule = rule;
        this.config = config != null ? config : new Map<String, Object>();
    }
}
