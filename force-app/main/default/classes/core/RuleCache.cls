public without sharing class RuleCache {

    /**
     * Holds one NotificationRule__c together with all its active NotificationChannel__c records.
     * Router works with RuleBundle objects — one bundle per rule.
     */
    public class RuleBundle {
        public NotificationRule__c rule;
        public List<NotificationChannel__c> channels;

        public RuleBundle(NotificationRule__c rule) {
            this.rule     = rule;
            this.channels = new List<NotificationChannel__c>();
        }
    }

    // key: "account|update"  →  list of bundles for that object + event
    private static Map<String, List<RuleBundle>> cache;

    /**
     * Returns all active rule bundles matching the given object and trigger event.
     * Results are ordered by Priority__c ASC (lower number = higher priority).
     *
     * @param objectApiName  e.g. "Account"
     * @param triggerEvent   e.g. "Update" (matches Trigger_Event__c picklist value)
     */
    public static List<RuleBundle> getRules(String objectApiName, String triggerEvent) {
        if (cache == null) {
            load();
        }
        String key = buildKey(objectApiName, triggerEvent);
        List<RuleBundle> result = cache.get(key);
        return result != null ? result : new List<RuleBundle>();
    }

    /** Clears the in-memory cache (used in tests to reset state between scenarios). */
    @TestVisible
    public static void clearCache() {
        cache = null;
    }

    // ─── private ─────────────────────────────────────────────────────────────

    private static void load() {
        cache = new Map<String, List<RuleBundle>>();

        // ── Query 1: fetch all active rules ordered by priority ───────────────
        List<NotificationRule__c> activeRules = [
            SELECT Id, Rule_Label__c, Object_API_Name__c, Trigger_Event__c,
                   Watched_Fields__c, Condition_Class__c, Condition_Config__c,
                   Recipient_Strategy__c, Recipient_Config__c, Recipient_Resolver_Class__c,
                   Cooldown_Minutes__c, Priority__c
            FROM   NotificationRule__c
            WHERE  Active__c = true
            ORDER BY Priority__c ASC NULLS LAST
        ];

        if (activeRules.isEmpty()) return;

        // Build bundle map — loop over list, zero SOQL inside
        Map<Id, RuleBundle> bundleById = new Map<Id, RuleBundle>();
        for (NotificationRule__c rule : activeRules) {
            RuleBundle bundle = new RuleBundle(rule);
            bundleById.put(rule.Id, bundle);

            String key = buildKey(rule.Object_API_Name__c, rule.Trigger_Event__c);
            if (!cache.containsKey(key)) {
                cache.put(key, new List<RuleBundle>());
            }
            cache.get(key).add(bundle);
        }

        // ── Query 2: fetch all active channels for those rules ────────────────
        List<NotificationChannel__c> activeChannels = [
            SELECT Id, Rule__c, Channel_Type__c, Channel_Config__c,
                   Template__c,
                   Template__r.Template_Key__c,
                   Template__r.Subject__c,
                   Template__r.Body__c,
                   Template__r.Body_Is_HTML__c,
                   Template__r.Language__c,
                   Template__r.Email_Template_Name__c,
                   Template__r.Bell_Body__c
            FROM   NotificationChannel__c
            WHERE  Rule__c IN :bundleById.keySet()
            AND    Active__c = true
        ];

        // Attach each channel to its bundle — loop over list, zero SOQL inside
        for (NotificationChannel__c channel : activeChannels) {
            bundleById.get(channel.Rule__c).channels.add(channel);
        }
    }

    private static String buildKey(String objectApiName, String triggerEvent) {
        return objectApiName.toLowerCase() + '|' + triggerEvent.toLowerCase();
    }
}
