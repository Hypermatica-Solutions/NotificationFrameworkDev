@IsTest
private class QueueResolverTest {

    @TestSetup
    static void setup() {
        Group q = new Group(Name = 'Resolver Test Queue', Type = 'Queue');
        insert q;
        insert new GroupMember(GroupId = q.Id, UserOrGroupId = UserInfo.getUserId());
    }

    // ─── helpers ─────────────────────────────────────────────────────────────

    private static RecipientContext buildCtx(Map<String, Object> config) {
        return new RecipientContext(new Account(Name = 'Test'), new NotificationRule__c(), config);
    }

    // ─── happy path ───────────────────────────────────────────────────────────

    @IsTest
    static void testResolvesQueueMembers() {
        Group q = [SELECT Id FROM Group WHERE Name = 'Resolver Test Queue' LIMIT 1];

        RecipientContext ctx = buildCtx(new Map<String, Object>{ 'queueId' => String.valueOf(q.Id) });

        Test.startTest();
        Set<Id> result = new QueueResolver().resolve(ctx);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return the one queue member');
        System.assert(result.contains(UserInfo.getUserId()), 'Current user should be in result');
    }

    // ─── missing config ───────────────────────────────────────────────────────

    @IsTest
    static void testMissingQueueId_returnsEmpty() {
        RecipientContext ctx = buildCtx(new Map<String, Object>());

        Set<Id> result = new QueueResolver().resolve(ctx);

        System.assertEquals(0, result.size(), 'Missing queueId should return empty set');
    }

    @IsTest
    static void testBlankQueueId_returnsEmpty() {
        RecipientContext ctx = buildCtx(new Map<String, Object>{ 'queueId' => '' });

        Set<Id> result = new QueueResolver().resolve(ctx);

        System.assertEquals(0, result.size());
    }

    // ─── empty queue ──────────────────────────────────────────────────────────

    @IsTest
    static void testQueueWithNoMembers_returnsEmpty() {
        Group emptyQueue = new Group(Name = 'Empty Test Queue', Type = 'Queue');
        insert emptyQueue;

        RecipientContext ctx = buildCtx(new Map<String, Object>{ 'queueId' => String.valueOf(emptyQueue.Id) });

        Test.startTest();
        Set<Id> result = new QueueResolver().resolve(ctx);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Empty queue should return empty set');
    }

    // ─── null guard ───────────────────────────────────────────────────────────

    @IsTest
    static void testNullCtx_returnsEmpty() {
        Set<Id> result = new QueueResolver().resolve(null);
        System.assertEquals(0, result.size());
    }
}
