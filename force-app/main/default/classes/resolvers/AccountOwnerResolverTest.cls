@IsTest
private class AccountOwnerResolverTest {

    @TestSetup
    static void setup() {
        // Test user used across all test methods
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User testUser = new User(
            FirstName        = 'Test',
            LastName         = 'Owner',
            Email            = 'testowner@notificationframework.test',
            Username         = 'testowner@notificationframework.test.dev',
            Alias            = 'towner',
            TimeZoneSidKey   = 'America/Los_Angeles',
            LocaleSidKey     = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId        = p.Id
        );
        insert testUser;
    }

    // ─── basic resolution ─────────────────────────────────────────────────────

    @IsTest
    static void testResolvesAccountOwner() {
        User owner = [SELECT Id FROM User WHERE Username = 'testowner@notificationframework.test.dev' LIMIT 1];

        Account record = new Account(Name = 'Test Co', OwnerId = owner.Id);
        NotificationRule__c rule = new NotificationRule__c();
        RecipientContext ctx = new RecipientContext(
            record, rule,
            new Map<String, Object>()
        );

        Set<Id> result = new AccountOwnerResolver().resolve(ctx);

        System.assertEquals(1, result.size());
        System.assert(result.contains(owner.Id));
    }

    // ─── excludeChangeAuthor ──────────────────────────────────────────────────

    @IsTest
    static void testExcludeChangeAuthor_ownerIsAuthor_returnsEmpty() {
        User owner = [SELECT Id FROM User WHERE Username = 'testowner@notificationframework.test.dev' LIMIT 1];

        Account record = new Account(Name = 'Test Co', OwnerId = owner.Id);
        NotificationRule__c rule = new NotificationRule__c();

        Map<String, Object> config = new Map<String, Object>{
            'excludeChangeAuthor' => true,
            'commitUserId'        => String.valueOf(owner.Id)
        };

        RecipientContext ctx = new RecipientContext(record, rule, config);
        Set<Id> result = new AccountOwnerResolver().resolve(ctx);

        System.assertEquals(0, result.size(), 'Owner should be suppressed when they are the change author');
    }

    @IsTest
    static void testExcludeChangeAuthor_ownerIsNotAuthor_returnsOwner() {
        User owner   = [SELECT Id FROM User WHERE Username = 'testowner@notificationframework.test.dev' LIMIT 1];
        User current = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        Account record = new Account(Name = 'Test Co', OwnerId = owner.Id);
        NotificationRule__c rule = new NotificationRule__c();

        Map<String, Object> config = new Map<String, Object>{
            'excludeChangeAuthor' => true,
            'commitUserId'        => String.valueOf(current.Id)
        };

        RecipientContext ctx = new RecipientContext(record, rule, config);
        Set<Id> result = new AccountOwnerResolver().resolve(ctx);

        System.assertEquals(1, result.size(), 'Owner should still be notified when change author is different');
        System.assert(result.contains(owner.Id));
    }

    // ─── null guards ─────────────────────────────────────────────────────────

    @IsTest
    static void testNullCtx_returnsEmpty() {
        Set<Id> result = new AccountOwnerResolver().resolve(null);
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void testNullRecord_returnsEmpty() {
        RecipientContext ctx = new RecipientContext(
            null, new NotificationRule__c(),
            new Map<String, Object>()
        );
        Set<Id> result = new AccountOwnerResolver().resolve(ctx);
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void testNullOwnerId_returnsEmpty() {
        // Account with no OwnerId set
        Account record = new Account(Name = 'No Owner');
        NotificationRule__c rule = new NotificationRule__c();
        RecipientContext ctx = new RecipientContext(
            record, rule, new Map<String, Object>()
        );

        Set<Id> result = new AccountOwnerResolver().resolve(ctx);
        System.assertEquals(0, result.size());
    }
}
