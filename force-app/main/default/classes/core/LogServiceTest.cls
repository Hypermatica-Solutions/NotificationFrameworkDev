@IsTest
private class LogServiceTest {

    @TestSetup
    static void setup() {
        NotificationRule__c rule = new NotificationRule__c(
            Rule_Label__c               = 'Test Rule',
            Object_API_Name__c          = 'Account',
            Trigger_Event__c            = 'Update',
            Condition_Class__c          = 'FieldChangedEvaluator',
            Recipient_Strategy__c       = 'ApexResolver',
            Recipient_Resolver_Class__c = 'AccountOwnerResolver',
            Active__c                   = true
        );
        insert rule;

        NotificationTemplate__c tmpl = new NotificationTemplate__c(
            Name             = 'Test Template',
            Template_Key__c  = 'TEST_TEMPLATE',
            Channel_Type__c  = 'Email',
            Subject__c       = 'Test Subject'
        );
        insert tmpl;

        NotificationChannel__c channel = new NotificationChannel__c(
            Rule__c          = rule.Id,
            Channel_Type__c  = 'Email',
            Template__c      = tmpl.Id,
            Active__c        = true
        );
        insert channel;
    }

    // ─── Sent scenario ────────────────────────────────────────────────────────

    @IsTest
    static void testLogWritten_sentStatus() {
        NotificationRule__c    rule    = [SELECT Id FROM NotificationRule__c LIMIT 1];
        NotificationChannel__c channel = [SELECT Id, Channel_Type__c FROM NotificationChannel__c LIMIT 1];
        Id recipientId = UserInfo.getUserId();
        Id recordId    = UserInfo.getUserId(); // dummy record Id

        DeliveryResult result = new DeliveryResult();
        DeliveryResult.RecipientResult rr = new DeliveryResult.RecipientResult();
        rr.success = true;
        rr.sentAt  = DateTime.now();
        result.resultsByRecipient.put(recipientId, rr);

        Test.startTest();
        LogService.log(rule, channel, recordId, new Set<Id>{recipientId}, result);
        Test.stopTest();

        List<NotificationLog__c> logs = [
            SELECT Status__c, Recipient_User__c, Channel_Type__c, Sent_At__c
            FROM   NotificationLog__c
            WHERE  Rule__c = :rule.Id
        ];

        System.assertEquals(1, logs.size(), 'One log record should be created');
        System.assertEquals('Sent',        logs[0].Status__c);
        System.assertEquals(recipientId,   logs[0].Recipient_User__c);
        System.assertEquals('Email',       logs[0].Channel_Type__c);
        System.assertNotEquals(null,        logs[0].Sent_At__c);
    }

    // ─── Failed scenario ──────────────────────────────────────────────────────

    @IsTest
    static void testLogWritten_failedStatus() {
        NotificationRule__c    rule    = [SELECT Id FROM NotificationRule__c LIMIT 1];
        NotificationChannel__c channel = [SELECT Id, Channel_Type__c FROM NotificationChannel__c LIMIT 1];
        Id recipientId = UserInfo.getUserId();
        Id recordId    = UserInfo.getUserId();

        DeliveryResult result = new DeliveryResult();
        DeliveryResult.RecipientResult rr = new DeliveryResult.RecipientResult();
        rr.success      = false;
        rr.errorMessage = 'Email address not verified';
        result.resultsByRecipient.put(recipientId, rr);

        Test.startTest();
        LogService.log(rule, channel, recordId, new Set<Id>{recipientId}, result);
        Test.stopTest();

        List<NotificationLog__c> logs = [
            SELECT Status__c, Error_Message__c
            FROM   NotificationLog__c
            WHERE  Rule__c = :rule.Id
        ];

        System.assertEquals(1,                           logs.size());
        System.assertEquals('Failed',                    logs[0].Status__c);
        System.assertEquals('Email address not verified', logs[0].Error_Message__c);
    }

    // ─── No result returned scenario ─────────────────────────────────────────

    @IsTest
    static void testLogWritten_noResultReturned_markedFailed() {
        NotificationRule__c    rule    = [SELECT Id FROM NotificationRule__c LIMIT 1];
        NotificationChannel__c channel = [SELECT Id, Channel_Type__c FROM NotificationChannel__c LIMIT 1];
        Id recipientId = UserInfo.getUserId();
        Id recordId    = UserInfo.getUserId();

        // Empty DeliveryResult — no entry for recipientId
        DeliveryResult result = new DeliveryResult();

        Test.startTest();
        LogService.log(rule, channel, recordId, new Set<Id>{recipientId}, result);
        Test.stopTest();

        List<NotificationLog__c> logs = [
            SELECT Status__c, Error_Message__c
            FROM   NotificationLog__c
            WHERE  Rule__c = :rule.Id
        ];

        System.assertEquals(1,                    logs.size());
        System.assertEquals('Failed',             logs[0].Status__c);
        System.assertEquals('No result returned', logs[0].Error_Message__c);
    }

    // ─── Multiple recipients ──────────────────────────────────────────────────

    @IsTest
    static void testLog_multipleRecipients_createsOneLogEach() {
        NotificationRule__c    rule    = [SELECT Id FROM NotificationRule__c LIMIT 1];
        NotificationChannel__c channel = [SELECT Id, Channel_Type__c FROM NotificationChannel__c LIMIT 1];

        // Create two test users for multiple recipient scenario
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> users = new List<User>();
        for (Integer i = 0; i < 2; i++) {
            users.add(new User(
                FirstName = 'Log', LastName = 'User' + i,
                Email = 'loguser' + i + '@notificationframework.test',
                Username = 'loguser' + i + '@notificationframework.test.dev',
                Alias = 'lu' + i,
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = p.Id
            ));
        }
        insert users;

        Set<Id> recipientIds = new Set<Id>{ users[0].Id, users[1].Id };
        DeliveryResult result = new DeliveryResult();
        for (User u : users) {
            DeliveryResult.RecipientResult rr = new DeliveryResult.RecipientResult();
            rr.success = true;
            rr.sentAt  = DateTime.now();
            result.resultsByRecipient.put(u.Id, rr);
        }

        Test.startTest();
        LogService.log(rule, channel, users[0].Id, recipientIds, result);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM NotificationLog__c WHERE Rule__c = :rule.Id];
        System.assertEquals(2, count, 'One log record per recipient');
    }
}
