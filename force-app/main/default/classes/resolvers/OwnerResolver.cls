/**
 * IRecipientResolver implementation that returns the record's OwnerId as the
 * sole notification recipient.
 *
 * Recipient_Config__c JSON keys:
 *   ownerField         (optional) – field holding the owner Id, default "OwnerId"
 *   excludeChangeAuthor (optional) – if true, suppress notification when the
 *                                    owner is also the person who made the change
 *
 * Config on NR-0000:
 *   {"excludeChangeAuthor": true}
 */
global with sharing class OwnerResolver implements IRecipientResolver {

    global Set<Id> resolve(RecipientContext ctx) {
        String ownerField = ctx.config.containsKey('ownerField')
                            ? (String) ctx.config.get('ownerField')
                            : 'OwnerId';

        Object ownerRaw = ctx.record.get(ownerField);
        if (ownerRaw == null) {
            System.debug('OwnerResolver: field "' + ownerField + '" is null on record ' + ctx.record.Id);
            return new Set<Id>();
        }

        Id ownerId = (Id) ownerRaw;

        // excludeChangeAuthor: skip notification if owner was the one who changed the record
        Boolean excludeAuthor = ctx.config.containsKey('excludeChangeAuthor')
                                && ctx.config.get('excludeChangeAuthor') == true;

        if (excludeAuthor && ctx.config.containsKey('commitUserId')) {
            Id commitUserId = (Id)(String) ctx.config.get('commitUserId');
            if (ownerId == commitUserId) {
                System.debug('OwnerResolver: owner is the change author — suppressed');
                return new Set<Id>();
            }
        }

        System.debug('OwnerResolver: resolved recipient = ' + ownerId);
        return new Set<Id>{ ownerId };
    }
}
