public without sharing class CooldownManager {

    /**
     * Composite key stored on NotificationLog__c.Cooldown_Key__c.
     * Format: ruleId|recordId|channelId
     */
    public static String buildKey(Id ruleId, Id recordId, Id channelId) {
        return String.valueOf(ruleId) + '|' + String.valueOf(recordId) + '|' + String.valueOf(channelId);
    }

    /**
     * Single pre-query — called ONCE by the Router before the per-channel loop.
     * Returns the most recent Sent_At__c for each key within maxCooldownMinutes.
     * Passing this map into isOnCooldown() keeps the main loop zero-SOQL.
     *
     * @param keys               all (ruleId|recordId|channelId) combos for this CDC batch
     * @param maxCooldownMinutes broadest Cooldown_Minutes__c across all active rules
     */
    public static Map<String, DateTime> getLastSentTimes(Set<String> keys, Decimal maxCooldownMinutes) {
        Map<String, DateTime> result = new Map<String, DateTime>();
        if (keys == null || keys.isEmpty()) return result;
        if (maxCooldownMinutes == null || maxCooldownMinutes <= 0) return result;

        DateTime cutoff = DateTime.now().addMinutes(-Integer.valueOf(maxCooldownMinutes));

        for (NotificationLog__c log : [
            SELECT Cooldown_Key__c, Sent_At__c
            FROM   NotificationLog__c
            WHERE  Cooldown_Key__c IN :keys
              AND  Status__c        = 'Sent'
              AND  Sent_At__c      >= :cutoff
            ORDER BY Sent_At__c DESC
        ]) {
            // ORDER BY DESC — first occurrence per key is the most recent
            if (!result.containsKey(log.Cooldown_Key__c)) {
                result.put(log.Cooldown_Key__c, log.Sent_At__c);
            }
        }
        return result;
    }

    /**
     * Pure in-memory check — zero SOQL. Called inside the per-channel loop.
     *
     * @param lastSentByKey  result of getLastSentTimes() for this batch
     * @param cooldownMinutes this rule's specific suppression window
     */
    public static Boolean isOnCooldown(
        Map<String, DateTime> lastSentByKey,
        Id      ruleId,
        Id      recordId,
        Id      channelId,
        Decimal cooldownMinutes
    ) {
        if (cooldownMinutes == null || cooldownMinutes <= 0) return false;
        if (ruleId == null || recordId == null || channelId == null) return false;
        if (lastSentByKey == null || lastSentByKey.isEmpty()) return false;

        DateTime lastSent = lastSentByKey.get(buildKey(ruleId, recordId, channelId));
        if (lastSent == null) return false;

        DateTime cutoff = DateTime.now().addMinutes(-Integer.valueOf(cooldownMinutes));
        return lastSent >= cutoff;
    }
}
