@IsTest
private class BellChannelHandlerTest {

    // ─── helpers ─────────────────────────────────────────────────────────────

    private static NotificationPayload buildPayload(
        Set<Id>             recipientIds,
        Map<String, Object> channelConfig
    ) {
        return new NotificationPayload(
            UserInfo.getUserId(), // ruleId    (dummy)
            UserInfo.getUserId(), // channelId (dummy)
            UserInfo.getUserId(), // recordId  (navigates to this record on click)
            recipientIds,
            'Test Bell Title',
            'Test Bell Body',
            false,
            channelConfig,
            new Map<String, Object>()
        );
    }

    // ─── no recipients ───────────────────────────────────────────────────────

    @IsTest
    static void testSend_noRecipients_returnsEmptyResult() {
        NotificationPayload payload = buildPayload(
            new Set<Id>(),
            new Map<String, Object>{ 'notificationType' => 'TestType' }
        );

        Test.startTest();
        DeliveryResult result = new BellChannelHandler().send(payload);
        Test.stopTest();

        System.assertEquals(0, result.resultsByRecipient.size(),
            'No recipients should return empty result map');
    }

    // ─── missing notificationType key ────────────────────────────────────────

    @IsTest
    static void testSend_missingNotificationTypeKey_allFailed() {
        Id userId = UserInfo.getUserId();
        NotificationPayload payload = buildPayload(
            new Set<Id>{ userId },
            new Map<String, Object>()  // notificationType key intentionally absent
        );

        Test.startTest();
        DeliveryResult result = new BellChannelHandler().send(payload);
        Test.stopTest();

        DeliveryResult.RecipientResult rr = result.resultsByRecipient.get(userId);
        System.assertNotEquals(null, rr, 'Result entry should exist for recipient');
        System.assertEquals(false, rr.success, 'Missing notificationType should mark recipient as failed');
        System.assert(
            rr.errorMessage.contains('notificationType not configured'),
            'Error message should mention missing config key'
        );
    }

    // ─── notificationType not in org ─────────────────────────────────────────

    @IsTest
    static void testSend_notificationTypeNotInOrg_allFailed() {
        Id userId = UserInfo.getUserId();
        NotificationPayload payload = buildPayload(
            new Set<Id>{ userId },
            new Map<String, Object>{ 'notificationType' => 'NONEXISTENT_TYPE_XYZ_999' }
        );

        Test.startTest();
        DeliveryResult result = new BellChannelHandler().send(payload);
        Test.stopTest();

        DeliveryResult.RecipientResult rr = result.resultsByRecipient.get(userId);
        System.assertNotEquals(null, rr, 'Result entry should exist for recipient');
        System.assertEquals(false, rr.success, 'Unknown notificationType should mark recipient as failed');
        System.assert(
            rr.errorMessage.contains('not found'),
            'Error message should confirm the type was not found in the org'
        );
    }

    // ─── result has entry per recipient regardless of outcome ────────────────

    @IsTest
    static void testSend_alwaysProducesEntryPerRecipient() {
        // If a valid CustomNotificationType exists in the org, use it — otherwise the
        // type lookup will return null and markAllFailed() covers the result. Either
        // way the result map must have exactly one entry for the recipient.
        List<CustomNotificationType> types = [
            SELECT Id, DeveloperName FROM CustomNotificationType LIMIT 1
        ];
        String typeName = types.isEmpty() ? 'NONEXISTENT_TYPE' : types[0].DeveloperName;

        Id userId = UserInfo.getUserId();
        NotificationPayload payload = buildPayload(
            new Set<Id>{ userId },
            new Map<String, Object>{ 'notificationType' => typeName }
        );

        Test.startTest();
        DeliveryResult result = new BellChannelHandler().send(payload);
        Test.stopTest();

        System.assertEquals(1, result.resultsByRecipient.size(),
            'One result entry must be created per recipient — success or failure');
        System.assertNotEquals(null, result.resultsByRecipient.get(userId));
    }

    // ─── empty body/subject falls back gracefully ────────────────────────────

    @IsTest
    static void testSend_emptySubjectAndBody_usesTitleAsFallback() {
        // subject and body both blank — handler defaults body to title
        Id userId = UserInfo.getUserId();
        NotificationPayload payload = new NotificationPayload(
            UserInfo.getUserId(),
            UserInfo.getUserId(),
            UserInfo.getUserId(),
            new Set<Id>{ userId },
            '',    // blank subject
            '',    // blank body
            false,
            new Map<String, Object>{ 'notificationType' => 'NONEXISTENT_TYPE_XYZ_999' },
            new Map<String, Object>()
        );

        Test.startTest();
        DeliveryResult result = new BellChannelHandler().send(payload);
        Test.stopTest();

        // We reach markAllFailed (type not found), but the key assertion is: no exception thrown
        System.assertEquals(1, result.resultsByRecipient.size(),
            'Blank subject/body should not throw — handler uses fallback strings');
    }
}
