/**
 * IChannelHandler implementation that sends email via Messaging.SingleEmailMessage.
 *
 * Uses setHtmlBody / setPlainTextBody (SEM Mode 2) — never setTemplateId.
 * This is required for CDC / Platform Event async contexts where template-based
 * emails are not allowed.
 *
 * One email is sent per resolved recipient. Results are mapped back individually
 * so LogService can record success / failure per user.
 *
 * OrgWideEmailAddress is cached in a static variable so it is queried only once
 * per transaction regardless of how many channels fire.
 *
 * Channel_Config__c JSON keys:
 *   senderDisplayName  (optional) – "From" display name, default "Notifications"
 *   replyTo            (optional) – reply-to email address
 *   fromEmail          (optional) – pins a specific verified OrgWideEmailAddress
 */
global without sharing class EmailChannelHandler implements IChannelHandler {

    // Cached per transaction — OrgWideEmailAddress is the same for all channels
    private static Map<String, Id> owEaCache = new Map<String, Id>();

    global DeliveryResult send(NotificationPayload payload) {
        DeliveryResult result = new DeliveryResult();

        if (payload.recipientIds == null || payload.recipientIds.isEmpty()) {
            System.debug('EmailChannelHandler: no recipients — skipping');
            return result;
        }

        // Step 1 — fetch email addresses for all recipient user Ids (one bulk query)
        List<Id> orderedRecipients = new List<Id>();
        Map<Id, String> emailByUserId = new Map<Id, String>();

        for (User u : [
            SELECT Id, Email
            FROM   User
            WHERE  Id IN :payload.recipientIds
            AND    IsActive = true
        ]) {
            if (String.isNotBlank(u.Email)) {
                orderedRecipients.add(u.Id);
                emailByUserId.put(u.Id, u.Email);
            }
        }

        if (orderedRecipients.isEmpty()) {
            System.debug('EmailChannelHandler: no active users with email found');
            return result;
        }

        // Step 2 — read optional channel config overrides
        String senderDisplayName = payload.channelConfig.containsKey('senderDisplayName')
            ? (String) payload.channelConfig.get('senderDisplayName')
            : 'Notifications';

        String replyTo = payload.channelConfig.containsKey('replyTo')
            ? (String) payload.channelConfig.get('replyTo')
            : null;

        String fromEmailAddress = payload.channelConfig.containsKey('fromEmail')
            ? (String) payload.channelConfig.get('fromEmail')
            : null;

        // Step 3 — resolve OrgWideEmailAddress from static cache (query at most once per key per transaction)
        Id orgWideEmailId = getOrgWideEmailId(fromEmailAddress);

        // Step 4 — build one SingleEmailMessage per recipient
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id recipientId : orderedRecipients) {
            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ emailByUserId.get(recipientId) });
            msg.setSubject(payload.subject);
            msg.setSaveAsActivity(false);
            msg.setUseSignature(false);

            if (orgWideEmailId != null) {
                msg.setOrgWideEmailAddressId(orgWideEmailId);
            } else {
                msg.setSenderDisplayName(senderDisplayName);
            }

            if (String.isNotBlank(replyTo)) {
                msg.setReplyTo(replyTo);
            }

            if (payload.bodyIsHtml) {
                msg.setHtmlBody(payload.body);
            } else {
                msg.setPlainTextBody(payload.body);
            }

            emails.add(msg);
        }

        // Step 5 — send in one call; false = don't throw on partial failure
        List<Messaging.SendEmailResult> sendResults = Messaging.sendEmail(emails, false);

        // Step 6 — map each result back to its recipient Id (same list order)
        for (Integer i = 0; i < orderedRecipients.size(); i++) {
            Id recipientId = orderedRecipients[i];
            Messaging.SendEmailResult sendResult = sendResults[i];

            DeliveryResult.RecipientResult rr = new DeliveryResult.RecipientResult();
            rr.success = sendResult.isSuccess();

            if (rr.success) {
                rr.sentAt = DateTime.now();
                System.debug('EmailChannelHandler: sent to ' + emailByUserId.get(recipientId));
            } else {
                List<String> errors = new List<String>();
                for (Messaging.SendEmailError err : sendResult.getErrors()) {
                    errors.add(err.getMessage());
                }
                rr.errorMessage = String.join(errors, '; ');
                System.debug('EmailChannelHandler: failed for ' + recipientId + ' — ' + rr.errorMessage);
            }

            result.resultsByRecipient.put(recipientId, rr);
        }

        return result;
    }

    // ─── OrgWideEmailAddress cache ────────────────────────────────────────────
    // Key: fromEmail address string (or empty string for default lookup)
    // Queried at most once per unique key per transaction
    private static Id getOrgWideEmailId(String fromEmailAddress) {
        String cacheKey = fromEmailAddress != null ? fromEmailAddress : '';

        if (!owEaCache.containsKey(cacheKey)) {
            List<OrgWideEmailAddress> oweas = String.isNotBlank(fromEmailAddress)
                ? [SELECT Id FROM OrgWideEmailAddress WHERE Address = :fromEmailAddress AND IsVerified = true LIMIT 1]
                : [SELECT Id FROM OrgWideEmailAddress WHERE IsVerified = true LIMIT 1];

            owEaCache.put(cacheKey, oweas.isEmpty() ? null : oweas[0].Id);
        }

        return owEaCache.get(cacheKey);
    }
}
