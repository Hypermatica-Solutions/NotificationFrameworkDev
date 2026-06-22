/**
 * IConditionEvaluator implementation that fires when a Boolean formula field
 * on the record evaluates to true.
 *
 * Use this when the notification condition is too complex for FieldChangedEvaluator
 * — build a checkbox formula field on the object instead and reference it here.
 * The record passed in ctx.newRecord is the fully re-queried record fetched by
 * RecordQueryService after the CDC commit, so the formula always reflects
 * the committed state.
 *
 * Condition_Config__c JSON keys:
 *   formulaField (required) – API name of the Boolean/checkbox formula field,
 *                             e.g. "Is_High_Value__c"
 *
 * Setup:
 *   1. Create a Formula(Checkbox) field on the object, e.g.:
 *        Is_High_Value__c  =  AnnualRevenue > 1000000
 *   2. Set Watched_Fields__c on the rule to the underlying field that drives
 *      the formula (e.g. "AnnualRevenue") — NOT the formula field itself,
 *      because CDC changedFields never includes read-only formula fields.
 *   3. Set Condition_Class__c = "FormulaEvaluator"
 *   4. Set Condition_Config__c = {"formulaField": "Is_High_Value__c"}
 *
 * Example configs:
 *   {"formulaField": "Is_High_Value__c"}
 *   {"formulaField": "Should_Notify_Owner__c"}
 */
global with sharing class FormulaEvaluator implements IConditionEvaluator {

    global Boolean evaluate(EvaluationContext ctx) {
        if (ctx == null || ctx.newRecord == null) return false;

        String fieldName = ctx.config.containsKey('formulaField')
            ? (String) ctx.config.get('formulaField')
            : null;

        if (String.isBlank(fieldName)) {
            System.debug('FormulaEvaluator: "formulaField" key missing from Condition_Config__c');
            return false;
        }

        Object value;
        try {
            value = ctx.newRecord.get(fieldName);
        } catch (SObjectException e) {
            System.debug('FormulaEvaluator: field "' + fieldName + '" not found on record — ' + e.getMessage());
            return false;
        }

        System.debug('FormulaEvaluator: field=' + fieldName + ' value=' + value);
        return value == true;
    }
}
