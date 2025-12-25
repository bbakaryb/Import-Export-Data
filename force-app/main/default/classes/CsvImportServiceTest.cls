@isTest
private class CsvImportServiceTest {

/* =========================================================
       Test data setup (executed once for the whole class)
       ========================================================= */
    @testSetup
    static void setupData() {
        List<Account> accounts = new List<Account>{
            new Account(
                Name = 'Existing Account 1',
                Phone = '0101010101',
                Rating = 'Hot'
            ),
            new Account(
                Name = 'Existing Account 2',
                Phone = '0202020202',
                Rating = 'Warm'
            )
        };
        insert accounts;
    }

    /* =========================================================
       Helpers
       ========================================================= */

    private static String toBase64(String csv) {
        return EncodingUtil.base64Encode(Blob.valueOf(csv));
    }

    private static Account getExistingAccount(String name) {
        return [
            SELECT Id, Name, Phone
            FROM Account
            WHERE Name =: name 
            LIMIT 1
        ];
    }

    /* =========================================================
       INSERT – Happy path (API names)
       ========================================================= */

    @IsTest
    static void testInsertAccount() {
        String csv =
            'Name,Phone\n' +
            'Imported Account,0999999999';

        Test.startTest();
        Map<String, Object> result =
            CsvImportService.importCsv('Account', toBase64(csv));
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(1, result.get('inserted'));

        Account a = getExistingAccount('Imported Account');
        System.assertEquals('0999999999', a.Phone);
    }

    /* =========================================================
       INSERT – Using field LABELS instead of API names
       ========================================================= */

    @IsTest
    static void testInsertUsingLabels() {
        String csv =
            'Account Name,Phone\n' +
            'Imported With Labels,0111111111';

        Map<String, Object> result = CsvImportService.importCsv('Account', toBase64(csv));
           
        System.assertEquals(true, result.get('success'));
        System.assertEquals(1, result.get('inserted'));
    }

    /* =========================================================
       UPDATE – UPSERT via Id column
       ========================================================= */

    @IsTest
    static void testUpdateAccountById() {
        Account existing = getExistingAccount('Existing Account 1');

        String csv =
            'Id,Name,Phone\n' +
            existing.Id + ',Updated Account,0666666666';

        Map<String, Object> result =
            CsvImportService.importCsv('Account', toBase64(csv));

        System.assertEquals(true, result.get('success'));

        Account updated = [
            SELECT Name, Phone
            FROM Account
            WHERE Id = :existing.Id
        ];
        System.assertEquals('Updated Account', updated.Name);
        System.assertEquals('0666666666', updated.Phone);
    }

    /* =========================================================
       ERROR – Unknown column
       ========================================================= */

    @IsTest
    static void testUnknownColumnError() {
        String csv =
            'Name,Unknown_Field\n' +
            'Bad Row,XXX';

        Map<String, Object> result =
            CsvImportService.importCsv('Account', toBase64(csv));

        System.assertEquals(false, result.get('success'));

        List<String> errors = (List<String>) result.get('errors');
        System.assertEquals(1, errors.size());
        System.assert(
            errors[0].contains('unknow column'),
            'Expected unknown column error'
        );
    }

    /* =========================================================
       Exception – Null parameters
       ========================================================= */
    @IsTest
    static void testMissingParameters() {
        try {
            CsvImportService.importCsv(null, null);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {

        }
    }
    /* =========================================================
       Error – Unknown Object
       ========================================================= */
    @IsTest
    static void testUnknownObject() {
        String csv = 'Name\nTest';

        try {
            CsvImportService.importCsv('FakeObject__c', EncodingUtil.base64Encode(Blob.valueOf(csv)));
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {

        }
    }

    /* =========================================================
       Error – CSV File
       ========================================================= */
    @IsTest
    static void testMaxLinesExceeded() {
        String header = 'Name\n';
        String body = '';

        for (Integer i = 0; i <= 5000; i++) {
            body += 'Account ' + i + '\n';
        }

        try {
            CsvImportService.importCsv(
                'Account',
                EncodingUtil.base64Encode(Blob.valueOf(header + body))
            );
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {

        }
    }

    @IsTest
    static void testEmptyCsv() {
        try {
            CsvImportService.importCsv('Account', EncodingUtil.base64Encode(Blob.valueOf('')));
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {

        }
    }

    @IsTest
    static void testIncorrectColumnCount() {
        String csv =
            'Name,Phone\n' +
            'OnlyOneValue';

        Map<String, Object> result =
            CsvImportService.importCsv('Account', toBase64(csv));

        System.assertEquals(false, result.get('success'));

        List<String> errors = (List<String>) result.get('errors');
        System.assert(
            errors[0].contains('incorrect number of columns'),
            'Expected column count error'
        );
    }

    /* =========================================================
       Cast Values Types
       ========================================================= */
    @IsTest
    static void testStringCastToDateTime() {
        Object dateVal =
            CsvImportService.castToCorrectType(
                Account.CreatedDate.getDescribe(),
                '2023-01-01 10:30:00'
            );

        System.assert(dateVal instanceof Datetime);
    }

    @IsTest
    static void testInvalidBooleanCast() {
        Schema.DescribeFieldResult dfr = Account.IsDeleted.getDescribe(); 
        Object result = CsvImportService.castToCorrectType(dfr, 'maybe');
        System.assertEquals(null, result);
    }
    /* =========================================================
       Picklist 
       ========================================================= */
    @IsTest
    static void testPicklistLabelAccepted() {
        Schema.DescribeFieldResult dfr =
            Account.Rating.getDescribe();

        Boolean ok =
            CsvImportService.isValidPicklistValue(dfr, 'Hot');

        System.assertEquals(true, ok);
    }

    @IsTest
    static void testInvalidPicklist() {
        String csv =
            'Name,Rating\n' +
            'Bad Picklist,INVALID_VALUE';

        Map<String, Object> result =
            CsvImportService.importCsv('Account', toBase64(csv));

        System.assertEquals(false, result.get('success'));

        List<String> errors = (List<String>) result.get('errors');
        System.assert(
            errors[0].contains('invalid picklist value'),
            'Expected invalid picklist error'
        );
    }

}