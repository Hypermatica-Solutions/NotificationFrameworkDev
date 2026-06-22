global without sharing class NotificationDispatcher {

    /**
     * Called from every CDC trigger (one call per object type).
     * Extracts change metadata, re-queries full records, then hands off to the Router.
     *
     * @param changeEvents  Trigger.new from the CDC trigger
     * @param objectApiName API name of the watched object, e.g. "Account"
     */
    global static void dispatch(List<SObject> changeEvents, String objectApiName) {
        if (changeEvents == null || changeEvents.isEmpty()) return;

        Set<Id>              recordIds             = new Set<Id>();
        Map<Id, Set<String>> changedFieldsByRecord = new Map<Id, Set<String>>();
        Map<Id, String>      changeTypeByRecord    = new Map<Id, String>();
        Map<Id, Id>          commitUserByRecord    = new Map<Id, Id>();

        for (SObject evt : changeEvents) {
            // ChangeEventHeader is not a castable SObject — read via JSON round-trip
            Map<String, Object> evtMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(evt));
            Map<String, Object> header = (Map<String, Object>) evtMap.get('ChangeEventHeader');

            String       changeType    = (String)       header.get('changeType');
            List<Object> changedFields = (List<Object>) header.get('changedFields');
            String       commitUser    = (String)       header.get('commitUser');
            List<Object> ids           = (List<Object>) header.get('recordIds');

            Set<String> fieldSet = new Set<String>();
            if (changedFields != null) {
                for (Object f : changedFields) fieldSet.add((String) f);
            }

            if (ids != null) {
                for (Object rid : ids) {
                    Id recordId = (Id)(String) rid;
                    recordIds.add(recordId);
                    changedFieldsByRecord.put(recordId, fieldSet);
                    changeTypeByRecord.put(recordId, changeType);
                    if (String.isNotBlank(commitUser)) {
                        commitUserByRecord.put(recordId, (Id) commitUser);
                    }
                }
            }
        }

        // Re-query full records (CDC only gives changed fields)
        // Query all the notification rules and 
        // TODO: We will first get all rules for this object which will help us get all the fields that need to be quried.
        Map<Id, SObject> records = RecordQueryService.queryByIds(objectApiName, recordIds);

        // Hand off to the Router
        NotificationRouter.route(records, changedFieldsByRecord, changeTypeByRecord, commitUserByRecord);
    }
}
