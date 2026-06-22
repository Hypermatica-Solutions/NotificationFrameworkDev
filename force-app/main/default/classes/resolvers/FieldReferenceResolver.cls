/**
 * IRecipientResolver implementation that resolves the recipient from a
 * User lookup field on the triggering record.
 *
 * Use this when the person to notify is stored directly on the record itself —
 * e.g. notify the Account Manager on an Opportunity, notify the Assigned To user
 * on a Case, notify the record creator via CreatedById.
 *
 * Recipient_Config__c JSON keys:
 *   field (required) – API name of the User lookup field on the record,
 *                      e.g. "OwnerId", "CreatedById", "Account_Manager__c"
 *
 * Behaviour:
 *   - Reads the field value from the re-queried record (full record from RecordQueryService).
 *   - Returns empty set if the field is null, the ID is not a User, or the user is inactive.
 *   - Gracefully handles fields that do not exist on the record (SObjectException caught).
 *
 * Example configs:
 *   {"field": "OwnerId"}
 *   {"field": "CreatedById"}
 *   {"field": "Account_Manager__c"}
 */
global with sharing class FieldReferenceResolver implements IRecipientResolver {

    global Set<Id> resolve(RecipientContext ctx) {
        if (ctx == null || ctx.record == null) return new Set<Id>();

        String fieldName = ctx.config.containsKey('field')
            ? (String) ctx.config.get('field')
            : null;

        if (String.isBlank(fieldName)) {
            System.debug('FieldReferenceResolver: "field" missing from Recipient_Config__c');
            return new Set<Id>();
        }

        // Read the field value from the record
        Object rawValue;
        try {
            rawValue = ctx.record.get(fieldName);
        } catch (SObjectException e) {
            System.debug('FieldReferenceResolver: field "' + fieldName + '" not found on record — ' + e.getMessage());
            return new Set<Id>();
        }

        if (rawValue == null) return new Set<Id>();

        // Cast to Id and verify it references a User (prefix '005')
        Id referencedId;
        try {
            referencedId = (Id) rawValue;
        } catch (Exception e) {
            System.debug('FieldReferenceResolver: field "' + fieldName + '" value is not a valid Id');
            return new Set<Id>();
        }

        if (!String.valueOf(referencedId).startsWith('005')) {
            System.debug('FieldReferenceResolver: field "' + fieldName + '" does not point to a User record');
            return new Set<Id>();
        }

        // Verify the user is active
        List<User> users = [SELECT Id FROM User WHERE Id = :referencedId AND IsActive = true LIMIT 1];
        if (users.isEmpty()) return new Set<Id>();

        System.debug('FieldReferenceResolver: resolved recipient ' + referencedId + ' from field ' + fieldName);
        return new Set<Id>{ users[0].Id };
    }
}
