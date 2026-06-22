@IsTest
private class EmailChannelHandlerTest {

    // ─── helpers ─────────────────────────────────────────────────────────────

    private static NotificationPayload buildPayload(
        Set<Id>             recipientIds,
        String              body,
        Boolean             bodyIsHtml,
        Map<String, Object> channelConfig
    ) {
        return new NotificationPayload(
            UserInfo.getUserId(), // ruleId    (dummy)
            UserInfo.getUserId(), // channelId (dummy)
            UserInfo.getUserId(), // recordId  (dummy)
            recipientIds,
            'Account Updated — Test Subject',
            body,
            bodyIsHtml,
            channelConfig,
            new Map<String, Object>()
        );
    }

    // ─── no recipients ───────────────────────────────────────────────────────

    @IsTest
    static void testSend_noRecipients_returnsEmptyResult() {
        NotificationPayload payload = buildPayload(
            new Set<Id>(), 'Test body', false, new Map<String, Object>()
        );

        Test.startTest();
        DeliveryResult result = new EmailChannelHandler().send(payload);
        Test.stopTest();

        System.assertEquals(0, result.resultsByRecipient.size(),
            'No recipients should produce empty result map');
    }

    // ─── active user recipient ────────────────────────────────────────────────

    @IsTest
    static void testSend_activeUserRecipient_resultHasEntry() {
        Id userId = UserInfo.getUserId();
        NotificationPayload payload = buildPayload(
            new Set<Id>{ userId }, 'Plain text body', false, new Map<String, Object>()
        );

        Test.startTest();
        DeliveryResult result = new EmailChannelHandler().send(payload);
        Test.stopTest();

        System.assertNotEquals(null, result.resultsByRecipient.get(userId),
            'Result map should have an entry for the recipient');
    }

    // ─── HTML vs plain text body ──────────────────────────────────────────────

    @IsTest
    static void testSend_htmlBody_resultHasEntry() {
        Id userId = UserInfo.getUserId();
        NotificationPayload payload = buildPayload(
            new Set<Id>{ userId },
            '<p>Hello <strong>World</strong></p>',
            true, // bodyIsHtml = true → setHtmlBody() path
            new Map<String, Object>()
        );

        Test.startTest();
        DeliveryResult result = new EmailChannelHandler().send(payload);
        Test.stopTest();

        System.assertNotEquals(null, result.resultsByRecipient.get(userId),
            'HTML body path should still produce a result entry');
    }

    @IsTest
    static void testSend_plainTextBody_resultHasEntry() {
        Id userId = UserInfo.getUserId();
        NotificationPayload payload = buildPayload(
            new Set<Id>{ userId },
            'Plain text notification',
            false, // bodyIsHtml = false → setPlainTextBody() path
            new Map<String, Object>()
        );

        Test.startTest();
        DeliveryResult result = new EmailChannelHandler().send(payload);
        Test.stopTest();

        System.assertNotEquals(null, result.resultsByRecipient.get(userId),
            'Plain text body path should produce a result entry');
    }

    // ─── channelConfig overrides ──────────────────────────────────────────────

    @IsTest
    static void testSend_senderDisplayNameFromConfig_resultHasEntry() {
        Id userId = UserInfo.getUserId();
        NotificationPayload payload = buildPayload(
            new Set<Id>{ userId },
            'Notification body',
            false,
            new Map<String, Object>{ 'senderDisplayName' => 'My Custom Sender' }
        );

        Test.startTest();
        DeliveryResult result = new EmailChannelHandler().send(payload);
        Test.stopTest();

        System.assertNotEquals(null, result.resultsByRecipient.get(userId),
            'Custom senderDisplayName in channelConfig should not prevent delivery');
    }

    @IsTest
    static void testSend_replyToFromConfig_resultHasEntry() {
        Id userId = UserInfo.getUserId();
        NotificationPayload payload = buildPayload(
            new Set<Id>{ userId },
            'Notification with reply-to',
            false,
            new Map<String, Object>{ 'replyTo' => 'noreply@example.com' }
        );

        Test.startTest();
        DeliveryResult result = new EmailChannelHandler().send(payload);
        Test.stopTest();

        System.assertNotEquals(null, result.resultsByRecipient.get(userId));
    }

    // ─── multiple recipients ──────────────────────────────────────────────────

    @IsTest
    static void testSend_multipleRecipients_entryPerRecipient() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> users = new List<User>();
        for (Integer i = 0; i < 2; i++) {
            users.add(new User(
                FirstName         = 'Email',
                LastName          = 'Recipient' + i,
                Email             = 'emailrecipient' + i + '@notificationframework.test',
                Username          = 'emailrecipient' + i + '@notificationframework.test.dev',
                Alias             = 'er' + i,
                TimeZoneSidKey    = 'America/Los_Angeles',
                LocaleSidKey      = 'en_US',
                EmailEncodingKey  = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId         = p.Id
            ));
        }
        insert users;

        Set<Id> recipientIds = new Set<Id>{ users[0].Id, users[1].Id };
        NotificationPayload payload = buildPayload(
            recipientIds, 'Bulk notification', false, new Map<String, Object>()
        );

        Test.startTest();
        DeliveryResult result = new EmailChannelHandler().send(payload);
        Test.stopTest();

        System.assertEquals(2, result.resultsByRecipient.size(),
            'Result map should have one entry per recipient');
    }
}
