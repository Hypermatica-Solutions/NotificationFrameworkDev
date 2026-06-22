@IsTest
private class NotificationRouterTest {

    // ─── helpers ─────────────────────────────────────────────────────────────

    private static NotificationRule__c insertRule(
        String watchedFields,
        String conditionClass,
        String conditionConfig,
        String resolverClass
    ) {
        // Condition_Class__c is required — default to FieldChangedEvaluator when not specified.
        // Default config '{"field":"AnnualRevenue"}' means "any AnnualRevenue change passes",
        // which aligns with the changedFields = {'AnnualRevenue'} used in all happy-path tests.
        String resolvedClass  = String.isBlank(conditionClass)  ? 'FieldChangedEvaluator'      : conditionClass;
        String resolvedConfig = String.isBlank(conditionConfig) ? '{"field":"AnnualRevenue"}' : conditionConfig;

        NotificationRule__c rule = new NotificationRule__c(
            Rule_Label__c               = 'Router Test Rule',
            Object_API_Name__c          = 'Account',
            Trigger_Event__c            = 'Update',
            Watched_Fields__c           = watchedFields,
            Condition_Class__c          = resolvedClass,
            Condition_Config__c         = resolvedConfig,
            Recipient_Strategy__c       = 'ApexResolver',
            Recipient_Resolver_Class__c = resolverClass,
            Active__c                   = true
        );
        insert rule;
        return rule;
    }

    private static void attachEmailChannel(Id ruleId) {
        NotificationTemplate__c tmpl = new NotificationTemplate__c(
            Name            = 'Router Test Template',
            Template_Key__c = 'ROUTER_TEST_TMPL',
            Channel_Type__c = 'Email',
            Subject__c      = 'Account Updated'
        );
        insert tmpl;
        insert new NotificationChannel__c(
            Rule__c         = ruleId,
            Channel_Type__c = 'Email',
            Template__c     = tmpl.Id,
            Active__c       = true
        );
    }

    private static Account insertAccount(Decimal annualRevenue) {
        Account acc = new Account(
            Name          = 'Router Test Co',
            OwnerId       = UserInfo.getUserId(),
            AnnualRevenue = annualRevenue
        );
        insert acc;
        return [SELECT Id, Name, OwnerId, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    }

    private static void callRoute(
        Account acc,
        Set<String> changedFields,
        String changeType
    ) {
        Map<Id, SObject>     records  = new Map<Id, SObject>{ acc.Id => acc };
        Map<Id, Set<String>> changed  = new Map<Id, Set<String>>{ acc.Id => changedFields };
        Map<Id, String>      evtType  = new Map<Id, String>{ acc.Id => changeType };
        Map<Id, Id>          commitBy = new Map<Id, Id>{ acc.Id => UserInfo.getUserId() };
        NotificationRouter.route(records, changed, evtType, commitBy);
    }

    // ─── null / empty guards ─────────────────────────────────────────────────

    @IsTest
    static void testRoute_nullRecords_doesNotThrow() {
        Test.startTest();
        NotificationRouter.route(null, null, null, null);
        Test.stopTest();
        System.assert(true, 'Null records should not throw');
    }

    @IsTest
    static void testRoute_emptyRecords_doesNotThrow() {
        Test.startTest();
        NotificationRouter.route(
            new Map<Id, SObject>(),
            new Map<Id, Set<String>>(),
            new Map<Id, String>(),
            new Map<Id, Id>()
        );
        Test.stopTest();
        System.assert(true, 'Empty records map should not throw');
    }

    // ─── no matching rule ────────────────────────────────────────────────────

    @IsTest
    static void testRoute_noMatchingRule_noLogCreated() {
        RuleCache.clearCache();
        Account acc = insertAccount(2000000);

        Test.startTest();
        callRoute(acc, new Set<String>{'AnnualRevenue'}, 'Update');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM NotificationLog__c], 'No rule means no log');
    }

    // ─── watched field guard ─────────────────────────────────────────────────

    @IsTest
    static void testRoute_watchedFieldNotChanged_noLogCreated() {
        // Rule watches AnnualRevenue, but only Name changed in this event
        NotificationRule__c rule = insertRule('AnnualRevenue', '', '', 'AccountOwnerResolver');
        attachEmailChannel(rule.Id);
        RuleCache.clearCache();

        Account acc = insertAccount(2000000);

        Test.startTest();
        callRoute(acc, new Set<String>{'Name'}, 'Update');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM NotificationLog__c WHERE Rule__c = :rule.Id],
            'Watched field not in changedFields — rule should be skipped');
    }

    // ─── condition evaluator guard ────────────────────────────────────────────

    @IsTest
    static void testRoute_conditionEvaluatesFalse_noLogCreated() {
        // Condition: AnnualRevenue > 9,999,999 — account only has 1,000, so fails
        NotificationRule__c rule = insertRule(
            'AnnualRevenue',
            'FieldChangedEvaluator',
            '{"field":"AnnualRevenue","operator":"greater_than","value":"9999999"}',
            'AccountOwnerResolver'
        );
        attachEmailChannel(rule.Id);
        RuleCache.clearCache();

        Account acc = insertAccount(1000);

        Test.startTest();
        callRoute(acc, new Set<String>{'AnnualRevenue'}, 'Update');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM NotificationLog__c WHERE Rule__c = :rule.Id],
            'Condition fails — rule should be skipped');
    }

    // ─── recipient resolver guard ────────────────────────────────────────────

    @IsTest
    static void testRoute_blankResolverClass_noLogCreated() {
        // Blank resolver class → resolveRecipients returns empty set → no delivery
        NotificationRule__c rule = insertRule('AnnualRevenue', '', '', '');
        attachEmailChannel(rule.Id);
        RuleCache.clearCache();

        Account acc = insertAccount(2000000);

        Test.startTest();
        callRoute(acc, new Set<String>{'AnnualRevenue'}, 'Update');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM NotificationLog__c WHERE Rule__c = :rule.Id],
            'Blank resolver class returns no recipients — no log expected');
    }

    // ─── happy path ───────────────────────────────────────────────────────────

    @IsTest
    static void testRoute_happyPath_emailDelivered_logCreated() {
        // Full end-to-end: rule matches, condition passes, owner resolved, email sent, log written
        NotificationRule__c rule = insertRule('AnnualRevenue', '', '', 'AccountOwnerResolver');
        attachEmailChannel(rule.Id);
        RuleCache.clearCache();

        Account acc = insertAccount(2000000);

        Test.startTest();
        callRoute(acc, new Set<String>{'AnnualRevenue'}, 'Update');
        Test.stopTest();

        Integer logCount = [SELECT COUNT() FROM NotificationLog__c WHERE Rule__c = :rule.Id];
        System.assertEquals(1, logCount, 'One log record should be created for the email delivery');
    }

    // ─── condition passes ────────────────────────────────────────────────────

    @IsTest
    static void testRoute_conditionPasses_logCreated() {
        // Condition: AnnualRevenue > 1,000,000 — account has 2,000,000, passes
        NotificationRule__c rule = insertRule(
            'AnnualRevenue',
            'FieldChangedEvaluator',
            '{"field":"AnnualRevenue","operator":"greater_than","value":"1000000"}',
            'AccountOwnerResolver'
        );
        attachEmailChannel(rule.Id);
        RuleCache.clearCache();

        Account acc = insertAccount(2000000);

        Test.startTest();
        callRoute(acc, new Set<String>{'AnnualRevenue'}, 'Update');
        Test.stopTest();

        Integer logCount = [SELECT COUNT() FROM NotificationLog__c WHERE Rule__c = :rule.Id];
        System.assertEquals(1, logCount, 'Condition passes — log should be created');
    }
}
