/**
 * IRecipientResolver implementation that returns the record's OwnerId as the
 * sole notification recipient.
 *
 * Recipient_Config__c JSON keys:
 *   ownerField          (optional) – field holding the owner Id, default "OwnerId"
 *   excludeChangeAuthor (optional) – if true, suppress notification when the
 *                                    owner is also the person who made the change
 */
global with sharing class AccountOwnerResolver implements IRecipientResolver {

    global Set<Id> resolve(RecipientContext ctx) {
        if (ctx == null || ctx.record == null) {
            System.debug('AccountOwnerResolver: ctx or ctx.record is null');
            return new Set<Id>();
        }

        String ownerField = ctx.config.containsKey('ownerField')
                            ? (String) ctx.config.get('ownerField')
                            : 'OwnerId';

        Object ownerRaw = ctx.record.get(ownerField);
        if (ownerRaw == null) {
            System.debug('AccountOwnerResolver: field "' + ownerField + '" is null on record');
            return new Set<Id>();
        }

        Id ownerId = (Id) ownerRaw;

        Boolean excludeAuthor = ctx.config.containsKey('excludeChangeAuthor')
                                && ctx.config.get('excludeChangeAuthor') == true;

        if (excludeAuthor && ctx.config.containsKey('commitUserId')) {
            Object rawCommitUser = ctx.config.get('commitUserId');
            if (rawCommitUser != null) {
                Id commitUserId = (Id)(String) rawCommitUser;
                if (ownerId == commitUserId) {
                    System.debug('AccountOwnerResolver: owner is the change author — suppressed');
                    return new Set<Id>();
                }
            }
        }

        System.debug('AccountOwnerResolver: resolved recipient = ' + ownerId);
        return new Set<Id>{ ownerId };
    }
}
