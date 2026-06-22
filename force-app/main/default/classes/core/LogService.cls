public without sharing class LogService {

    public static void log(
        NotificationRule__c    rule,
        NotificationChannel__c channel,
        Id                     recordId,
        Set<Id>                recipientIds,
        DeliveryResult         result
    ) {
        List<NotificationLog__c> logs = new List<NotificationLog__c>();

        for (Id recipientId : recipientIds) {
            DeliveryResult.RecipientResult rr = result.resultsByRecipient.get(recipientId);

            NotificationLog__c log = new NotificationLog__c();
            log.Rule__c           = rule.Id;
            log.Channel__c        = channel.Id;
            log.Record_Id__c      = String.valueOf(recordId);
            log.Channel_Type__c   = channel.Channel_Type__c;
            log.Recipient_User__c = recipientId;
            log.Cooldown_Key__c   = CooldownManager.buildKey(rule.Id, recordId, channel.Id);

            if (rr != null && rr.success) {
                log.Status__c  = 'Sent';
                log.Sent_At__c = rr.sentAt;
            } else {
                log.Status__c       = 'Failed';
                log.Error_Message__c = rr != null ? rr.errorMessage : 'No result returned';
            }

            logs.add(log);
        }

        if (!logs.isEmpty()) {
            insert logs;
        }
    }
}
