@IsTest
private class SpecificUsersResolverTest {

    // ─── helpers ─────────────────────────────────────────────────────────────

    private static RecipientContext buildCtx(Map<String, Object> config) {
        return new RecipientContext(new Account(Name = 'Test'), new NotificationRule__c(), config);
    }

    // ─── happy path ───────────────────────────────────────────────────────────

    @IsTest
    static void testResolvesConfiguredUsers() {
        Id userId = UserInfo.getUserId();
        RecipientContext ctx = buildCtx(new Map<String, Object>{
            'userIds' => new List<Object>{ String.valueOf(userId) }
        });

        Test.startTest();
        Set<Id> result = new SpecificUsersResolver().resolve(ctx);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should resolve the configured user');
        System.assert(result.contains(userId));
    }

    @IsTest
    static void testMultipleUsers_returnsAll() {
        // Create a second active user to include in the list
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u2 = new User(
            FirstName = 'Specific', LastName = 'User Two',
            Email = 'specificuser2@notificationframework.test',
            Username = 'specificuser2@notificationframework.test.dev',
            Alias = 'su2',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u2;

        RecipientContext ctx = buildCtx(new Map<String, Object>{
            'userIds' => new List<Object>{ String.valueOf(UserInfo.getUserId()), String.valueOf(u2.Id) }
        });

        Test.startTest();
        Set<Id> result = new SpecificUsersResolver().resolve(ctx);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Both configured users should be returned');
    }

    @IsTest
    static void testDuplicateIds_deduped() {
        Id userId = UserInfo.getUserId();
        RecipientContext ctx = buildCtx(new Map<String, Object>{
            'userIds' => new List<Object>{ String.valueOf(userId), String.valueOf(userId) }
        });

        Test.startTest();
        Set<Id> result = new SpecificUsersResolver().resolve(ctx);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Duplicate IDs should be de-duped');
    }

    // ─── missing / invalid config ─────────────────────────────────────────────

    @IsTest
    static void testMissingUserIds_returnsEmpty() {
        RecipientContext ctx = buildCtx(new Map<String, Object>());
        System.assertEquals(0, new SpecificUsersResolver().resolve(ctx).size());
    }

    @IsTest
    static void testEmptyUserIdsList_returnsEmpty() {
        RecipientContext ctx = buildCtx(new Map<String, Object>{
            'userIds' => new List<Object>()
        });
        System.assertEquals(0, new SpecificUsersResolver().resolve(ctx).size());
    }

    @IsTest
    static void testInvalidIdFormat_skippedGracefully() {
        RecipientContext ctx = buildCtx(new Map<String, Object>{
            'userIds' => new List<Object>{ 'NOT_A_VALID_ID' }
        });

        Test.startTest();
        Set<Id> result = new SpecificUsersResolver().resolve(ctx);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Invalid ID should be skipped, returning empty set');
    }

    // ─── null guard ───────────────────────────────────────────────────────────

    @IsTest
    static void testNullCtx_returnsEmpty() {
        System.assertEquals(0, new SpecificUsersResolver().resolve(null).size());
    }
}
