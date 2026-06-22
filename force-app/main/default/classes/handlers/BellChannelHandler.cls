/**
 * IChannelHandler implementation that sends Salesforce in-app bell notifications
 * via Messaging.CustomNotification.
 *
 * Bell notifications appear in the 🔔 bell icon in the Salesforce header and
 * as push notifications on the Salesforce Mobile app.
 *
 * Title  → channel.Template__r.Subject__c  (rendered {{{tokens}}})
 * Body   → channel.Template__r.Bell_Body__c (rendered {{{tokens}}}, max 255 chars)
 *
 * Channel_Config__c JSON keys:
 *   notificationType (required) – Developer Name of the Custom Notification Type
 *                                  created in Setup → Custom Notifications
 *   targetPageRef    (optional) – page reference type to navigate on click,
 *                                  defaults to standard record page of the record
 *
 * Setup required in org before using this handler:
 *   Setup → Custom Notifications → New
 *   Developer Name must match the value in Channel_Config__c notificationType key
 */
global without sharing class BellChannelHandler implements IChannelHandler {

    // Cache notification type Id per transaction to avoid repeated SOQL
    private static Map<String, String> notifTypeCache = new Map<String, String>();

    global DeliveryResult send(NotificationPayload payload) {
        DeliveryResult result = new DeliveryResult();

        if (payload.recipientIds == null || payload.recipientIds.isEmpty()) {
            System.debug('BellChannelHandler: no recipients — skipping');
            return result;
        }

        // Step 1 — resolve Custom Notification Type Id from Channel_Config__c
        String notifTypeName = payload.channelConfig.containsKey('notificationType')
            ? (String) payload.channelConfig.get('notificationType')
            : null;

        if (String.isBlank(notifTypeName)) {
            System.debug('BellChannelHandler: notificationType missing in Channel_Config__c');
            markAllFailed(payload.recipientIds, 'notificationType not configured in Channel_Config__c', result);
            return result;
        }

        String notifTypeId = getNotificationTypeId(notifTypeName);
        if (String.isBlank(notifTypeId)) {
            System.debug('BellChannelHandler: Custom Notification Type not found: ' + notifTypeName);
            markAllFailed(payload.recipientIds, 'Custom Notification Type not found: ' + notifTypeName, result);
            return result;
        }

        // Step 2 — build and send the notification
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(notifTypeId);

            // Title — from rendered Subject__c (max 255 chars)
            String title = String.isNotBlank(payload.subject)
                ? payload.subject.abbreviate(255)
                : 'Notification';
            notification.setTitle(title);

            // Body — from rendered Bell_Body__c (max 255 chars)
            String body = String.isNotBlank(payload.body)
                ? payload.body.abbreviate(255)
                : title;
            notification.setBody(body);

            // Target — clicking the bell navigates to the related record
            notification.setTargetId(payload.recordId);

            // send() requires Set<String> — convert from Set<Id>
            Set<String> recipientStrings = new Set<String>();
            for (Id rid : payload.recipientIds) {
                recipientStrings.add(String.valueOf(rid));
            }
            notification.send(recipientStrings);

            System.debug('BellChannelHandler: sent to ' + payload.recipientIds.size() + ' recipients');

            // Mark all recipients as sent
            for (Id recipientId : payload.recipientIds) {
                DeliveryResult.RecipientResult rr = new DeliveryResult.RecipientResult();
                rr.success = true;
                rr.sentAt  = DateTime.now();
                result.resultsByRecipient.put(recipientId, rr);
            }

        } catch (Exception e) {
            System.debug('BellChannelHandler: send failed — ' + e.getMessage());
            markAllFailed(payload.recipientIds, e.getMessage(), result);
        }

        return result;
    }

    // ─── helpers ─────────────────────────────────────────────────────────────

    private static String getNotificationTypeId(String developerName) {
        if (notifTypeCache.containsKey(developerName)) {
            return notifTypeCache.get(developerName);
        }

        List<CustomNotificationType> types = [
            SELECT Id
            FROM   CustomNotificationType
            WHERE  DeveloperName = :developerName
            LIMIT  1
        ];

        String typeId = types.isEmpty() ? null : types[0].Id;
        notifTypeCache.put(developerName, typeId);
        return typeId;
    }

    private static void markAllFailed(Set<Id> recipientIds, String errorMessage, DeliveryResult result) {
        for (Id recipientId : recipientIds) {
            DeliveryResult.RecipientResult rr = new DeliveryResult.RecipientResult();
            rr.success      = false;
            rr.errorMessage = errorMessage;
            result.resultsByRecipient.put(recipientId, rr);
        }
    }
}
