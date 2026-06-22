global with sharing class NotificationPayload {
    global Id ruleId;
    global Id channelId;
    global Id recordId;
    global Set<Id> recipientIds;
    global String subject;
    global String body;
    global Boolean bodyIsHtml;
    global Map<String, Object> channelConfig;
    global Map<String, Object> mergeContext;

    global NotificationPayload(
        Id ruleId,
        Id channelId,
        Id recordId,
        Set<Id> recipientIds,
        String subject,
        String body,
        Boolean bodyIsHtml,
        Map<String, Object> channelConfig,
        Map<String, Object> mergeContext
    ) {
        this.ruleId = ruleId;
        this.channelId = channelId;
        this.recordId = recordId;
        this.recipientIds = recipientIds != null ? recipientIds : new Set<Id>();
        this.subject = subject;
        this.body = body;
        this.bodyIsHtml = bodyIsHtml != null ? bodyIsHtml : false;
        this.channelConfig = channelConfig != null ? channelConfig : new Map<String, Object>();
        this.mergeContext = mergeContext != null ? mergeContext : new Map<String, Object>();
    }
}
