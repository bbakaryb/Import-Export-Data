
@isTest
private class CsvUtilsTest {

/* =========================================================
       Tests for escape()
       ========================================================= */

    @IsTest
    static void testEscape_NullValue() {
        String result = CsvUtils.escape(null);
        System.assertEquals('', result, 'Null input should return empty string');
    }

    @IsTest
    static void testEscape_SimpleText() {
        String result = CsvUtils.escape('Hello');
        System.assertEquals('Hello', result);
    }

    @IsTest
    static void testEscape_TextWithComma() {
        String result = CsvUtils.escape('Hello,World');
        System.assertEquals('"Hello,World"', result);
    }

    @IsTest
    static void testEscape_TextWithQuotes() {
        String result = CsvUtils.escape('He said "Hello"');
        System.assertEquals('"He said ""Hello"""', result);
    }

    @IsTest
    static void testEscape_TextWithLineBreaks() {
        String result = CsvUtils.escape('Hello\nWorld');
        System.assertEquals('Hello World', result);
    }

    @IsTest
    static void testEscape_TextWithParentheses() {
        String result = CsvUtils.escape('(48.8566,2.3522)');
        System.assertEquals('"48.8566,2.3522"', result);
    }

    /* =========================================================
       Tests for parseLine()
       ========================================================= */

    @IsTest
    static void testParseLine_Simple() {
        List<String> result = CsvUtils.parseLine('a,b,c');
        System.assertEquals(3, result.size());
        System.assertEquals('a', result[0]);
        System.assertEquals('b', result[1]);
        System.assertEquals('c', result[2]);
    }

    @IsTest
    static void testParseLine_CommaInsideQuotes() {
        List<String> result = CsvUtils.parseLine('"a,b",c');
        System.assertEquals(2, result.size());
        System.assertEquals('a,b', result[0]);
        System.assertEquals('c', result[1]);
    }

    @IsTest
    static void testParseLine_EscapedQuotes() {
        List<String> result = CsvUtils.parseLine('"a""b",c');
        System.assertEquals(2, result.size());
        System.assertEquals('a"b', result[0]);
        System.assertEquals('c', result[1]);
    }

    @IsTest
    static void testParseLine_EmptyValues() {
        List<String> result = CsvUtils.parseLine('a,,c');
        System.assertEquals(3, result.size());
        System.assertEquals('a', result[0]);
        System.assertEquals('', result[1]);
        System.assertEquals('c', result[2]);
    }

    /* =========================================================
       Tests for parse()
       ========================================================= */

    @IsTest
    static void testParse_MultipleLines() {
        String csv =
            'a,b,c\n' +
            '1,2,3\n' +
            '"x,y",z';

        List<List<String>> rows = CsvUtils.parse(csv);

        System.assertEquals(3, rows.size());
        System.assertEquals('a', rows[0][0]);
        System.assertEquals('1', rows[1][0]);
        System.assertEquals('x,y', rows[2][0]);
    }

    @IsTest
    static void testParse_IgnoresEmptyLines() {
        String csv =
            'a,b,c\n\n1,2,3\r\n\r\n';

        List<List<String>> rows = CsvUtils.parse(csv);

        System.assertEquals(2, rows.size());
    }

}