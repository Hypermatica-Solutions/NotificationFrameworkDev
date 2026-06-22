@IsTest
private class FormulaEvaluatorTest {

    // ─── helpers ─────────────────────────────────────────────────────────────

    // HasOptedOutOfEmail is a standard settable Boolean field on Contact used
    // to simulate a Boolean formula field in tests (formula fields are read-only
    // and cannot be created in test context). Contact is used because Account
    // does not have a universally available settable Boolean field.

    private static EvaluationContext buildCtx(String formulaFieldName, Boolean fieldValue) {
        Contact record = new Contact(LastName = 'Formula Test');
        if (formulaFieldName != null && fieldValue != null) {
            record.put(formulaFieldName, fieldValue);
        }
        Map<String, Object> config = new Map<String, Object>{
            'formulaField' => formulaFieldName
        };
        return new EvaluationContext(record, null, new Set<String>(), new NotificationRule__c(), config);
    }

    // ─── formula field returns true ───────────────────────────────────────────

    @IsTest
    static void testFormulaFieldTrue_returnsTrue() {
        EvaluationContext ctx = buildCtx('HasOptedOutOfEmail', true);
        System.assertEquals(true, new FormulaEvaluator().evaluate(ctx),
            'evaluator should return true when the formula field evaluates to true');
    }

    // ─── formula field returns false ──────────────────────────────────────────

    @IsTest
    static void testFormulaFieldFalse_returnsFalse() {
        EvaluationContext ctx = buildCtx('HasOptedOutOfEmail', false);
        System.assertEquals(false, new FormulaEvaluator().evaluate(ctx),
            'evaluator should return false when the formula field evaluates to false');
    }

    @IsTest
    static void testFormulaFieldNotSet_returnsFalse() {
        // Field not set on the SObject → get() returns null → null == true → false
        Contact record = new Contact(LastName = 'Test');
        EvaluationContext ctx = new EvaluationContext(
            record, null, new Set<String>(), new NotificationRule__c(),
            new Map<String, Object>{ 'formulaField' => 'HasOptedOutOfEmail' }
        );
        System.assertEquals(false, new FormulaEvaluator().evaluate(ctx));
    }

    // ─── missing or blank config key ─────────────────────────────────────────

    @IsTest
    static void testMissingFormulaFieldKey_returnsFalse() {
        Account record = new Account(Name = 'Test Co');
        EvaluationContext ctx = new EvaluationContext(
            record, null, new Set<String>(), new NotificationRule__c(),
            new Map<String, Object>()  // no formulaField key at all
        );
        System.assertEquals(false, new FormulaEvaluator().evaluate(ctx));
    }

    @IsTest
    static void testEmptyFormulaFieldName_returnsFalse() {
        Account record = new Account(Name = 'Test Co');
        EvaluationContext ctx = new EvaluationContext(
            record, null, new Set<String>(), new NotificationRule__c(),
            new Map<String, Object>{ 'formulaField' => '' }
        );
        System.assertEquals(false, new FormulaEvaluator().evaluate(ctx));
    }

    // ─── non-existent field name ──────────────────────────────────────────────

    @IsTest
    static void testNonExistentField_returnsFalse() {
        // SObjectException is caught and returns false gracefully
        Account record = new Account(Name = 'Test Co');
        EvaluationContext ctx = new EvaluationContext(
            record, null, new Set<String>(), new NotificationRule__c(),
            new Map<String, Object>{ 'formulaField' => 'NonExistentField__xyz' }
        );
        System.assertEquals(false, new FormulaEvaluator().evaluate(ctx));
    }

    // ─── null guards ──────────────────────────────────────────────────────────

    @IsTest
    static void testNullCtx_returnsFalse() {
        System.assertEquals(false, new FormulaEvaluator().evaluate(null));
    }

    @IsTest
    static void testNullRecord_returnsFalse() {
        // Null record in context — evaluator must guard against NPE
        EvaluationContext ctx = new EvaluationContext(
            null, null, new Set<String>(), new NotificationRule__c(),
            new Map<String, Object>{ 'formulaField' => 'HasOptedOutOfEmail' }
        );
        System.assertEquals(false, new FormulaEvaluator().evaluate(ctx));
    }
}
