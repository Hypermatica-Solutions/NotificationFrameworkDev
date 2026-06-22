public with sharing class RecordQueryService {

    /**
     * Dynamically re-queries all accessible fields for the given record IDs.
     * CDC events only carry changed fields — this gives the Router the full record.
     *
     * @param objectApiName  e.g. "Account"
     * @param recordIds      set of record Ids to fetch
     * @return               map of Id → SObject with all accessible fields populated
     */
    public static Map<Id, SObject> queryByIds(String objectApiName, Set<Id> recordIds) {
        if (String.isBlank(objectApiName) || recordIds == null || recordIds.isEmpty()) {
            return new Map<Id, SObject>();
        }

        Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectApiName);
        if (sObjType == null) {
            System.debug('RecordQueryService: unknown object API name: ' + objectApiName);
            return new Map<Id, SObject>();
        }

        List<String> accessibleFields = new List<String>();
        for (String fieldName : sObjType.getDescribe().fields.getMap().keySet()) {
            if (sObjType.getDescribe().fields.getMap().get(fieldName).getDescribe().isAccessible()) {
                accessibleFields.add(fieldName);
            }
        }

        String soql = 'SELECT ' + String.join(accessibleFields, ', ')
                    + ' FROM ' + String.escapeSingleQuotes(objectApiName)
                    + ' WHERE Id IN :recordIds';

        Map<Id, SObject> result = new Map<Id, SObject>();
        for (SObject record : Database.query(soql)) {
            result.put(record.Id, record);
        }
        return result;
    }
}
