@IsTest
private class FieldChangedEvaluatorTest {

    // ─── helpers ─────────────────────────────────────────────────────────────

    private static EvaluationContext buildCtx(
        String fieldName,
        Object fieldValue,
        Set<String> changedFields,
        String conditionJson
    ) {
        Account record = new Account(Name = 'Test Co');
        record.put(fieldName, fieldValue);

        NotificationRule__c rule = new NotificationRule__c();

        Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(conditionJson);
        return new EvaluationContext(record, null, changedFields, rule, config);
    }

    // ─── equals (default) ────────────────────────────────────────────────────

    @IsTest
    static void testEquals_fieldChangedToExpectedValue_returnsTrue() {
        EvaluationContext ctx = buildCtx(
            'Type', 'Customer - Direct',
            new Set<String>{'Type'},
            '{"field":"Type","value":"Customer - Direct"}'
        );
        System.assertEquals(true, new FieldChangedEvaluator().evaluate(ctx));
    }

    @IsTest
    static void testEquals_fieldChangedButWrongValue_returnsFalse() {
        EvaluationContext ctx = buildCtx(
            'Type', 'Prospect',
            new Set<String>{'Type'},
            '{"field":"Type","value":"Customer - Direct"}'
        );
        System.assertEquals(false, new FieldChangedEvaluator().evaluate(ctx));
    }

    @IsTest
    static void testEquals_caseInsensitive_returnsTrue() {
        EvaluationContext ctx = buildCtx(
            'Type', 'customer - direct',
            new Set<String>{'Type'},
            '{"field":"Type","value":"Customer - Direct"}'
        );
        System.assertEquals(true, new FieldChangedEvaluator().evaluate(ctx));
    }

    // ─── field not changed ───────────────────────────────────────────────────

    @IsTest
    static void testFieldNotInChangedFields_returnsFalse() {
        EvaluationContext ctx = buildCtx(
            'Type', 'Customer - Direct',
            new Set<String>{'Rating'},  // Type did not change
            '{"field":"Type","value":"Customer - Direct"}'
        );
        System.assertEquals(false, new FieldChangedEvaluator().evaluate(ctx));
    }

    @IsTest
    static void testEmptyChangedFields_returnsFalse() {
        EvaluationContext ctx = buildCtx(
            'Type', 'Customer - Direct',
            new Set<String>(),
            '{"field":"Type","value":"Customer - Direct"}'
        );
        System.assertEquals(false, new FieldChangedEvaluator().evaluate(ctx));
    }

    // ─── no value — any change triggers ─────────────────────────────────────

    @IsTest
    static void testNoValueConfigured_anyChangeReturnsTrue() {
        EvaluationContext ctx = buildCtx(
            'Type', 'Anything',
            new Set<String>{'Type'},
            '{"field":"Type"}'
        );
        System.assertEquals(true, new FieldChangedEvaluator().evaluate(ctx));
    }

    // ─── not_equals ──────────────────────────────────────────────────────────

    @IsTest
    static void testNotEquals_differentValue_returnsTrue() {
        EvaluationContext ctx = buildCtx(
            'Type', 'Prospect',
            new Set<String>{'Type'},
            '{"field":"Type","operator":"not_equals","value":"Customer - Direct"}'
        );
        System.assertEquals(true, new FieldChangedEvaluator().evaluate(ctx));
    }

    @IsTest
    static void testNotEquals_sameValue_returnsFalse() {
        EvaluationContext ctx = buildCtx(
            'Type', 'Customer - Direct',
            new Set<String>{'Type'},
            '{"field":"Type","operator":"not_equals","value":"Customer - Direct"}'
        );
        System.assertEquals(false, new FieldChangedEvaluator().evaluate(ctx));
    }

    // ─── contains ────────────────────────────────────────────────────────────

    @IsTest
    static void testContains_valueContainsSubstring_returnsTrue() {
        EvaluationContext ctx = buildCtx(
            'Name', 'Acme Corporation Ltd',
            new Set<String>{'Name'},
            '{"field":"Name","operator":"contains","value":"Corporation"}'
        );
        System.assertEquals(true, new FieldChangedEvaluator().evaluate(ctx));
    }

    @IsTest
    static void testContains_valueDoesNotContain_returnsFalse() {
        EvaluationContext ctx = buildCtx(
            'Name', 'Acme Ltd',
            new Set<String>{'Name'},
            '{"field":"Name","operator":"contains","value":"Corporation"}'
        );
        System.assertEquals(false, new FieldChangedEvaluator().evaluate(ctx));
    }

    // ─── greater_than ────────────────────────────────────────────────────────

    @IsTest
    static void testGreaterThan_actualAboveThreshold_returnsTrue() {
        EvaluationContext ctx = buildCtx(
            'AnnualRevenue', 2000000,
            new Set<String>{'AnnualRevenue'},
            '{"field":"AnnualRevenue","operator":"greater_than","value":"1500000"}'
        );
        System.assertEquals(true, new FieldChangedEvaluator().evaluate(ctx));
    }

    @IsTest
    static void testGreaterThan_actualBelowThreshold_returnsFalse() {
        EvaluationContext ctx = buildCtx(
            'AnnualRevenue', 500000,
            new Set<String>{'AnnualRevenue'},
            '{"field":"AnnualRevenue","operator":"greater_than","value":"1500000"}'
        );
        System.assertEquals(false, new FieldChangedEvaluator().evaluate(ctx));
    }

    @IsTest
    static void testGreaterThan_equalToThreshold_returnsFalse() {
        EvaluationContext ctx = buildCtx(
            'AnnualRevenue', 1500000,
            new Set<String>{'AnnualRevenue'},
            '{"field":"AnnualRevenue","operator":"greater_than","value":"1500000"}'
        );
        System.assertEquals(false, new FieldChangedEvaluator().evaluate(ctx));
    }

    // ─── less_than ───────────────────────────────────────────────────────────

    @IsTest
    static void testLessThan_actualBelowThreshold_returnsTrue() {
        EvaluationContext ctx = buildCtx(
            'AnnualRevenue', 100000,
            new Set<String>{'AnnualRevenue'},
            '{"field":"AnnualRevenue","operator":"less_than","value":"500000"}'
        );
        System.assertEquals(true, new FieldChangedEvaluator().evaluate(ctx));
    }

    @IsTest
    static void testLessThan_actualAboveThreshold_returnsFalse() {
        EvaluationContext ctx = buildCtx(
            'AnnualRevenue', 900000,
            new Set<String>{'AnnualRevenue'},
            '{"field":"AnnualRevenue","operator":"less_than","value":"500000"}'
        );
        System.assertEquals(false, new FieldChangedEvaluator().evaluate(ctx));
    }

    // ─── missing field config ─────────────────────────────────────────────────

    @IsTest
    static void testMissingFieldConfig_returnsFalse() {
        Account record = new Account(Name = 'Test');
        NotificationRule__c rule = new NotificationRule__c();
        EvaluationContext ctx = new EvaluationContext(
            record, null, new Set<String>{'Type'}, rule,
            new Map<String, Object>()  // no 'field' key
        );
        System.assertEquals(false, new FieldChangedEvaluator().evaluate(ctx));
    }
}
