@IsTest
private class FieldReferenceResolverTest {

    // ─── helpers ─────────────────────────────────────────────────────────────

    private static RecipientContext buildCtx(SObject record, String fieldName) {
        Map<String, Object> config = String.isNotBlank(fieldName)
            ? new Map<String, Object>{ 'field' => fieldName }
            : new Map<String, Object>();
        return new RecipientContext(record, new NotificationRule__c(), config);
    }

    // ─── happy path ───────────────────────────────────────────────────────────

    @IsTest
    static void testResolvesUserFromOwnerId() {
        // OwnerId is a standard User lookup on Account — always populated
        Account record = new Account(Name = 'Ref Test Co', OwnerId = UserInfo.getUserId());
        RecipientContext ctx = buildCtx(record, 'OwnerId');

        Test.startTest();
        Set<Id> result = new FieldReferenceResolver().resolve(ctx);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should resolve OwnerId as recipient');
        System.assert(result.contains(UserInfo.getUserId()));
    }

    @IsTest
    static void testResolvesUserFromCreatedById() {
        Account acc = new Account(Name = 'Created By Test');
        insert acc;
        acc = [SELECT Id, CreatedById FROM Account WHERE Id = :acc.Id];

        RecipientContext ctx = buildCtx(acc, 'CreatedById');

        Test.startTest();
        Set<Id> result = new FieldReferenceResolver().resolve(ctx);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should resolve CreatedById as recipient');
        System.assert(result.contains(acc.CreatedById));
    }

    // ─── null field value ────────────────────────────────────────────────────

    @IsTest
    static void testFieldValueNull_returnsEmpty() {
        // Account with no OwnerId populated on in-memory SObject
        Account record = new Account(Name = 'No Owner');
        RecipientContext ctx = buildCtx(record, 'OwnerId');

        Set<Id> result = new FieldReferenceResolver().resolve(ctx);

        System.assertEquals(0, result.size(), 'Null field value should return empty set');
    }

    // ─── missing config ───────────────────────────────────────────────────────

    @IsTest
    static void testMissingFieldConfig_returnsEmpty() {
        Account record = new Account(Name = 'Test', OwnerId = UserInfo.getUserId());
        RecipientContext ctx = buildCtx(record, null);

        System.assertEquals(0, new FieldReferenceResolver().resolve(ctx).size());
    }

    // ─── non-existent field ───────────────────────────────────────────────────

    @IsTest
    static void testNonExistentField_returnsEmpty() {
        Account record = new Account(Name = 'Test');
        RecipientContext ctx = new RecipientContext(
            record, new NotificationRule__c(),
            new Map<String, Object>{ 'field' => 'NonExistentField__xyz' }
        );

        Set<Id> result = new FieldReferenceResolver().resolve(ctx);

        System.assertEquals(0, result.size(), 'Non-existent field should return empty set gracefully');
    }

    // ─── null guards ─────────────────────────────────────────────────────────

    @IsTest
    static void testNullCtx_returnsEmpty() {
        System.assertEquals(0, new FieldReferenceResolver().resolve(null).size());
    }

    @IsTest
    static void testNullRecord_returnsEmpty() {
        RecipientContext ctx = new RecipientContext(
            null, new NotificationRule__c(),
            new Map<String, Object>{ 'field' => 'OwnerId' }
        );
        System.assertEquals(0, new FieldReferenceResolver().resolve(ctx).size());
    }
}
