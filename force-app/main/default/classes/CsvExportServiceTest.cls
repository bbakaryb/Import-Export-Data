@isTest
private class CsvExportServiceTest {

/* =========================================================
       Test data setup
       ========================================================= */
    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'Test CSV Export',
            Phone = '0123456789',
            NumberOfEmployees = 10
        );
        insert acc;
    }

    /* =========================================================
       Nominal export test
       ========================================================= */
    @IsTest
    static void testExportCsvSuccess() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<String> fields = new List<String>{
            'Name',
            'Phone',
            'NumberOfEmployees'
        };

        Test.startTest();
        String base64Csv =
            CsvExportService.exportCsv(
                'Account',
                fields,
                acc.Id
            );
        Test.stopTest();

        System.assertNotEquals(null, base64Csv);

        String decoded =
            EncodingUtil.base64Decode(base64Csv).toString();

        System.assert(
            decoded.contains('Test CSV Export'),
            'CSV must contain account name'
        );
    }

    /* =========================================================
       CSV escaping test
       ========================================================= */
    @IsTest
    static void testCsvEscaping() {
        Account acc = new Account(
            Name = 'ACME, "Corp"',
            Phone = '01,23'
        );
        insert acc;

        List<String> fields = new List<String>{ 'Name', 'Phone' };

        String base64Csv =
            CsvExportService.exportCsv(
                'Account',
                fields,
                acc.Id
            );

        String csv =
            EncodingUtil.base64Decode(base64Csv).toString();

        System.assert(
            csv.contains('"ACME, ""Corp"""'),
            'Comma and quotes must be escaped'
        );
    }

    /* =========================================================
       Field filtering (unknown / inaccessible fields)
       ========================================================= */
    @IsTest
    static void testUnknownFieldIgnored() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<String> fields = new List<String>{
            'Name',
            'DoesNotExist__c'
        };

        String base64Csv =
            CsvExportService.exportCsv(
                'Account',
                fields,
                acc.Id
            );

        String csv =
            EncodingUtil.base64Decode(base64Csv).toString();

        System.assert(
            csv.startsWith('Account Name'),
            'Only valid fields should be included'
        );
    }

    /* =========================================================
       Error: empty field list
       ========================================================= */
    @IsTest
    static void testEmptyFieldsThrows() {
        try {
            CsvExportService.exportCsv(
                'Account',
                new List<String>(),
                null
            );
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {

        }
    }

    /* =========================================================
       Error: unknown object
       ========================================================= */
    @IsTest
    static void testUnknownObjectThrows() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        try {
            CsvExportService.exportCsv(
                'Unknown__c',
                new List<String>{ 'Name' },
                acc.Id
            );
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {

        }
    }
}