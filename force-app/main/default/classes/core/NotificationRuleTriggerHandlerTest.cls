@IsTest
private class NotificationRuleTriggerHandlerTest {

    // ── Base rule builder — all required fields populated with valid values ───

    private static NotificationRule__c validRule() {
        return new NotificationRule__c(
            Rule_Label__c         = 'Test Rule',
            Object_API_Name__c    = 'Account',
            Trigger_Event__c      = 'Update',
            Condition_Class__c    = 'FieldChangedEvaluator',
            Recipient_Strategy__c = 'Owner',
            Active__c             = true
        );
    }

    // ── Insert: valid rules ───────────────────────────────────────────────────

    @IsTest
    static void testInsert_validRule_succeeds() {
        Test.startTest();
        insert validRule();
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM NotificationRule__c], 'Valid rule must save successfully');
    }

    @IsTest
    static void testInsert_apexResolver_withResolverClass_succeeds() {
        NotificationRule__c rule  = validRule();
        rule.Recipient_Strategy__c    = 'ApexResolver';
        rule.Recipient_Resolver_Class__c = 'OwnerResolver';

        Test.startTest();
        insert rule;
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM NotificationRule__c], 'ApexResolver with class set must save');
    }

    @IsTest
    static void testInsert_nonApexResolver_blankResolverClass_succeeds() {
        // Owner strategy never requires Recipient_Resolver_Class__c
        NotificationRule__c rule = validRule();
        rule.Recipient_Strategy__c    = 'Owner';
        rule.Recipient_Resolver_Class__c = null;

        Test.startTest();
        insert rule;
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM NotificationRule__c], 'Non-ApexResolver with blank resolver must save');
    }

    // ── Insert: invalid Condition_Class__c ────────────────────────────────────

    @IsTest
    static void testInsert_nonExistentConditionClass_addsFieldError() {
        NotificationRule__c rule = validRule();
        rule.Condition_Class__c = 'CompletelyNonExistentClass99999';

        Test.startTest();
        try {
            insert rule;
            System.assert(false, 'Expected DmlException for non-existent class');
        } catch (DmlException e) {
            System.assert(
                e.getDmlMessage(0).contains('not found'),
                'Error must mention "not found": ' + e.getDmlMessage(0)
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testInsert_classNotImplementingInterface_addsFieldError() {
        // LogService exists in the org but does NOT implement IConditionEvaluator
        NotificationRule__c rule = validRule();
        rule.Condition_Class__c = 'LogService';

        Test.startTest();
        try {
            insert rule;
            System.assert(false, 'Expected DmlException for wrong interface');
        } catch (DmlException e) {
            System.assert(
                e.getDmlMessage(0).contains('IConditionEvaluator'),
                'Error must mention IConditionEvaluator: ' + e.getDmlMessage(0)
            );
        }
        Test.stopTest();
    }

    // ── Insert: invalid Recipient_Resolver_Class__c ───────────────────────────

    @IsTest
    static void testInsert_apexResolver_blankResolverClass_addsFieldError() {
        NotificationRule__c rule = validRule();
        rule.Recipient_Strategy__c       = 'ApexResolver';
        rule.Recipient_Resolver_Class__c = null;

        Test.startTest();
        try {
            insert rule;
            System.assert(false, 'Expected DmlException for blank resolver class');
        } catch (DmlException e) {
            System.assert(
                e.getDmlMessage(0).contains('Recipient Resolver Class is required'),
                'Error must mention resolver class requirement: ' + e.getDmlMessage(0)
            );
        }
        Test.stopTest();
    }

    // ── Update: relevant field changed ────────────────────────────────────────

    @IsTest
    static void testUpdate_conditionClassChangedToInvalid_addsFieldError() {
        NotificationRule__c rule = validRule();
        insert rule;

        rule.Condition_Class__c = 'NonExistentClass99999';

        Test.startTest();
        try {
            update rule;
            System.assert(false, 'Expected DmlException on update with invalid class');
        } catch (DmlException e) {
            System.assert(
                e.getDmlMessage(0).contains('not found'),
                'Error must mention "not found": ' + e.getDmlMessage(0)
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdate_conditionClassChangedToValid_succeeds() {
        NotificationRule__c rule = validRule();
        insert rule;

        // FormulaEvaluator also implements IConditionEvaluator
        rule.Condition_Class__c = 'FormulaEvaluator';

        Test.startTest();
        update rule;
        Test.stopTest();

        System.assertEquals(
            'FormulaEvaluator',
            [SELECT Condition_Class__c FROM NotificationRule__c LIMIT 1].Condition_Class__c,
            'Valid class update must save'
        );
    }

    @IsTest
    static void testUpdate_unrelatedFieldChanged_skipsValidation() {
        NotificationRule__c rule = validRule();
        insert rule;

        // Toggling Active__c does not touch any validated field — must save without re-validation
        rule.Active__c = false;

        Test.startTest();
        update rule;
        Test.stopTest();

        System.assertEquals(
            false,
            [SELECT Active__c FROM NotificationRule__c LIMIT 1].Active__c,
            'Unrelated field update must save without validation error'
        );
    }
}
