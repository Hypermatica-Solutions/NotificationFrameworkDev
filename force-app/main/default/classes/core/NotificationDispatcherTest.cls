@IsTest
private class NotificationDispatcherTest {

    @TestSetup
    static void setup() {
        insert new NotificationRule__c(
            Rule_Label__c               = 'Dispatcher Test Rule',
            Object_API_Name__c          = 'Account',
            Trigger_Event__c            = 'Update',
            Watched_Fields__c           = 'AnnualRevenue',
            Condition_Class__c          = 'FieldChangedEvaluator',
            Condition_Config__c         = '{"field":"AnnualRevenue"}',
            Recipient_Strategy__c       = 'ApexResolver',
            Recipient_Resolver_Class__c = 'AccountOwnerResolver',
            Active__c                   = true
        );

        insert new NotificationTemplate__c(
            Name            = 'Dispatcher Test Template',
            Template_Key__c = 'DISP_TEST_TMPL',
            Channel_Type__c = 'Email',
            Subject__c      = 'Account Revenue Changed'
        );
    }

    // ─── helper: build a mock AccountChangeEvent without firing the CDC trigger ──
    // dispatch() uses JSON.serialize(evt) internally to read the header, so setting
    // EventBus.ChangeEventHeader directly produces the correct JSON structure.

    private static AccountChangeEvent buildMockEvent(Id recordId, List<String> changedFields) {
        EventBus.ChangeEventHeader ceh = new EventBus.ChangeEventHeader();
        ceh.changeType    = 'UPDATE';
        ceh.changedFields = changedFields;
        ceh.commitUser    = String.valueOf(UserInfo.getUserId());
        ceh.recordIds     = new List<String>{ String.valueOf(recordId) };

        AccountChangeEvent evt = new AccountChangeEvent();
        evt.ChangeEventHeader = ceh;
        return evt;
    }

    // ─── guard clauses ────────────────────────────────────────────────────────

    @IsTest
    static void testDispatch_nullEvents_doesNotThrow() {
        Test.startTest();
        NotificationDispatcher.dispatch(null, 'Account');
        Test.stopTest();
        System.assert(true, 'Null events list should return silently without throwing');
    }

    @IsTest
    static void testDispatch_emptyEvents_doesNotThrow() {
        Test.startTest();
        NotificationDispatcher.dispatch(new List<SObject>(), 'Account');
        Test.stopTest();
        System.assert(true, 'Empty events list should return silently without throwing');
    }

    // ─── direct dispatch with mock event ─────────────────────────────────────

    @IsTest
    static void testDispatch_accountUpdate_createsLog() {
        NotificationRule__c     rule = [SELECT Id FROM NotificationRule__c LIMIT 1];
        NotificationTemplate__c tmpl = [SELECT Id FROM NotificationTemplate__c LIMIT 1];

        insert new NotificationChannel__c(
            Rule__c         = rule.Id,
            Channel_Type__c = 'Email',
            Template__c     = tmpl.Id,
            Active__c       = true
        );

        Account acc = new Account(
            Name          = 'Dispatch Mock Co',
            OwnerId       = UserInfo.getUserId(),
            AnnualRevenue = 2000000
        );
        insert acc;

        RuleCache.clearCache();

        // Call dispatch() directly with a constructed mock event —
        // bypasses CDC trigger delivery which is unreliable in test context.
        AccountChangeEvent mockEvt = buildMockEvent(acc.Id, new List<String>{ 'AnnualRevenue' });

        Test.startTest();
        NotificationDispatcher.dispatch(new List<SObject>{ mockEvt }, 'Account');
        Test.stopTest();

        Integer logCount = [SELECT COUNT() FROM NotificationLog__c WHERE Rule__c = :rule.Id];
        System.assertEquals(1, logCount,
            'dispatch() should route the event through the full chain and create one log record');
    }

    @IsTest
    static void testDispatch_noChannelAttached_noLogCreated() {
        // Rule exists but no channel → bundle.channels is empty → no delivery → no log
        NotificationRule__c rule = [SELECT Id FROM NotificationRule__c LIMIT 1];

        Account acc = new Account(
            Name          = 'No Channel Co',
            OwnerId       = UserInfo.getUserId(),
            AnnualRevenue = 2000000
        );
        insert acc;

        RuleCache.clearCache();

        AccountChangeEvent mockEvt = buildMockEvent(acc.Id, new List<String>{ 'AnnualRevenue' });

        Test.startTest();
        NotificationDispatcher.dispatch(new List<SObject>{ mockEvt }, 'Account');
        Test.stopTest();

        Integer logCount = [SELECT COUNT() FROM NotificationLog__c WHERE Rule__c = :rule.Id];
        System.assertEquals(0, logCount,
            'No log expected when the rule has no active channels attached');
    }
}
