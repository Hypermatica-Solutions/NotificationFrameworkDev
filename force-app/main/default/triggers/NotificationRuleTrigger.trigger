trigger NotificationRuleTrigger on NotificationRule__c (before insert, before update) {
    if (Trigger.isInsert) {
        NotificationRuleTriggerHandler.onBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
        NotificationRuleTriggerHandler.onBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
