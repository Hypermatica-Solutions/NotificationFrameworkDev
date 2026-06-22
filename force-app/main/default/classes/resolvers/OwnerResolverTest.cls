@IsTest
private class OwnerResolverTest {

    @TestSetup
    static void setup() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        insert new User(
            FirstName         = 'Owner',
            LastName          = 'Resolver User',
            Email             = 'ownerresolver@notificationframework.test',
            Username          = 'ownerresolver@notificationframework.test.dev',
            Alias             = 'owres',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = p.Id
        );
    }

    // ─── basic resolution ─────────────────────────────────────────────────────

    @IsTest
    static void testResolvesDefaultOwnerId() {
        User owner = [SELECT Id FROM User WHERE Username = 'ownerresolver@notificationframework.test.dev' LIMIT 1];
        Account record = new Account(Name = 'Test Co', OwnerId = owner.Id);

        RecipientContext ctx = new RecipientContext(record, new NotificationRule__c(), new Map<String, Object>());
        Set<Id> result = new OwnerResolver().resolve(ctx);

        System.assertEquals(1, result.size(), 'Should resolve one recipient from OwnerId');
        System.assert(result.contains(owner.Id), 'Resolved recipient should be the account owner');
    }

    @IsTest
    static void testCustomOwnerField_fromConfig() {
        User owner = [SELECT Id FROM User WHERE Username = 'ownerresolver@notificationframework.test.dev' LIMIT 1];

        // Explicitly configure ownerField to 'OwnerId' (same as default — validates config path)
        Account record = new Account(Name = 'Test Co', OwnerId = owner.Id);
        Map<String, Object> config = new Map<String, Object>{ 'ownerField' => 'OwnerId' };

        RecipientContext ctx = new RecipientContext(record, new NotificationRule__c(), config);
        Set<Id> result = new OwnerResolver().resolve(ctx);

        System.assertEquals(1, result.size());
        System.assert(result.contains(owner.Id));
    }

    // ─── excludeChangeAuthor ──────────────────────────────────────────────────

    @IsTest
    static void testExcludeChangeAuthor_ownerIsAuthor_returnsEmpty() {
        User owner = [SELECT Id FROM User WHERE Username = 'ownerresolver@notificationframework.test.dev' LIMIT 1];
        Account record = new Account(Name = 'Test Co', OwnerId = owner.Id);

        Map<String, Object> config = new Map<String, Object>{
            'excludeChangeAuthor' => true,
            'commitUserId'        => String.valueOf(owner.Id)
        };

        RecipientContext ctx = new RecipientContext(record, new NotificationRule__c(), config);
        Set<Id> result = new OwnerResolver().resolve(ctx);

        System.assertEquals(0, result.size(), 'Owner who made the change should be suppressed');
    }

    @IsTest
    static void testExcludeChangeAuthor_differentUser_returnsOwner() {
        User owner = [SELECT Id FROM User WHERE Username = 'ownerresolver@notificationframework.test.dev' LIMIT 1];
        Account record = new Account(Name = 'Test Co', OwnerId = owner.Id);

        Map<String, Object> config = new Map<String, Object>{
            'excludeChangeAuthor' => true,
            'commitUserId'        => String.valueOf(UserInfo.getUserId()) // different user made the change
        };

        RecipientContext ctx = new RecipientContext(record, new NotificationRule__c(), config);
        Set<Id> result = new OwnerResolver().resolve(ctx);

        System.assertEquals(1, result.size(), 'Owner should be notified when a different user made the change');
        System.assert(result.contains(owner.Id));
    }

    @IsTest
    static void testExcludeChangeAuthor_flagFalse_ownerAlwaysNotified() {
        User owner = [SELECT Id FROM User WHERE Username = 'ownerresolver@notificationframework.test.dev' LIMIT 1];
        Account record = new Account(Name = 'Test Co', OwnerId = owner.Id);

        // excludeChangeAuthor = false — even when owner == commitUser, still notify
        Map<String, Object> config = new Map<String, Object>{
            'excludeChangeAuthor' => false,
            'commitUserId'        => String.valueOf(owner.Id)
        };

        RecipientContext ctx = new RecipientContext(record, new NotificationRule__c(), config);
        Set<Id> result = new OwnerResolver().resolve(ctx);

        System.assertEquals(1, result.size(), 'excludeChangeAuthor=false should never suppress the owner');
    }

    // ─── null owner ───────────────────────────────────────────────────────────

    @IsTest
    static void testNullOwnerId_returnsEmpty() {
        // Account SObject with OwnerId not set — get() returns null
        Account record = new Account(Name = 'No Owner');

        RecipientContext ctx = new RecipientContext(record, new NotificationRule__c(), new Map<String, Object>());
        Set<Id> result = new OwnerResolver().resolve(ctx);

        System.assertEquals(0, result.size(), 'Null OwnerId on record should return empty set');
    }
}
