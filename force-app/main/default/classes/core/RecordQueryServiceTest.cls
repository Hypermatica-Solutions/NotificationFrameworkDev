@IsTest
private class RecordQueryServiceTest {

    // ─── guard clauses ────────────────────────────────────────────────────────

    @IsTest
    static void testBlankObjectName_returnsEmptyMap() {
        Map<Id, SObject> result = RecordQueryService.queryByIds('', new Set<Id>{ UserInfo.getUserId() });
        System.assertEquals(0, result.size(), 'Blank object name should return empty map');
    }

    @IsTest
    static void testNullObjectName_returnsEmptyMap() {
        Map<Id, SObject> result = RecordQueryService.queryByIds(null, new Set<Id>{ UserInfo.getUserId() });
        System.assertEquals(0, result.size(), 'Null object name should return empty map');
    }

    @IsTest
    static void testNullRecordIds_returnsEmptyMap() {
        Map<Id, SObject> result = RecordQueryService.queryByIds('Account', null);
        System.assertEquals(0, result.size(), 'Null recordIds should return empty map');
    }

    @IsTest
    static void testEmptyRecordIds_returnsEmptyMap() {
        Map<Id, SObject> result = RecordQueryService.queryByIds('Account', new Set<Id>());
        System.assertEquals(0, result.size(), 'Empty recordIds should return empty map');
    }

    @IsTest
    static void testUnknownObjectName_returnsEmptyMap() {
        Map<Id, SObject> result = RecordQueryService.queryByIds('NotARealObject__xyz', new Set<Id>{ UserInfo.getUserId() });
        System.assertEquals(0, result.size(), 'Unknown object API name should return empty map gracefully');
    }

    // ─── valid queries ────────────────────────────────────────────────────────

    @IsTest
    static void testSingleAccount_returnsRecord() {
        Account acc = new Account(Name = 'Query Service Test Co');
        insert acc;

        Test.startTest();
        Map<Id, SObject> result = RecordQueryService.queryByIds('Account', new Set<Id>{ acc.Id });
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return exactly one record');
        System.assert(result.containsKey(acc.Id), 'Result must be keyed by record Id');
    }

    @IsTest
    static void testMultipleAccounts_returnsAll() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Query Service Co A'),
            new Account(Name = 'Query Service Co B')
        };
        insert accounts;

        Set<Id> ids = new Set<Id>{ accounts[0].Id, accounts[1].Id };

        Test.startTest();
        Map<Id, SObject> result = RecordQueryService.queryByIds('Account', ids);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should return one entry per requested record Id');
    }

    @IsTest
    static void testReturnedRecord_hasPopulatedFields() {
        Account acc = new Account(Name = 'Fields Test Co', Phone = '555-9999');
        insert acc;

        Map<Id, SObject> result = RecordQueryService.queryByIds('Account', new Set<Id>{ acc.Id });
        Account returned = (Account) result.get(acc.Id);

        System.assertNotEquals(null, returned);
        System.assertEquals('Fields Test Co', returned.Name, 'Name field should be populated on returned record');
    }

    @IsTest
    static void testNonExistentId_returnsEmptyMap() {
        // Delete the account immediately so the Id is invalid
        Account acc = new Account(Name = 'Gone Co');
        insert acc;
        Id deletedId = acc.Id;
        delete acc;

        Map<Id, SObject> result = RecordQueryService.queryByIds('Account', new Set<Id>{ deletedId });
        System.assertEquals(0, result.size(), 'Deleted record Id should return no results');
    }
}
