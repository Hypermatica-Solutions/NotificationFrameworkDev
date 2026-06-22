/**
 * IRecipientResolver implementation that returns a fixed, admin-configured
 * set of users as notification recipients.
 *
 * Use this when the recipients are always the same people regardless of who
 * owns the record or what changed — e.g. always notify the CFO on large deals,
 * always notify the Legal team on contract approvals.
 *
 * Recipient_Config__c JSON keys:
 *   userIds (required) – JSON array of Salesforce User IDs.
 *
 * Behaviour:
 *   - Invalid or malformed IDs in the array are silently skipped.
 *   - Inactive users in the list are excluded — active-only policy.
 *   - Duplicate IDs are de-duped automatically via Set<Id>.
 *
 * Example config:
 *   {"userIds": ["005A000000000001AAA", "005A000000000002AAA"]}
 */
global with sharing class SpecificUsersResolver implements IRecipientResolver {

    global Set<Id> resolve(RecipientContext ctx) {
        if (ctx == null) return new Set<Id>();

        List<Object> rawIds = ctx.config.containsKey('userIds')
            ? (List<Object>) ctx.config.get('userIds')
            : null;

        if (rawIds == null || rawIds.isEmpty()) {
            System.debug('SpecificUsersResolver: "userIds" missing or empty in Recipient_Config__c');
            return new Set<Id>();
        }

        // Parse and validate each ID — skip any that are malformed
        Set<Id> requestedIds = new Set<Id>();
        for (Object raw : rawIds) {
            try {
                requestedIds.add((Id) String.valueOf(raw));
            } catch (Exception e) {
                System.debug('SpecificUsersResolver: invalid user ID "' + raw + '" — skipped');
            }
        }

        if (requestedIds.isEmpty()) return new Set<Id>();

        // Return only active users from the configured list
        Set<Id> result = new Set<Id>();
        for (User u : [SELECT Id FROM User WHERE Id IN :requestedIds AND IsActive = true]) {
            result.add(u.Id);
        }

        System.debug('SpecificUsersResolver: resolved ' + result.size() + ' of ' + requestedIds.size() + ' configured user(s)');
        return result;
    }
}
