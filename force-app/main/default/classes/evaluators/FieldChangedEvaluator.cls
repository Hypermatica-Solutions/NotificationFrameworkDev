/**
 * IConditionEvaluator implementation that checks whether a specific field
 * changed AND (optionally) now holds a particular value.
 *
 * Condition_Config__c JSON keys:
 *   field    (required) – API name of the field to inspect, e.g. "AnnualRevenue"
 *   value    (optional) – expected value to compare against
 *                         omit to trigger on any change to the field
 *   operator (optional) – "equals" (default) | "not_equals" | "contains"
 *                       | "greater_than" | "less_than"
 *
 * Numeric operators (greater_than, less_than) parse both actual and expected
 * as Decimal for accurate comparison. Falls back to string comparison if either
 * value cannot be parsed as a number.
 *
 * Example configs:
 *   {"field": "Type", "value": "Customer - Direct"}
 *   {"field": "AnnualRevenue", "operator": "greater_than", "value": "1500000"}
 */
global with sharing class FieldChangedEvaluator implements IConditionEvaluator {

    global Boolean evaluate(EvaluationContext ctx) {
        String fieldName     = (String) ctx.config.get('field');
        String expectedValue = (String) ctx.config.get('value');
        String operator      = ctx.config.containsKey('operator')
                                ? ((String) ctx.config.get('operator')).toLowerCase()
                                : 'equals';

        if (String.isBlank(fieldName)) {
            System.debug('FieldChangedEvaluator: "field" missing in Condition_Config__c');
            return false;
        }

        // Step 1 — field must appear in changedFields reported by CDC
        Boolean fieldChanged = false;
        for (String changed : ctx.changedFields) {
            if (changed.equalsIgnoreCase(fieldName)) {
                fieldChanged = true;
                break;
            }
        }

        if (!fieldChanged) {
            System.debug('FieldChangedEvaluator: field "' + fieldName + '" did not change');
            return false;
        }

        // Step 2 — if no expected value is configured, any change is sufficient
        if (String.isBlank(expectedValue)) return true;

        // Step 3 — compare the new field value against the expected value
        Object actualRaw = ctx.newRecord.get(fieldName);
        String actual    = actualRaw != null ? String.valueOf(actualRaw) : '';

        System.debug('FieldChangedEvaluator: field=' + fieldName
            + ' actual=' + actual + ' expected=' + expectedValue + ' op=' + operator);

        if (operator == 'not_equals') {
            return !actual.equalsIgnoreCase(expectedValue);

        } else if (operator == 'contains') {
            return actual.toLowerCase().contains(expectedValue.toLowerCase());

        } else if (operator == 'greater_than') {
            try {
                return Decimal.valueOf(actual) > Decimal.valueOf(expectedValue);
            } catch (Exception e) {
                System.debug('FieldChangedEvaluator: greater_than — non-numeric values, falling back to string compare');
                return actual > expectedValue;
            }

        } else if (operator == 'less_than') {
            try {
                return Decimal.valueOf(actual) < Decimal.valueOf(expectedValue);
            } catch (Exception e) {
                System.debug('FieldChangedEvaluator: less_than — non-numeric values, falling back to string compare');
                return actual < expectedValue;
            }

        } else {
            // default: equals
            return actual.equalsIgnoreCase(expectedValue);
        }
    }
}
