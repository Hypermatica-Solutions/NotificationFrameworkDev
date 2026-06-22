@IsTest
private class RuleCacheTest {

    // ─── helpers ─────────────────────────────────────────────────────────────

    private static NotificationRule__c insertRule(
        String label, String event, Integer priority, Boolean active
    ) {
        NotificationRule__c rule = new NotificationRule__c(
            Rule_Label__c               = label,
            Object_API_Name__c          = 'Account',
            Trigger_Event__c            = event,
            Condition_Class__c          = 'FieldChangedEvaluator',
            Condition_Config__c         = '{"field":"AnnualRevenue"}',
            Recipient_Strategy__c       = 'ApexResolver',
            Recipient_Resolver_Class__c = 'AccountOwnerResolver',
            Active__c                   = active,
            Priority__c                 = priority
        );
        insert rule;
        return rule;
    }

    private static void attachEmailChannel(Id ruleId, Boolean active) {
        NotificationTemplate__c tmpl = new NotificationTemplate__c(
            Name            = 'Cache Test Template',
            Template_Key__c = 'CACHE_TEST_TMPL',
            Channel_Type__c = 'Email',
            Subject__c      = 'Test'
        );
        insert tmpl;
        insert new NotificationChannel__c(
            Rule__c         = ruleId,
            Channel_Type__c = 'Email',
            Template__c     = tmpl.Id,
            Active__c       = active
        );
    }

    // ─── matching key ────────────────────────────────────────────────────────

    @IsTest
    static void testGetRules_matchingObjectAndEvent_returnsBundles() {
        insertRule('Test Rule', 'Update', 1, true);
        RuleCache.clearCache();

        List<RuleCache.RuleBundle> result = RuleCache.getRules('Account', 'Update');

        System.assert(!result.isEmpty(), 'Should return bundles for Account + Update');
        System.assertEquals('Test Rule', result[0].rule.Rule_Label__c);
    }

    @IsTest
    static void testGetRules_wrongEvent_returnsEmpty() {
        insertRule('Test Rule', 'Update', 1, true);
        RuleCache.clearCache();

        List<RuleCache.RuleBundle> result = RuleCache.getRules('Account', 'Create');

        System.assertEquals(0, result.size(), 'Wrong event should return empty list');
    }

    @IsTest
    static void testGetRules_wrongObject_returnsEmpty() {
        insertRule('Test Rule', 'Update', 1, true);
        RuleCache.clearCache();

        List<RuleCache.RuleBundle> result = RuleCache.getRules('Contact', 'Update');

        System.assertEquals(0, result.size(), 'Wrong object should return empty list');
    }

    // ─── active/inactive filtering ────────────────────────────────────────────

    @IsTest
    static void testInactiveRulesExcluded() {
        insertRule('Inactive Rule', 'Update', 1, false);
        RuleCache.clearCache();

        List<RuleCache.RuleBundle> result = RuleCache.getRules('Account', 'Update');

        System.assertEquals(0, result.size(), 'Inactive rules must not be returned');
    }

    @IsTest
    static void testBundleIncludesActiveChannels() {
        NotificationRule__c rule = insertRule('Rule With Channel', 'Update', 1, true);
        attachEmailChannel(rule.Id, true);
        RuleCache.clearCache();

        List<RuleCache.RuleBundle> result = RuleCache.getRules('Account', 'Update');

        System.assertEquals(1, result[0].channels.size(), 'Bundle should include the active channel');
    }

    @IsTest
    static void testInactiveChannelsExcluded() {
        NotificationRule__c rule = insertRule('Rule With Inactive Channel', 'Update', 1, true);
        attachEmailChannel(rule.Id, false);
        RuleCache.clearCache();

        List<RuleCache.RuleBundle> result = RuleCache.getRules('Account', 'Update');

        System.assertEquals(0, result[0].channels.size(), 'Inactive channels must not be in bundle');
    }

    // ─── priority ordering ────────────────────────────────────────────────────

    @IsTest
    static void testPriorityOrdering_lowerNumberFirst() {
        insertRule('Low Priority',  'Update', 10, true);
        insertRule('High Priority', 'Update',  1, true);
        RuleCache.clearCache();

        List<RuleCache.RuleBundle> result = RuleCache.getRules('Account', 'Update');

        System.assertEquals(2, result.size());
        System.assertEquals('High Priority', result[0].rule.Rule_Label__c, 'Lower priority number should come first');
        System.assertEquals('Low Priority',  result[1].rule.Rule_Label__c);
    }

    // ─── clearCache ───────────────────────────────────────────────────────────

    @IsTest
    static void testClearCache_forcesReload() {
        NotificationRule__c rule = insertRule('Cache Test Rule', 'Update', 1, true);
        RuleCache.clearCache();

        List<RuleCache.RuleBundle> before = RuleCache.getRules('Account', 'Update');
        System.assertEquals(1, before.size(), 'Rule should be returned before delete');

        delete rule;
        RuleCache.clearCache();

        List<RuleCache.RuleBundle> after = RuleCache.getRules('Account', 'Update');
        System.assertEquals(0, after.size(), 'Deleted rule should not appear after clearCache');
    }

    // ─── empty org ────────────────────────────────────────────────────────────

    @IsTest
    static void testNoRules_returnsEmptyList() {
        RuleCache.clearCache();

        List<RuleCache.RuleBundle> result = RuleCache.getRules('Account', 'Update');

        System.assertEquals(0, result.size(), 'No rules in org should return empty list');
    }
}
