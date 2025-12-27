@isTest
private class CsvImportServiceTest {

    /* =========================================================
       Test data setup (executed once for the whole class)
       ========================================================= */
    @testSetup
    static void setupData() {
        insert new List<Account>{
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
    }

    /* =========================================================
       Helpers
       ========================================================= */

    private static String toBase64(String csv) {
        return EncodingUtil.base64Encode(Blob.valueOf(csv));
    }

    private static Account getAccountByName(String name) {
        return [
            SELECT Id, Name, Phone
            FROM Account
            WHERE Name = :name
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

        Map<String, Object> result =
            CsvImportService.importCsv('Account', toBase64(csv), null);

        System.assertEquals(true, result.get('success'));
        System.assertEquals(1, result.get('inserted'));

        Account a = getAccountByName('Imported Account');
        System.assertEquals('0999999999', a.Phone);
    }

    /* =========================================================
       INSERT – Using field LABELS
       ========================================================= */
    @IsTest
    static void testInsertUsingLabels() {
        String csv =
            'Account Name,Phone\n' +
            'Imported With Labels,0111111111';

        Map<String, Object> result =
            CsvImportService.importCsv('Account', toBase64(csv), null);

        System.assertEquals(true, result.get('success'));
        System.assertEquals(1, result.get('inserted'));
    }

    /* =========================================================
       INSERT – Missing required field (Name)
       ========================================================= */
    @IsTest
    static void testInsertMissingRequiredField() {
        String csv =
            'Phone\n' +
            '0666666666';

        Map<String, Object> result =
            CsvImportService.importCsv('Account', toBase64(csv), null);

        System.assertEquals(false, result.get('success'));

        List<String> errors = (List<String>) result.get('errors');
        System.assert(
            errors[0].contains('required field missing'),
            'Expected missing required field error'
        );
    }

    /* =========================================================
       UPDATE – Upsert via Id (required fields NOT enforced)
       ========================================================= */
    @IsTest
    static void testUpdateAccountById() {
        Account existing = getAccountByName('Existing Account 1');

        String csv =
            'Id,Name\n' +
            existing.Id + ',abc';

        Map<String, Object> result =
            CsvImportService.importCsv('Account', toBase64(csv), null);

        System.assertEquals(true, result.get('success'));

        Account updated = [
            SELECT Name
            FROM Account
            WHERE Id = :existing.Id
        ];
        System.assertEquals('abc', updated.Name);
    }

    /* =========================================================
       ERROR – Unmapped column
       ========================================================= */
    @IsTest
    static void testUnmappedColumn() {
        String csv =
            'Name,UnknownColumn\n' +
            'Bad Row,XXX';

        Map<String, Object> result =
            CsvImportService.importCsv('Account', toBase64(csv), null);

        System.assertEquals(false, result.get('success'));

        List<String> errors = (List<String>) result.get('errors');
        System.assert(errors[0].contains('Unmapped CSV column'));
    }

    /* =========================================================
       ERROR – Incorrect column count
       ========================================================= */
    @IsTest
    static void testIncorrectColumnCount() {
        String csv =
            'Name,Phone\n' +
            'OnlyOneValue';

        Map<String, Object> result =
            CsvImportService.importCsv('Account', toBase64(csv), null);

        System.assertEquals(false, result.get('success'));

        List<String> errors = (List<String>) result.get('errors');
        System.assert(errors[0].contains('incorrect number of columns'));
    }

    /* =========================================================
       ERROR – Invalid picklist
       ========================================================= */
    @IsTest
    static void testInvalidPicklist() {
        String csv =
            'Name,Rating\n' +
            'Bad Picklist,INVALID_VALUE';

        Map<String, Object> result =
            CsvImportService.importCsv('Account', toBase64(csv), null);

        System.assertEquals(false, result.get('success'));

        List<String> errors = (List<String>) result.get('errors');
        System.assert(errors[0].contains('invalid picklist value'));
    }

    /* =========================================================
       PICKLIST – Label accepted
       ========================================================= */
    @IsTest
    static void testPicklistLabelAccepted() {
        Schema.DescribeFieldResult dfr =
            Account.Rating.getDescribe();

        Boolean ok =
            CsvImportService.isValidPicklistValue(dfr, 'Hot');

        System.assertEquals(true, ok);
    }

    /* =========================================================
       CAST – DateTime
       ========================================================= */
    @IsTest
    static void testCastDateTime() {
        Object val =
            CsvImportService.castToCorrectType(
                Account.CreatedDate.getDescribe(),
                '2023-01-01 10:30:00'
            );

        System.assert(val instanceof Datetime);
    }

    /* =========================================================
       CAST – Invalid Boolean
       ========================================================= */
    @IsTest
    static void testInvalidBooleanCast() {
        Object val =
            CsvImportService.castToCorrectType(
                Account.IsDeleted.getDescribe(),
                'maybe'
            );

        System.assertEquals(null, val);
    }

    /* =========================================================
       EXCEPTIONS
       ========================================================= */
    @IsTest
    static void testMissingParameters() {
        try {
            CsvImportService.importCsv(null, null, null);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testUnknownObject() {
        try {
            CsvImportService.importCsv(
                'FakeObject__c',
                toBase64('Name\nTest'),
                null
            );
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testMaxLinesExceeded() {
        String csv = 'Name\n';
        for (Integer i = 0; i <= 5000; i++) {
            csv += 'Account ' + i + '\n';
        }

        try {
            CsvImportService.importCsv('Account', toBase64(csv), null);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

}
