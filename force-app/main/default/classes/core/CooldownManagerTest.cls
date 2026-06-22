@IsTest
private class CooldownManagerTest {

    // ── Test data ─────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        NotificationRule__c rule = new NotificationRule__c(
            Rule_Label__c         = 'Cooldown Test Rule',
            Object_API_Name__c    = 'Account',
            Trigger_Event__c      = 'Update',
            Condition_Class__c    = 'FieldChangedEvaluator',
            Recipient_Strategy__c = 'Owner',
            Active__c             = true
        );
        insert rule;

        NotificationChannel__c channel = new NotificationChannel__c(
            Rule__c         = rule.Id,
            Channel_Type__c = 'Email',
            Active__c       = true
        );
        insert channel;
    }

    // ── buildKey ──────────────────────────────────────────────────────────────

    @IsTest
    static void testBuildKey_format() {
        Id id1 = UserInfo.getUserId();
        Id id2 = UserInfo.getUserId();
        Id id3 = UserInfo.getUserId();

        String key = CooldownManager.buildKey(id1, id2, id3);
        List<String> parts = key.split('\\|');

        System.assertEquals(3, parts.size(), 'Key must have exactly 3 pipe-delimited parts');
        System.assertEquals(String.valueOf(id1), parts[0], 'First part must be ruleId');
        System.assertEquals(String.valueOf(id3), parts[2], 'Third part must be channelId');
    }

    // ── isOnCooldown — null / zero guards ─────────────────────────────────────

    @IsTest
    static void testIsOnCooldown_nullCooldownMinutes_returnsFalse() {
        Id dummy = UserInfo.getUserId();
        System.assertEquals(false,
            CooldownManager.isOnCooldown(new Map<String, DateTime>(), dummy, dummy, dummy, null),
            'Null cooldown minutes must return false'
        );
    }

    @IsTest
    static void testIsOnCooldown_zeroCooldownMinutes_returnsFalse() {
        Id dummy = UserInfo.getUserId();
        System.assertEquals(false,
            CooldownManager.isOnCooldown(new Map<String, DateTime>(), dummy, dummy, dummy, 0),
            'Zero cooldown minutes must return false'
        );
    }

    @IsTest
    static void testIsOnCooldown_nullIds_returnsFalse() {
        System.assertEquals(false,
            CooldownManager.isOnCooldown(new Map<String, DateTime>(), null, null, null, 10),
            'Null IDs must return false'
        );
    }

    @IsTest
    static void testIsOnCooldown_nullMap_returnsFalse() {
        Id dummy = UserInfo.getUserId();
        System.assertEquals(false,
            CooldownManager.isOnCooldown(null, dummy, dummy, dummy, 10),
            'Null map must return false without throwing'
        );
    }

    // ── isOnCooldown — in-memory suppression logic ────────────────────────────

    @IsTest
    static void testIsOnCooldown_keyNotInMap_returnsFalse() {
        Id dummy = UserInfo.getUserId();
        Map<String, DateTime> lastSentByKey = new Map<String, DateTime>{
            'unrelated|key|here' => DateTime.now()
        };
        System.assertEquals(false,
            CooldownManager.isOnCooldown(lastSentByKey, dummy, dummy, dummy, 10),
            'Absent key must return false'
        );
    }

    @IsTest
    static void testIsOnCooldown_recentLog_returnsTrue() {
        Id dummy = UserInfo.getUserId();
        String key = CooldownManager.buildKey(dummy, dummy, dummy);

        // Log sent 2 minutes ago, cooldown window is 10 minutes → still suppressed
        Map<String, DateTime> lastSentByKey = new Map<String, DateTime>{
            key => DateTime.now().addMinutes(-2)
        };

        System.assertEquals(true,
            CooldownManager.isOnCooldown(lastSentByKey, dummy, dummy, dummy, 10),
            'Log within cooldown window must suppress'
        );
    }

    @IsTest
    static void testIsOnCooldown_expiredLog_returnsFalse() {
        Id dummy = UserInfo.getUserId();
        String key = CooldownManager.buildKey(dummy, dummy, dummy);

        // Log sent 61 minutes ago, cooldown window is 60 minutes → window expired
        Map<String, DateTime> lastSentByKey = new Map<String, DateTime>{
            key => DateTime.now().addMinutes(-61)
        };

        System.assertEquals(false,
            CooldownManager.isOnCooldown(lastSentByKey, dummy, dummy, dummy, 60),
            'Log outside cooldown window must allow through'
        );
    }

    // ── getLastSentTimes — SOQL path ──────────────────────────────────────────

    @IsTest
    static void testGetLastSentTimes_emptyKeys_returnsEmptyMap() {
        Test.startTest();
        Map<String, DateTime> result = CooldownManager.getLastSentTimes(new Set<String>(), 10);
        Test.stopTest();

        System.assert(result.isEmpty(), 'Empty key set must return empty map');
    }

    @IsTest
    static void testGetLastSentTimes_zeroCooldown_returnsEmptyMap() {
        Test.startTest();
        Map<String, DateTime> result = CooldownManager.getLastSentTimes(
            new Set<String>{ 'someKey' }, 0
        );
        Test.stopTest();

        System.assert(result.isEmpty(), 'Zero cooldown must return empty map');
    }

    @IsTest
    static void testGetLastSentTimes_recentLog_returnsKey() {
        NotificationRule__c    rule    = [SELECT Id FROM NotificationRule__c LIMIT 1];
        NotificationChannel__c channel = [SELECT Id FROM NotificationChannel__c LIMIT 1];
        Id recordId = UserInfo.getUserId();

        String key = CooldownManager.buildKey(rule.Id, recordId, channel.Id);

        insert new NotificationLog__c(
            Rule__c         = rule.Id,
            Channel__c      = channel.Id,
            Channel_Type__c = 'Email',
            Status__c       = 'Sent',
            Sent_At__c      = DateTime.now().addMinutes(-2),
            Cooldown_Key__c = key,
            Record_Id__c    = String.valueOf(recordId)
        );

        Test.startTest();
        Map<String, DateTime> result = CooldownManager.getLastSentTimes(
            new Set<String>{ key }, 10
        );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should find 1 log within the window');
        System.assert(result.containsKey(key), 'Returned map must contain the queried key');
    }

    @IsTest
    static void testGetLastSentTimes_expiredLog_returnsEmptyMap() {
        NotificationRule__c    rule    = [SELECT Id FROM NotificationRule__c LIMIT 1];
        NotificationChannel__c channel = [SELECT Id FROM NotificationChannel__c LIMIT 1];
        Id recordId = UserInfo.getUserId();

        String key = CooldownManager.buildKey(rule.Id, recordId, channel.Id);

        insert new NotificationLog__c(
            Rule__c         = rule.Id,
            Channel__c      = channel.Id,
            Channel_Type__c = 'Email',
            Status__c       = 'Sent',
            Sent_At__c      = DateTime.now().addMinutes(-61),
            Cooldown_Key__c = key,
            Record_Id__c    = String.valueOf(recordId)
        );

        Test.startTest();
        Map<String, DateTime> result = CooldownManager.getLastSentTimes(
            new Set<String>{ key }, 60
        );
        Test.stopTest();

        System.assert(result.isEmpty(), 'Log outside window must not be returned');
    }
}
