/**
 * IRecipientResolver implementation that resolves all active members of a
 * Salesforce Queue as notification recipients.
 *
 * Recipient_Config__c JSON keys:
 *   queueId (required) – Salesforce ID of the Queue (Group of Type = Queue).
 *                        Use Setup → Queues to find the ID, or query:
 *                        SELECT Id FROM Group WHERE Type = 'Queue' AND Name = 'Your Queue Name'
 *
 * Behaviour:
 *   - Queries GroupMember records for direct user members of the queue.
 *   - Nested group memberships (group-within-a-group) are not expanded — v2.
 *   - Only active users are returned; inactive members are silently excluded.
 *
 * Example config:
 *   {"queueId": "00G000000000001AAA"}
 */
global with sharing class QueueResolver implements IRecipientResolver {

    global Set<Id> resolve(RecipientContext ctx) {
        if (ctx == null) return new Set<Id>();

        String queueId = ctx.config.containsKey('queueId')
            ? (String) ctx.config.get('queueId')
            : null;

        if (String.isBlank(queueId)) {
            System.debug('QueueResolver: "queueId" missing from Recipient_Config__c');
            return new Set<Id>();
        }

        // Collect direct user members — skip nested group IDs (prefix '00G')
        Set<Id> memberIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT UserOrGroupId
            FROM   GroupMember
            WHERE  GroupId = :queueId
        ]) {
            // User IDs start with '005'; Group/nested-queue IDs start with '00G'
            if (String.valueOf(gm.UserOrGroupId).startsWith('005')) {
                memberIds.add(gm.UserOrGroupId);
            }
        }

        if (memberIds.isEmpty()) return new Set<Id>();

        // Filter to active users only
        Set<Id> result = new Set<Id>();
        for (User u : [SELECT Id FROM User WHERE Id IN :memberIds AND IsActive = true]) {
            result.add(u.Id);
        }

        System.debug('QueueResolver: resolved ' + result.size() + ' recipient(s) from queue ' + queueId);
        return result;
    }
}
